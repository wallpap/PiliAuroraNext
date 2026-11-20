import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/application/topic_header.dart';
import 'package:pili_aurora_next/features/community/application/topic_queries.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  late ProviderContainer container;
  late DynamicsUpdates updates;
  LoginAccount account(int id, [String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$id', 'bili_jct': csrf}),
    null,
    null,
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Map<String, Object?> top(String name, {bool favorite = false}) => {
    'code': 0,
    'data': {
      'top_details': {
        'topic_item': {
          'id': 12,
          'name': name,
          'fav': 2,
          'like': 3,
          'is_fav': favorite,
          'is_like': false,
        },
      },
    },
  };
  Map<String, Object?> feed(
    List<String> ids, {
    String offset = '',
    bool more = false,
    bool fold = false,
    int? sort,
  }) => {
    'code': 0,
    'data': {
      'topic_card_list': {
        'has_more': more,
        'offset': offset,
        if (sort != null) 'topic_sort_by_conf': {'show_sort_by': sort},
        'items': [
          for (final id in ids)
            {
              'dynamic_card_item': {'id_str': id},
            },
          if (fold)
            {
              'fold_card_item': {'fold_count': 1, 'fold_desc': '展开更多'},
            },
        ],
      },
    },
  };
  final header = topicHeaderProvider('12');
  TopicQuery query([int sort = 0]) => (owner: Object(), id: '12', sort: sort);
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account(1);
    Accounts.accountMode[AccountType.recommend.index] = account(2);
    updates = DynamicsUpdates();
    container = ProviderContainer(
      overrides: [dynamicsUpdatesProvider.overrideWithValue(updates)],
    );
  });
  tearDown(() async {
    container.dispose();
    for (final request in requests) {
      if (!request.reply.isCompleted) request.reply.complete({'code': -1});
    }
    await tick();
    await updates.close();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('头部刷新隔离乱序，失败保留快照，关闭后不接收迟到结果', () async {
    final subscription = container.listen(header, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(top('初始'));
    await tick();
    final actions = container.read(header.notifier);
    final old = actions.refresh();
    final fresh = actions.refresh();
    await interceptor.waitForRequests(3);
    expect(container.read(header).loading.data!.topicItem!.name, '初始');
    requests[2].reply.complete(top('最新'));
    await fresh;
    requests[1].reply.complete(top('过期'));
    await old;
    expect(container.read(header).loading.data!.topicItem!.name, '最新');
    final failure = actions.refresh();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({'code': -403, 'message': '刷新失败'});
    await failure;
    expect(container.read(header).loading.data!.topicItem!.name, '最新');
    expect(container.read(header).error?.errMsg, '刷新失败');
    final pending = actions.refresh();
    await interceptor.waitForRequests(5);
    subscription.close();
    await container.pump();
    requests[4].reply.complete(top('已关闭'));
    await pending;
  });

  test('头部固定主账号，内容固定推荐账号，同 UID 新凭据使旧查询失效', () async {
    final provider = topicFeedProvider(query());
    container
      ..listen(header, (_, _) {})
      ..listen(provider, (_, _) {});
    await interceptor.waitForRequests(2);
    final replacement = account(1, 'main-new');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(4);
    final topRequest = requests.lastWhere(
      (r) => r.options.path == Api.topicTop,
    );
    expect(topRequest.options.extra['account'], same(replacement));
    topRequest.reply.complete(top('新主账号'));
    final recommend = account(2, 'recommend-new');
    Accounts.replaceCredentials(recommend);
    await interceptor.waitForRequests(5);
    expect(requests.last.options.path, Api.topicFeed);
    expect(requests.last.options.extra['account'], same(recommend));
    requests.last.reply.complete(feed(['new']));
    for (final request in requests.where((r) => !r.reply.isCompleted)) {
      request.reply.complete(
        request.options.path == Api.topicTop ? top('旧账号') : feed(['old']),
      );
    }
    await tick();
    expect(container.read(header).loading.data!.topicItem!.name, '新主账号');
    expect(
      container.read(provider).loading.data.single.dynamicCardItem!.idStr,
      'new',
    );
  });

  test('收藏与点赞互斥重复提交，待确认保留计数，成功通知收藏库', () async {
    container.listen(header, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(top('话题'));
    await tick();
    final actions = container.read(header.notifier);
    final before = container.read(header).loading.data!.topicItem!;
    var writes = 0;
    final sub = container
        .read(favoriteLibraryProvider)
        .changes
        .listen((_) => writes++);
    addTearDown(sub.cancel);
    final uncertain = actions.toggle(favorite: true);
    expect(await actions.toggle(favorite: true), isA<Error>());
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': '0'});
    expect(await uncertain, isA<UnknownResult>());
    expect(container.read(header).loading.data!.topicItem!.fav, 2);
    final confirmed = actions.toggle(favorite: true);
    await interceptor.waitForRequests(3);
    requests[2].reply.complete({'code': 0});
    expect(await confirmed, isA<Success>());
    expect(container.read(header).loading.data!.topicItem!.fav, 3);
    expect(container.read(header).loading.data!.topicItem!.isFav, true);
    expect(before.fav, 2);
    expect(writes, 1);
    final like = actions.toggle(favorite: false);
    expect(await actions.toggle(favorite: false), isA<Error>());
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({'code': 0});
    expect(await like, isA<Success>());
    expect(container.read(header).loading.data!.topicItem!.like, 4);
    expect(container.read(header).loading.data!.topicItem!.isFav, true);
  });

  test('已确认写入遇到刷新仍交付成功，并重查新详情而不修改旧快照', () async {
    container.listen(header, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(top('旧详情'));
    await tick();
    final actions = container.read(header.notifier);
    final pending = actions.toggle(favorite: false);
    final refresh = actions.refresh();
    await interceptor.waitForRequests(3);
    final read = requests.lastWhere((r) => r.options.path == Api.topicTop);
    read.reply.complete(top('刷新详情'));
    await refresh;
    final refreshed = container.read(header).loading.data;
    requests.lastWhere((r) => r.options.path == Api.likeTopic).reply.complete({
      'code': 0,
    });
    expect(await pending, isA<Success>());
    await interceptor.waitForRequests(4);
    expect(refreshed!.topicItem!.like, 3);
    requests.last.reply.complete(top('确认后的详情'));
    await tick();
    expect(container.read(header).loading.data!.topicItem!.name, '确认后的详情');
  });

  test('离页重开仍保留在途写入锁，旧账号写入不能更改新账号状态', () async {
    var sub = container.listen(header, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(top('初始'));
    await tick();
    final old = container.read(header.notifier).toggle(favorite: false);
    await interceptor.waitForRequests(2);
    sub.close();
    await container.pump();
    sub = container.listen(header, (_, _) {});
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(top('重开'));
    await tick();
    expect(
      await container.read(header.notifier).toggle(favorite: false),
      isA<Error>(),
    );
    expect(requests, hasLength(3));
    Accounts.replaceCredentials(account(1, 'new'));
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(top('新账号'));
    await tick();
    requests[1].reply.complete({'code': 0});
    expect(await old, isA<Success>());
    expect(container.read(header).loading.data!.topicItem!.like, 3);
    sub.close();
  });

  test('离页完成的点赞通知已重开详情核对', () async {
    final first = container.listen(header, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(top('旧页面'));
    await tick();
    final pending = container.read(header.notifier).toggle(favorite: false);
    await interceptor.waitForRequests(2);
    first.close();
    await container.pump();
    container.listen(header, (_, _) {});
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(top('重新打开'));
    await tick();
    requests[1].reply.complete({'code': 0});
    expect(await pending, isA<Success>());
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(top('写入后核对'));
    await tick();
    expect(container.read(header).loading.data!.topicItem!.name, '写入后核对');
  });

  test('分页失败重试原游标，展开保留并发续页，刷新保持排序与快照', () async {
    final provider = topicFeedProvider(query());
    container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(
      feed(['1'], offset: 'a', more: true, fold: true, sort: 2),
    );
    await tick();
    final actions = container.read(provider.notifier);
    final fold = actions.unfold();
    final page = actions.onLoadMore();
    await interceptor.waitForRequests(3);
    expect(requests[2].options.queryParameters['offset'], 'a');
    requests[2].reply.complete(feed(['3'], offset: 'b', more: true));
    await page;
    requests[1].reply.complete(feed(['1', '2']));
    expect(await fold, isA<Success>());
    expect(
      container
          .read(provider)
          .loading
          .data
          .map((e) => e.dynamicCardItem!.idStr),
      ['1', '2', '3'],
    );
    final failed = actions.onLoadMore();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete({'code': -403, 'message': '失败'});
    await failed;
    await actions.onLoadMore();
    expect(requests, hasLength(4));
    final retry = actions.retry();
    await interceptor.waitForRequests(5);
    expect(requests[4].options.queryParameters['offset'], 'b');
    requests[4].reply.complete(feed(['4'], offset: 'b', more: true));
    await retry;
    expect(container.read(provider).hasMore, false);
    final refresh = actions.onRefresh();
    await interceptor.waitForRequests(6);
    expect(requests.last.options.queryParameters['sort_by'], 2);
    expect(requests.last.options.queryParameters.containsKey('offset'), false);
    expect(container.read(provider).loading.data, hasLength(4));
    requests.last.reply.complete({'code': -403});
    await refresh;
    expect(container.read(provider).loading.data, hasLength(4));
  });

  test('刷新、切号和查询释放废弃旧展开；发布刷新，删除排除迟到结果', () async {
    final provider = topicFeedProvider(query());
    final sub = container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(feed(['1'], fold: true));
    await tick();
    final actions = container.read(provider.notifier);
    final fold = actions.unfold();
    final refresh = actions.onRefresh();
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(feed(['new']));
    await refresh;
    requests[1].reply.complete(feed(['old-fold']));
    expect(await fold, isA<Error>());
    expect(
      container.read(provider).loading.data.single.dynamicCardItem!.idStr,
      'new',
    );
    updates.published(Accounts.main);
    await interceptor.waitForRequests(4);
    updates.removed(Accounts.main, 'removed');
    requests[3].reply.complete(feed(['removed', 'kept']));
    await tick();
    expect(
      container.read(provider).loading.data.single.dynamicCardItem!.idStr,
      'kept',
    );
    sub.close();
    await container.pump();
    updates.published(Accounts.main);
    await tick();
    expect(requests, hasLength(4));
  });

  test('新快照可继续展开，旧展开不占用刷新后操作也不覆盖结果', () async {
    final provider = topicFeedProvider(query());
    container.listen(provider, (_, _) {});
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(feed([], fold: true));
    await tick();
    final actions = container.read(provider.notifier);
    final oldFold = actions.unfold();
    final refresh = actions.onRefresh();
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(feed(['new'], fold: true));
    await refresh;
    final newFold = actions.unfold();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(feed(['new-fold']));
    expect(await newFold, isA<Success>());
    requests[1].reply.complete(feed(['old-fold']));
    expect(await oldFold, isA<Error>());
    expect(
      container
          .read(provider)
          .loading
          .data
          .map((item) => item.dynamicCardItem!.idStr),
      ['new', 'new-fold'],
    );
  });

  test('面板实例与关键词隔离，防抖前废弃旧结果，关闭后停止调度', () async {
    final old = topicSearchProvider((
      owner: Object(),
      keyword: '旧',
      debounce: false,
    ));
    final oldSub = container.listen(old, (_, _) {});
    await interceptor.waitForRequests(1);
    oldSub.close();
    final current = topicSearchProvider((
      owner: Object(),
      keyword: '新',
      debounce: true,
    ));
    final sub = container.listen(current, (_, _) {});
    await container.pump();
    requests[0].reply.complete({
      'code': 0,
      'data': {
        'topic_items': [
          {'id': 1, 'name': '过期'},
        ],
      },
    });
    await tick();
    expect(container.read(current).loading, isA<Loading>());
    sub.close();
    await container.pump();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(requests, hasLength(1));
    final mention = mentionSearchProvider((
      owner: Object(),
      keyword: '用户',
      debounce: false,
    ));
    container.listen(mention, (_, _) {});
    await interceptor.waitForRequests(2);
    Accounts.replaceCredentials(account(1, 'replacement'));
    await interceptor.waitForRequests(3);
    requests[2].reply.complete({
      'code': 0,
      'data': {
        'groups': [
          {'group_name': '新账号'},
        ],
      },
    });
    requests[1].reply.complete({
      'code': 0,
      'data': {
        'groups': [
          {'group_name': '旧账号'},
        ],
      },
    });
    await tick();
    expect(container.read(mention).loading.data.single.groupName, '新账号');
  });
}
