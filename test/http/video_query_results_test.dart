import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/data/video_note_repository.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/features/content_discovery/data/recommendation_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/data/related_video_repository.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  Object? body;
  bool fail = false;
  void Function(RequestOptions)? onRequest;
  final queries = <Future<LoadingState<Object?>> Function()>[
    () => VideoHttp.rcmdVideoList(ps: 20, freshIdx: 0),
    () => VideoHttp.rcmdVideoListApp(freshIdx: 0),
    () => VideoHttp.hotVideoList(pn: 1, ps: 20),
    () => VideoHttp.videoIntro(bvid: 'BV-test'),
    () => RelatedVideoRepository.load(
      Accounts.get(AccountType.recommend),
      'BV-test',
    ),
    () => VideoHttp.onlineTotal(bvid: 'BV-test', cid: 1),
    () => VideoHttp.playInfo(bvid: 'BV-test', cid: 1),
    () => VideoHttp.getRankVideoList(0),
    () => VideoHttp.pgcRankList(seasonType: 1),
    () => VideoHttp.pgcSeasonRankList(seasonType: 2),
    () => VideoNoteRepository.list(Accounts.main, 1, 1),
    VideoHttp.popularSeriesList,
    () => VideoHttp.popularSeriesOne(number: 1),
    () => VideoHttp.popularPrecious(page: 1),
    () => VideoHttp.tvPlayUrl(cid: 1, objectId: 1, playurlType: 1),
  ];
  LoginAccount account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture-csrf'}),
    'fixture-$mid',
    null,
  );
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            onRequest?.call(options);
            if (fail) {
              handler.reject(
                DioException(requestOptions: options, type: .connectionError),
              );
            } else {
              handler.resolve(Response(requestOptions: options, data: body));
            }
          },
        ),
      );
  });
  setUp(() async {
    requests.clear();
    fail = false;
    onRequest = null;
    body = null;
    for (final type in AccountType.values) {
      Accounts.accountMode[type.index] = account(type.index + 1);
    }
    await GStorage.localCache.putAll({
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: 'fixture-key',
    });
  });
  tearDownAll(() => Request.dio.close(force: true));
  test(
    'discovery decodes each page with the saved title and zone filters',
    () async {
      addTearDown(() async {
        await GStorage.setting.delete(SettingBoxKey.banWordForRecommend);
        await GStorage.setting.delete(SettingBoxKey.banWordForZone);
      });
      Map<String, dynamic> video(String title, String zone) => {
        'title': title,
        'tname': zone,
        'duration': 90,
        'owner': {'mid': 1},
        'stat': {'like': 20, 'view': 100},
      };
      body = {
        'code': 0,
        'data': {
          'list': [
            video('Spoiler', 'Video'),
            video('Demo', 'Game'),
            video('Saved', 'Video'),
          ],
        },
      };
      await GStorage.setting.putAll({
        SettingBoxKey.banWordForRecommend: 'spoiler',
        SettingBoxKey.banWordForZone: 'game',
      });
      expect(
        (await VideoHttp.hotVideoList(
          pn: 1,
          ps: 20,
        )).data.map((item) => item.title),
        ['Saved'],
      );
      await GStorage.setting.put(SettingBoxKey.banWordForRecommend, '[');
      expect(
        (await VideoHttp.getRankVideoList(0)).data.map((item) => item.title),
        ['Spoiler', 'Saved'],
      );
    },
  );
  test('15类视频查询保留拒绝码，非法响应和传输失败通过结果交付', () async {
    for (final query in queries) {
      body = {'code': -403, 'message': '拒绝查询'};
      final rejected = await query() as Error;
      expect(rejected.code, -403);
      body = {'code': 0, 'data': 'private malformed data', 'result': 1};
      final malformed = await query() as Error;
      expect(malformed.cause, isNotNull);
      expect(malformed.stackTrace, isNotNull);
      expect(malformed.toString(), isNot(contains('private malformed data')));
      fail = true;
      final transport = await query() as Error;
      expect(transport.cause, isA<DioException>());
      expect(transport, isNot(isA<UnknownResult>()));
      fail = false;
    }
  });
  test('推荐与榜单等列表保留已有空语义，损坏每周期数拒绝进入页面', () async {
    body = {
      'code': 0,
      'data': {'item': [], 'items': [], 'list': []},
      'result': {'list': []},
    };
    for (final query in [
      queries[0],
      queries[1],
      queries[2],
      queries[7],
      queries[8],
      queries[9],
      queries[11],
    ]) {
      expect((await query()).data, isEmpty);
    }
    body = {'code': 0, 'data': null, 'result': null};
    expect(
      (await RelatedVideoRepository.load(
        Accounts.get(AccountType.recommend),
        'BV-test',
      )).data.items,
      isEmpty,
    );
    for (final query in [queries[8], queries[9], queries[11]]) {
      expect(await query(), isA<Success<Object?>>());
      expect((await query()).data, isNull);
    }
    body = {
      'code': 0,
      'data': {
        'list': [<String, dynamic>{}],
      },
    };
    final invalid = await VideoHttp.popularSeriesList() as Error;
    expect(invalid.cause, isA<FormatException>());
  });
  test('推荐数据接口始终使用显式账号与取消令牌', () async {
    final captured = account(80);
    Accounts.accountMode[AccountType.recommend.index] = account(99);
    body = {
      'code': 0,
      'data': {'item': [], 'items': []},
    };
    for (final app in [false, true]) {
      final token = CancelToken();
      final result = await const RecommendationRepository().page(
        account: captured,
        app: app,
        index: 3,
        pageSize: 40,
        cancelToken: token,
      );
      expect(result.data, isEmpty);
      expect(requests.last.extra['account'], same(captured));
      expect(requests.last.cancelToken, same(token));
      expect(requests.last.queryParameters[app ? 'idx' : 'fresh_idx'], 3);
      if (!app) expect(requests.last.queryParameters['ps'], 40);
    }
  });
  test('签名等待期间固定发起账号，资料读取保留显式账号的禁重试约定', () async {
    final original = Accounts.get(AccountType.recommend);
    await GStorage.localCache.delete(LocalCacheKey.mixinKey);
    onRequest = (options) {
      if (options.path == Api.userInfo) {
        Accounts.accountMode[AccountType.recommend.index] = account(99);
        body = {
          'code': 0,
          'data': {
            'wbi_img': {
              'img_url':
                  'https://fixture.test/01234567890123456789012345678901.png',
              'sub_url':
                  'https://fixture.test/01234567890123456789012345678901.png',
            },
          },
        };
      } else {
        body = {
          'code': 0,
          'data': {'item': []},
        };
      }
    };
    expect((await queries.first()).isSuccess, isTrue);
    expect(requests.last.extra['account'], same(original));
    onRequest = null;
    body = {'code': -404};
    await VideoHttp.videoIntro(bvid: 'BV-test', account: original);
    expect(requests.last.extra['account'], same(original));
    expect(requests.last.extra['noRetry'], isTrue);
  });
  test('发现模块显式账号优先于当前推荐角色，全部 Adapter 沿用捕获凭据', () async {
    final owner = account(88);
    body = {
      'code': 0,
      'data': {'list': []},
      'result': {'list': []},
    };
    final captured = <Future<LoadingState<Object?>> Function()>[
      () => VideoHttp.hotVideoList(pn: 1, ps: 20, account: owner),
      () => VideoHttp.getRankVideoList(0, account: owner),
      () => VideoHttp.pgcRankList(seasonType: 1, account: owner),
      () => VideoHttp.pgcSeasonRankList(seasonType: 2, account: owner),
      () => VideoHttp.popularSeriesList(account: owner),
      () => VideoHttp.popularSeriesOne(number: 1, account: owner),
      () => VideoHttp.popularPrecious(page: 1, account: owner),
    ];
    for (final query in captured) {
      expect((await query()).isSuccess, isTrue);
      expect(requests.last.extra['account'], same(owner));
    }
  });
  test('取消查询不分发，签名准备失败保留原始原因', () async {
    final token = CancelToken()..cancel();
    final cancelled = await VideoHttp.rcmdVideoList(
      ps: 20,
      freshIdx: 0,
      cancelToken: token,
    ) as Error;
    expect(cancelled.cause, isA<DioException>());
    expect(requests, isEmpty);
    await GStorage.localCache.put(
      LocalCacheKey.timeStamp,
      'invalid cached timestamp',
    );
    final failed = await VideoHttp.videoIntro(bvid: 'BV-test') as Error;
    expect(failed.cause, isA<TypeError>());
    expect(failed.stackTrace, isNotNull);
    expect(requests, isEmpty);
  });
}
