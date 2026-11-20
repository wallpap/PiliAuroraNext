import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/features/member_space/domain/archive_order_type_web.dart';
import 'package:pili_aurora_next/features/member_space/domain/archive_sort_type_app.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_id.dart';
import 'package:pili_aurora_next/features/member_space/domain/contribute_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/web_ss_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/application/space_archive.dart';
import 'package:pili_aurora_next/features/member_space/application/space_web.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/search.dart';
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
  final appQuery = (
    owner: Object(),
    mid: 2,
    type: ContributeType.video,
    season: null as int?,
    series: null as int?,
  );
  final webQuery = (
    owner: Object(),
    mid: 2,
    type: null as WebSsType?,
    id: null as Object?,
  );
  final app = spaceArchiveProvider(appQuery);
  final web = spaceWebProvider(webQuery);
  LoginAccount account(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;
  Map<String, dynamic> page(String label, {bool episodic = false}) => {
    'code': 0,
    'data': <String, dynamic>{
      'count': 1,
      if (episodic)
        'episodic_button': {'text': '继续播放', 'uri': 'bilibili://video?oid=1'},
      'has_next': false,
      'item': [
        {'param': label, 'title': label},
      ],
    },
  };
  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox({
      LocalCacheKey.mixinKey: 'synthetic',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
    });
    Accounts.account = MemoryBox<LoginAccount>();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    container = ProviderContainer.test();
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account('old');
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  for (final kind in ['video', 'web']) {
    final isWeb = kind == 'web';
    ProviderSubscription<Object?> create() => isWeb
        ? container.listen(web, (_, _) {})
        : container.listen(app, (_, _) {});
    LoadingState<List<BaseSimpleVideoItemModel>> loading() =>
        isWeb ? container.read(web).loading : container.read(app).loading;
    Future<void> refresh() => isWeb
        ? container.read(web.notifier).refresh(clear: true)
        : container.read(app.notifier).refresh(clear: true);
    String? title() => loading().data.single.title;
    Map<String, dynamic> payload(String label) => isWeb
        ? {
            'code': 0,
            'data': {
              'page': {'count': 1},
              'list': {
                'vlist': [
                  {'title': label},
                ],
              },
            },
          }
        : page(label);
    test('$kind 同 UID 换凭据重新查询，拒绝旧响应且释放账号订阅', () async {
      final sub = create();
      await interceptor.waitForRequests(1);
      final old = Accounts.main;
      final replacement = account('new');
      Accounts.replaceCredentials(replacement);
      await interceptor.waitForRequests(2);
      expect(requests.first.options.extra['account'], same(old));
      expect(requests.last.options.extra['account'], same(replacement));
      requests.last.reply.complete(payload('new'));
      await flush();
      expect(title(), 'new');
      requests.first.reply.complete(payload('old'));
      await flush();
      expect(title(), 'new');
      sub.close();
      await container.pump();
      Accounts.replaceCredentials(account('closed'));
      await flush();
      expect(requests, hasLength(2));
    });
    test('$kind 首屏失败返回错误，可刷新重试，关闭不发布迟到结果', () async {
      final sub = create();
      await interceptor.waitForRequests(1);
      requests.first.reply.complete({'code': -403, 'message': '拒绝查询'});
      await flush();
      expect(loading(), isA<Error>());
      final retry = refresh();
      await interceptor.waitForRequests(2);
      sub.close();
      await container.pump();
      requests.last.reply.complete(payload('late'));
      await retry;
      expect(container.exists(isWeb ? web : app), isFalse);
    });
  }
  test('继续播放互斥，换凭据后的迟到查询失败不弹窗或打开视频', () async {
    container.listen(app, (_, _) {});
    final video = container.read(app.notifier);
    await interceptor.waitForRequests(1);
    requests.single.reply.complete(page('first', episodic: true));
    await flush();
    final opening = video.playback();
    expect(await video.playback(), isNull);
    await interceptor.waitForRequests(2);
    final original = Accounts.main;
    Accounts.replaceCredentials(account('replacement'));
    await interceptor.waitForRequests(3);
    requests[1].reply.complete({'code': -403, 'message': '旧账号失败'});
    expect(await opening, isNull);
    expect(requests[1].options.extra['account'], same(original));
    requests[2].reply.complete(page('replacement'));
    await flush();
    expect(container.read(app).loading.data.single.title, 'replacement');
  });

  test('观看定位与上一段请求不覆盖向后游标，上一段失败可重试', () async {
    container.listen(app, (_, _) {});
    final archive = container.read(app.notifier);
    await interceptor.waitForRequests(1);
    requests.single.reply.complete(page('30'));
    await flush();
    Map<String, dynamic> params(int i) => requests[i].options.queryParameters;
    Map<String, dynamic> segment(String label, int next) {
      final payload = page(label);
      (payload['data'] as Map<String, dynamic>).addAll({
        'next': next,
        'has_prev': true,
        'has_next': true,
      });
      return payload;
    }

    final locating = archive.refresh(clear: true, anchor: '20');
    await interceptor.waitForRequests(2);
    expect(params(1)['aid'], '20');
    expect(params(1)['include_cursor'], true);
    requests[1].reply.complete(segment('20', 101));
    await locating;

    final failed = archive.previous();
    await interceptor.waitForRequests(3);
    expect(params(2)['aid'], '20');
    expect(params(2)['sort'], 'asc');
    requests[2].reply.complete({'code': -403, 'message': '上一段失败'});
    expect(await failed, isA<Error>());
    expect(container.read(app).loading.data.single.param, '20');

    final previous = archive.previous();
    await interceptor.waitForRequests(4);
    requests[3].reply.complete(segment('30', 999));
    expect((await previous).data, 1);
    expect(container.read(app).loading.data.map((row) => row.param), [
      '30',
      '20',
    ]);
    final more = archive.more();
    await interceptor.waitForRequests(5);
    expect(params(4)['aid'], '20');
    expect(params(4)['next'], 101);
    requests[4].reply.complete(page('10'));
    await more;
    expect(container.read(app).loading.data.map((row) => row.param), [
      '30',
      '20',
      '10',
    ]);
  });

  for (final type in [null, ...WebSsType.values]) {
    test('Web $type 跳页和换排序保留各自的端点与参数', () async {
      final provider = spaceWebProvider((
        owner: Object(),
        mid: 2,
        type: type,
        id: type == null ? null : 7,
      ));
      container.listen(provider, (_, _) {});
      final archive = container.read(provider.notifier);
      final (path, pageKey, sortKey, firstSort, secondSort) = switch (type) {
        null => (Api.searchArchive, 'pn', 'order', 'pubdate', 'click'),
        WebSsType.season => (
          Api.seasonArchives,
          'page_num',
          'sort_reverse',
          false,
          true,
        ),
        WebSsType.series => (Api.seriesArchives, 'pn', 'sort', 'desc', 'asc'),
      };
      void confirm(int i, int number, Object sort) {
        final request = requests[i];
        expect(request.options.path, endsWith(path));
        final params = request.options.queryParameters;
        expect(params[pageKey].toString(), '$number');
        expect(params[sortKey], sort);
        if (type != null) expect(params['${type.name}_id'], 7);
        request.reply.complete({
          'code': 0,
          'data': type == null
              ? {
                  'page': {'count': 95},
                  'list': {
                    'vlist': [
                      {'title': '普通投稿'},
                    ],
                  },
                }
              : {
                  'page': {'total': 95},
                  'archives': [
                    {
                      'title': '合集或系列',
                      'pubdate': 1,
                      'duration': 1,
                      'stat': <String, dynamic>{},
                    },
                  ],
                },
        });
      }

      await interceptor.waitForRequests(1);
      confirm(0, 1, firstSort);
      await flush();
      expect(container.read(provider).totalPage, 4);
      final jump = archive.jump(3);
      await interceptor.waitForRequests(2);
      confirm(1, 3, firstSort);
      await jump;
      expect(container.read(provider).page, 3);
      final change = archive.selectOrder(
        type == null ? ArchiveOrderTypeWeb.click : ArchiveSortTypeApp.asc,
      );
      await interceptor.waitForRequests(3);
      confirm(2, 1, secondSort);
      await change;
      expect(container.read(provider).page, 1);
    });
  }

  test('播放全部选首个可播稿件，继续播放以服务端记录创建同一投稿队列', () async {
    container.listen(app, (_, _) {});
    final archive = container.read(app.notifier);
    await interceptor.waitForRequests(1);
    requests.single.reply.complete({
      'code': 0,
      'data': {
        'count': 2,
        'episodic_button': {'text': '播放全部', 'uri': 'bilibili://video'},
        'item': [
          {'param': '0', 'title': '不可播'},
          {
            'param': '2',
            'title': '可播',
            'bvid': IdUtils.av2bv(2),
            'first_cid': 20,
            'uri': 'bilibili://video?player_width=720&player_height=1280',
          },
        ],
      },
    });
    await flush();
    final all = (await archive.playback(username: '作者'))!.data!;
    expect(all.cid, 20);
    expect(all.isVertical, isTrue);
    expect(all.arguments, containsPair('sortField', 1));
    expect(all.arguments, containsPair('mediaId', 2));
    expect(all.arguments, containsPair('oid', IdUtils.bv2av(IdUtils.av2bv(2))));

    final refresh = archive.refresh();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(page('recent', episodic: true));
    await refresh;
    final opening = archive.playback(username: '作者');
    await interceptor.waitForRequests(3);
    expect(requests[2].options.queryParameters['aid'], 1);
    requests[2].reply.complete({
      'code': 0,
      'data': [
        {'cid': 10},
      ],
    });
    final resume = (await opening)!.data!;
    expect(resume.cid, 10);
    expect(resume.arguments, containsPair('oid', '1'));
    expect(resume.arguments, containsPair('isContinuePlaying', true));
  });

  test('分 P 结果明确区分失败与空内容，交由调用方提示', () async {
    var query = SearchHttp.pageWithDimension(aid: 1, account: Accounts.main);
    await interceptor.waitForRequests(1);
    requests.single.reply.complete({'code': -403, 'message': '拒绝查询'});
    expect(await query, isA<Error>());
    query = SearchHttp.pageWithDimension(aid: 1, account: Accounts.main);
    await interceptor.waitForRequests(2);
    requests.last.reply.complete({'code': 0, 'data': []});
    final empty = await query;
    expect(empty, isA<Success>());
    expect(empty.data, isNull);
  });
}
