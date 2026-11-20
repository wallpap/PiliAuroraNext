import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';

import 'video_write_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final main = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1'}),
    'main-key',
    null,
  );
  final recommend = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '2'}),
    'recommend-key',
    null,
  );
  final fixture = VideoWriteFixture(DioExceptionType.sendTimeout);
  final requests = fixture.requests;
  setUpAll(fixture.install);
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = main;
    Accounts.accountMode[AccountType.recommend.index] = recommend;
    fixture.reset();
  });
  tearDownAll(fixture.close);
  final writes = <Future<LoadingState<void>> Function()>[
    () => VideoHttp.feedDislike(goto: 'av', id: 1, reasonId: 2),
    () => VideoHttp.feedDislikeCancel(goto: 'av', id: 1),
    () => VideoHttp.dislikeVideo(bvid: IdUtils.av2bv(1), type: true),
  ];

  test('GET 反馈及撤销也是写入，真实重试拦截器不重放超时请求', () async {
    fixture.fail = true;
    for (final write in writes) {
      final before = requests.length;
      final error = await write() as UnknownResult;
      expect(requests.length, before + 1);
      expect(error.cause, isA<DioException>());
      expect(error.stackTrace, isNotNull);
      expect(requests.last.extra['noRetry'], isTrue);
    }
    expect(requests.map((request) => request.method), ['GET', 'GET', 'POST']);
    expect(requests[0].extra['account'], same(recommend));
    expect(requests[1].extra['account'], same(recommend));
    expect(requests[2].extra['account'], same(main));
  });

  test('反馈保留拒绝码；空回显成功，损坏协议为待确认', () async {
    for (final write in writes) {
      fixture.body = {'code': -403, 'message': '拒绝反馈'};
      final rejected = await write() as Error;
      expect(rejected.code, -403);
      expect(rejected, isNot(isA<UnknownResult>()));
      fixture.body = {'code': 0};
      expect(await write(), isA<Success<void>>());
      fixture.body = {'message': 'private-body'};
      final uncertain = await write() as UnknownResult;
      expect(uncertain.toString(), isNot(contains('private-body')));
    }
  });

  test('缺少或冲突的反馈目标在分发前拒绝，撤销可不带原因', () async {
    for (final result in [
      await VideoHttp.feedDislike(goto: 'av', id: 1),
      await VideoHttp.feedDislike(
        goto: 'av',
        id: 1,
        reasonId: 1,
        feedbackId: 2,
      ),
      await VideoHttp.feedDislikeCancel(goto: '', id: 0),
      await VideoHttp.dislikeVideo(bvid: '', type: true),
    ]) {
      expect(result, isA<Error>());
      expect(result, isNot(isA<UnknownResult>()));
    }
    expect(requests, isEmpty);
    expect(await writes[1](), isA<Success<void>>());
  });
}
