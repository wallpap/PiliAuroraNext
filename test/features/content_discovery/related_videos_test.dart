import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/application/related_videos.dart';
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
  LoginAccount login(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '3', 'bili_jct': csrf}),
    null,
    null,
  );

  Map<String, dynamic> response(Iterable<int> ids) => {
    'code': 0,
    'data': [
      for (final id in ids)
        {
          'aid': id,
          'bvid': 'BV-fixture-$id',
          'title': 'video-$id',
          'duration': id == 1 ? 15 : 120,
          'owner': {'mid': 8},
          'stat': <String, dynamic>{},
        },
    ],
  };

  setUpAll(() {
    GStorage.setting = MemoryBox({
      SettingBoxKey.filterBlockedAuthors: false,
      SettingBoxKey.applyFilterToRelatedVideos: true,
      SettingBoxKey.minDurationForRcmd: 60,
    });
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('切片与同 UID 换凭据隔离旧响应，隐藏后的首项供面板和连播共用', () async {
    final recommend = login('before');
    Accounts.accountMode[AccountType.recommend.index] = recommend;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = relatedVideosProvider(RelatedVideoQuery('BV-first'));
    final firstView = container.listen(first, (_, _) {});
    await interceptor.waitForRequests(1);
    expect(requests[0].options.extra['account'], same(recommend));
    expect(requests[0].options.queryParameters['bvid'], 'BV-first');

    firstView.close();
    final next = relatedVideosProvider(RelatedVideoQuery('BV-next'));
    final nextView = container.listen(next, (_, _) {});
    await interceptor.waitForRequests(2);
    final replacement = login('after');
    Accounts.replaceCredentials(replacement);
    expect(nextView.read().loading, isA<Loading>());
    await interceptor.waitForRequests(3);
    expect(requests[2].options.extra['account'], same(replacement));
    expect(requests[2].options.queryParameters['bvid'], 'BV-next');

    requests[2].reply.complete(response([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    final selected = nextView.read().loading.data;
    expect(selected.map((item) => item.aid), [2, 3]);

    final notifier = container.read(next.notifier)
      ..remove(selected.first)
      ..remove(selected.first);
    requests[0].reply.complete(response([4]));
    requests[1].reply.complete(response([5]));
    await Future<void>.delayed(Duration.zero);
    expect(nextView.read().loading.data.single.aid, 3);
    expect(container.exists(first), isFalse);
    await notifier.onLoadMore();
    expect(requests, hasLength(3));
  });
}
