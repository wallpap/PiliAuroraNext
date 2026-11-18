import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/pages/music/controller.dart';
import 'package:pili_aurora_next/pages/match_info/controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Music extends MusicDetailController {
  _Music() : super(musicId: 'track');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  final account = LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': 'synthetic-csrf'}),
    null,
    null,
  );
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox({
      LocalCacheKey.mixinKey: 'synthetic',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
    });
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = account;
    requests.clear();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  Map<String, dynamic> music({
    String title = 'sample',
    int? oid,
    int? wishes = 2,
    bool liked = false,
  }) => {
    'code': 0,
    'data': {
      'music_title': title,
      'wish_count': wishes,
      'wish_listen': liked,
      if (oid != null)
        'music_comment': {'oid': oid, 'page_type': 47, 'nums': 3},
    },
  };
  Future<void> load(
    MusicDetailController controller,
    Map<String, dynamic> body,
  ) async {
    final next = requests.length + 1;
    final pending = controller.getMusicDetail();
    await interceptor.waitForRequests(next);
    requests.last.reply.complete(body);
    await pending;
  }

  test('音乐详情重复加载可更新评论来源，不再重复初始化 late final', () async {
    final controller = _Music();
    addTearDown(controller.onDelete.call);
    await load(controller, music(oid: 1));
    await load(controller, music(oid: 2));
    expect(controller.oid, 2);
    expect(controller.replyType, 47);
    expect(controller.commentSource.value.data, (oid: 2, type: 47));
    expect(controller.count, 3);
  });

  test('没有评论元数据时详情可用，评论呈现空状态而非持续加载', () async {
    final controller = _Music();
    addTearDown(controller.onDelete.call);
    await load(controller, music());
    expect(controller.infoState.value, isA<Success>());
    expect(controller.canComment, isFalse);
    expect(controller.commentSource.value, isA<Success>());
    expect(controller.commentSource.value.data, isNull);
    expect(controller.count, 0);
  });

  test('旧音乐详情不能覆盖新查询或重新发起旧评论查询', () async {
    final controller = _Music();
    addTearDown(controller.onDelete.call);
    final old = controller.getMusicDetail();
    await interceptor.waitForRequests(1);
    final latest = controller.getMusicDetail();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(music(title: 'latest', oid: 2));
    await latest;
    requests[0].reply.complete(music(title: 'old', oid: 1));
    await old;
    expect(controller.infoState.value.data.musicTitle, 'latest');
    expect(controller.oid, 2);
    expect(controller.commentSource.value.data, (oid: 2, type: 47));
  });

  test('关闭或切号后音乐迟到结果不再发布，也不让页面一直等待', () async {
    final closed = _Music();
    addTearDown(closed.onDelete.call);
    final pending = closed.getMusicDetail();
    await interceptor.waitForRequests(1);
    closed.onDelete();
    requests[0].reply.complete(music(oid: 1));
    await pending;
    expect(closed.infoState.value, isA<Loading>());
    expect(closed.commentSource.value.dataOrNull, isNull);
    final changed = _Music();
    addTearDown(changed.onDelete.call);
    final next = changed.getMusicDetail();
    await interceptor.waitForRequests(2);
    Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '2'}),
      null,
      null,
    );
    requests[1].reply.complete(music(oid: 1));
    await next;
    expect(changed.infoState.value, isA<Error>());
    expect(changed.infoState.value.toString(), contains('账号已切换'));
    expect(changed.commentSource.value.dataOrNull, isNull);
  });

  test('点赞等待服务端确认并拒绝重复提交，未知计数保持未知', () async {
    final controller = _Music();
    addTearDown(controller.onDelete.call);
    await load(controller, music(wishes: null));
    final item = controller.infoState.value.data;
    final liking = controller.toggleWish(item);
    await interceptor.waitForRequests(2);
    await controller.toggleWish(item);
    expect(requests, hasLength(2));
    expect(item.wishListen, isFalse);
    expect(requests[1].options.extra['account'], same(account));
    requests[1].reply.complete({'code': 0});
    await liking;
    expect(item.wishListen, isTrue);
    expect(item.wishCount, isNull);
  });

  test('切号后点赞迟到成功不修改旧详情快照', () async {
    final controller = _Music();
    addTearDown(controller.onDelete.call);
    await load(controller, music());
    final item = controller.infoState.value.data;
    final liking = controller.toggleWish(item);
    await interceptor.waitForRequests(2);
    Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '2'}),
      null,
      null,
    );
    requests[1].reply.complete({'code': 0});
    await liking;
    expect(item.wishListen, isFalse);
    expect(item.wishCount, 2);
  });

  test('赛事详情等待时已经提供独立评论目标', () async {
    final controller = MatchInfoController(oid: 1);
    addTearDown(controller.onDelete.call);
    final pending = controller.getMatchInfo();
    await interceptor.waitForRequests(1);
    expect(controller.commentSource.value.data, (oid: 1, type: 27));
    requests[0].reply.complete({'code': 0, 'data': <String, dynamic>{}});
    await pending;
    expect(controller.infoState.value.data, isNull);
  });

  test('赛事详情失败不阻塞评论，非法路由标识不发出任何请求', () async {
    final controller = MatchInfoController(oid: 1);
    addTearDown(controller.onDelete.call);
    final pending = controller.getMatchInfo();
    await interceptor.waitForRequests(1);
    requests[0].reply.complete({'code': -403, 'message': '详情拒绝'});
    await pending;
    expect((controller.infoState.value as Error).code, -403);
    expect(controller.commentSource.value.data, (oid: 1, type: 27));
    final invalid = MatchInfoController(oid: 0);
    addTearDown(invalid.onDelete.call);
    await invalid.getMatchInfo();
    expect(requests, hasLength(1));
    expect(invalid.infoState.value, isA<Error>());
    expect(invalid.commentSource.value, isA<Error>());
  });

  test('旧赛事请求与关闭后的结果不更新当前详情', () async {
    final controller = MatchInfoController(oid: 1);
    addTearDown(controller.onDelete.call);
    final old = controller.getMatchInfo();
    await interceptor.waitForRequests(1);
    final latest = controller.getMatchInfo();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({
      'code': 0,
      'data': {
        'contest': {'game_stage': 'latest'},
      },
    });
    await latest;
    requests[0].reply.complete({
      'code': 0,
      'data': {
        'contest': {'game_stage': 'old'},
      },
    });
    await old;
    expect(controller.infoState.value.data!.gameStage, 'latest');
  });
}
