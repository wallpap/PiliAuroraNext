import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/data/favorite_repository.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_order_type.dart';
import 'package:pili_aurora_next/features/subscriptions/data/hidden_media.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final repository = FavoriteRepository();
  final account = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': 'fixture'}),
    null,
    null,
  );
  final folder = {
    'id': 7,
    'mid': 1,
    'title': '测试',
    'attr': 2,
    'media_count': 42,
  };
  final requests = interceptor.requests;
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() async {
    Accounts.accountMode[AccountType.main.index] = account;
    requests.clear();
    await GStorage.setting.clear();
    await GStorage.localCache.clear();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  Future<void> reply(Map<String, dynamic> data, [int count = 1]) async {
    await interceptor.waitForRequests(count);
    expect(requests.last.options.extra['account'], same(account));
    requests.last.reply.complete({'code': 0, 'data': data});
  }

  for (final kind in [
    FavoriteKind.folders,
    FavoriteKind.article,
    FavoriteKind.topic,
    FavoriteKind.cheese,
    FavoriteKind.note,
    FavoriteKind.pgc,
  ]) {
    test('${kind.name} 以原始分页和固定账号解码', () async {
      final query = FavoriteQuery(
        owner: Object(),
        kind: kind,
        type: 1,
        status: 2,
      );
      final operation = repository.page(account, query, null);
      await reply(switch (kind) {
        FavoriteKind.folders => {
          'list': [folder],
          'count': 1,
          'has_more': false,
        },
        FavoriteKind.article => {
          'items': [
            {'opus_id': '1'},
          ],
          'has_more': false,
        },
        FavoriteKind.topic => {
          'topic_list': {
            'topic_items': [
              {'id': 1, 'name': '话题'},
            ],
            'page_info': {'total': 1},
          },
        },
        FavoriteKind.cheese => {
          'items': [
            {'season_id': 1},
          ],
          'page': {'next': false},
        },
        FavoriteKind.note => {
          'list': [
            {'note_id': 1},
          ],
        },
        FavoriteKind.pgc => {
          'list': [
            {'season_id': 1},
          ],
          'total': 1,
        },
        _ => {},
      });
      final page = await operation;
      expect(page.items, hasLength(1));
      expect(page.next, isNull);
      if (kind == FavoriteKind.pgc) {
        expect(requests.single.options.queryParameters['follow_status'], 2);
        expect(requests.single.options.queryParameters['type'], 1);
      }
    });
  }
  test('追番分页按原始条目累计到总数，不依赖固定页大小', () async {
    const query = FavoriteQuery(
      owner: Object(),
      kind: FavoriteKind.pgc,
      type: 1,
      status: 2,
    );
    final first = repository.page(account, query, null);
    await reply({
      'list': [
        {'season_id': 1},
      ],
      'total': 2,
    });
    expect((await first).next, (2, 1));
    final next = repository.page(account, query, (2, 1));
    await reply({
      'list': [
        {'season_id': 2},
      ],
      'total': 2,
    }, 2);
    expect((await next).next, isNull);
    expect(requests.last.options.queryParameters['pn'], 2);
  });
  test('详情倒序先查总数，读取尾页并反转内容；搜索显式传递筛选', () async {
    const query = FavoriteQuery(
      owner: Object(),
      kind: FavoriteKind.detail,
      mediaId: 7,
      reverse: true,
      keyword: 'keyword',
      order: FavOrderType.view,
      type: 1,
    );
    final operation = repository.page(account, query, null);
    await reply(folder);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.queryParameters, containsPair('pn', 3));
    expect(
      requests.last.options.queryParameters,
      containsPair('keyword', 'keyword'),
    );
    expect(
      requests.last.options.queryParameters,
      containsPair('order', 'view'),
    );
    await reply({
      'info': folder,
      'medias': [
        {'id': 1, 'type': 2},
        {'id': 2, 'type': 2},
      ],
      'has_more': false,
    }, 2);
    final page = await operation;
    expect(page.items.map(favoriteKey), [(2, 2), (2, 1)]);
    expect(page.next, 2);
  });
  test('详情缺少收藏夹元信息交付错误，不用空快照冒充成功', () async {
    final operation = repository.page(
      account,
      const FavoriteQuery(
        owner: Object(),
        kind: FavoriteKind.detail,
        mediaId: 7,
      ),
      null,
    );
    final check = expectLater(operation, throwsA(isA<Error>()));
    await reply({});
    await check;
  });
  test('倒序预查询期间来源释放，不再发送后续分页', () async {
    var current = true;
    final operation = repository.page(
      account,
      const FavoriteQuery(
        owner: Object(),
        kind: FavoriteKind.detail,
        mediaId: 7,
        reverse: true,
      ),
      null,
      isCurrent: () => current,
    );
    final check = expectLater(operation, throwsA(isA<Error>()));
    current = false;
    await reply(folder);
    await check;
    expect(requests, hasLength(1));
  });
  test('隐藏非所有者条目仍保留原始下一页，自己的内容不隐藏', () async {
    await GStorage.setting.put(
      SettingBoxKey.hideInvalidSubscriptionVideos,
      true,
    );
    await HiddenSubscriptionMedia(
      GStorage.localCache,
      account.mid,
    ).add(11, 7, {(1, 2)});
    const query = FavoriteQuery(
      owner: Object(),
      kind: FavoriteKind.detail,
      mediaId: 7,
    );
    final read = repository.page(account, query, null);
    await reply({
      'info': {...folder, 'mid': 2},
      'medias': [
        {'id': 1, 'type': 2},
      ],
      'has_more': true,
    });
    final filtered = await read;
    expect(filtered.items, isEmpty);
    expect(filtered.next, 2);
    final owned = repository.page(account, query, null);
    await reply({
      'info': folder,
      'medias': [
        {'id': 1, 'type': 2},
      ],
      'has_more': false,
    }, 2);
    expect((await owned).items, hasLength(1));
  });
  test('公开笔记删除固定账号及 CSRF，待确认回执不重试', () async {
    const query = FavoriteQuery(
      owner: Object(),
      kind: FavoriteKind.note,
      published: true,
    );
    final operation = repository.remove(account, query, [
      FavNoteItemModel(cvid: '12', noteId: 9),
    ]);
    await interceptor.waitForRequests(1);
    final options = requests.single.options;
    expect(options.path, Api.delPublishNote);
    expect(options.extra['account'], same(account));
    expect(options.data, containsPair('cvids', '12'));
    expect(options.data, containsPair('csrf', account.csrf));
    requests.single.reply.complete({'code': '0'});
    expect(await operation, isA<UnknownResult>());
    expect(requests, hasLength(1));
  });
}
