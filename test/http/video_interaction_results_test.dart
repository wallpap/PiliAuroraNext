import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';

import 'video_write_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final account = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': 'fixture-csrf'}),
    'fixture-access',
    null,
  );
  final fixture = VideoWriteFixture(DioExceptionType.receiveTimeout);
  final requests = fixture.requests;
  final video = IdUtils.av2bv(1);
  setUpAll(fixture.install);
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = account;
    fixture.reset();
  });
  tearDownAll(fixture.close);
  final writes = <Future<LoadingState<Object?>> Function()>[
    () => VideoHttp.coinVideo(bvid: video, multiply: 1),
    () => VideoHttp.likeVideo(bvid: video, type: true),
    () => VideoHttp.ugcTriple(bvid: video),
    () => VideoHttp.pgcTriple(epId: 1),
  ];
  test('四类写入保留拒绝码，超时仅分发一次并携带原始原因', () async {
    for (final write in writes) {
      fixture.body = {'code': -403, 'message': '拒绝互动'};
      final rejected = await write() as Error;
      expect(rejected.code, -403);
      expect(rejected, isNot(isA<UnknownResult>()));
      fixture.fail = true;
      final count = requests.length;
      final uncertain = await write() as UnknownResult;
      expect(requests, hasLength(count + 1));
      expect(uncertain.cause, isA<DioException>());
      expect(uncertain.stackTrace, isNotNull);
      expect(requests.last.extra['account'], same(account));
      expect(requests.last.extra['noRetry'], isTrue);
      fixture.fail = false;
    }
    expect(requests[4].data['csrf'], 'fixture-csrf');
    expect(requests[6].data['csrf'], 'fixture-csrf');
  });
  test('点赞确认不依赖可选提示，三连缺状态或数量不能伪造成功', () async {
    for (final data in [
      null,
      {},
      {'toast': ''},
      {'toast': 3},
    ]) {
      fixture.body = {'code': 0, 'data': data};
      expect(
        await VideoHttp.likeVideo(bvid: video, type: true),
        const Success<String?>(null),
      );
    }
    fixture.body = {
      'code': 0,
      'data': {'like': true, 'coin': true, 'fav': true, 'multiply': 1},
    };
    expect((await VideoHttp.ugcTriple(bvid: video)).data.multiply, 1);
    fixture.body = {
      'code': 0,
      'data': {'like': true, 'coin': false, 'fav': false},
    };
    expect((await VideoHttp.ugcTriple(bvid: video)).data.multiply, 0);
    for (final data in [
      {},
      {'like': true, 'coin': true, 'fav': true},
      {'like': 1, 'coin': true, 'fav': true, 'multiply': 2},
    ]) {
      fixture.body = {'code': 0, 'data': data};
      expect(await VideoHttp.ugcTriple(bvid: video), isA<UnknownResult>());
    }
    fixture.body = {
      'code': 0,
      'data': {'like': 1, 'coin': 1, 'favorite': 0, 'coin_number': 1},
    };
    expect((await VideoHttp.pgcTriple(epId: 1)).data.coinNumber, 1);
    fixture.body = {
      'code': 0,
      'data': {'like': 1, 'coin': 1, 'favorite': 0},
    };
    expect(await VideoHttp.pgcTriple(epId: 1), isA<UnknownResult>());
  });
  test('参数无效在分发前返回普通失败，显式账号绑定 Cookie 写入', () async {
    for (final result in [
      await VideoHttp.coinVideo(bvid: '', multiply: 1),
      await VideoHttp.coinVideo(bvid: video, multiply: 3),
      await VideoHttp.likeVideo(bvid: '', type: true),
      await VideoHttp.ugcTriple(bvid: ''),
      await VideoHttp.pgcTriple(epId: 0),
    ]) {
      expect(result, isA<Error>());
      expect(result, isNot(isA<UnknownResult>()));
    }
    expect(requests, isEmpty);
    Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
    fixture.body = {
      'code': 0,
      'data': {'like': true, 'coin': false, 'fav': false},
    };
    expect(
      (await VideoHttp.ugcTriple(bvid: video, account: account)).isSuccess,
      isTrue,
    );
    expect(requests.single.extra['account'], same(account));
    expect(requests.single.data['csrf'], account.csrf);
  });
  test('状态查询缺字段返回可诊断解析失败，查询仍可重试', () async {
    for (final query in [
      () => VideoHttp.videoRelation(bvid: video),
      () => VideoHttp.pgcLikeCoinFav(epId: 1),
    ]) {
      fixture.body = {'code': 0, 'data': <String, dynamic>{}};
      final result = await query() as Error;
      expect(result, isNot(isA<UnknownResult>()));
      expect(result.cause, isA<FormatException>());
      expect(requests.last.extra['noRetry'], isFalse);
    }
    expect(requests.map((e) => e.path), [
      Api.videoRelation,
      Api.pgcLikeCoinFav,
    ]);
  });
}
