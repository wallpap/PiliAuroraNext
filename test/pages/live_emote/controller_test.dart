import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/live_emote_panel.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/features/community/data/emote_repository.dart';
import 'package:pili_aurora_next/features/community/domain/live_emote/datum.dart';
import 'package:pili_aurora_next/pages/live_emote/view.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _Repository extends EmoteRepository {
  @override
  Future<LoadingState<List<LiveEmoteDatum>?>> livePackages(
    Account account,
    int roomId,
  ) async => Success([LiveEmoteDatum(), LiveEmoteDatum()]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  LoginAccount account(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  Map<String, dynamic> emotes(String cover) => {
    'code': 0,
    'data': {
      'data': [
        {'current_cover': cover},
      ],
    },
  };

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
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

  test('直播表情绑定主账号，凭据替换后拒绝旧结果并释放旧页签', () async {
    final original = account('original');
    Accounts.accountMode[AccountType.main.index] = original;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = liveEmotePackagesProvider((owner: Object(), roomId: 12));
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await interceptor.waitForRequests(1);
    expect(requests.single.options.path, Api.getLiveEmoticons);
    expect(requests.single.options.extra['account'], same(original));
    final replacement = account('replacement');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.extra['account'], same(replacement));
    requests.last.reply.complete(emotes('new'));
    await Future<void>.delayed(Duration.zero);
    final refresh = controller.onRefresh();
    await interceptor.waitForRequests(3);
    expect(container.read(provider).loading, isA<Loading>());
    requests.last.reply.complete(emotes('refreshed'));
    await refresh;
    requests.first.reply.complete(emotes('old'));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(provider).loading.data.single.currentCover,
      'refreshed',
    );
    expect(container.read(provider).loading, isA<Success>());
    container.dispose();
    Accounts.replaceCredentials(account('after-close'));
    expect(requests, hasLength(3));
  });
  test('同房间两个面板与另一房间查询互相隔离，失败可重试原房间', () async {
    requests.clear();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final providers = [
      for (final room in [12, 12, 34])
        liveEmotePackagesProvider((owner: Object(), roomId: room)),
    ];
    final subscriptions = [
      for (final provider in providers) container.listen(provider, (_, _) {}),
    ];
    await interceptor.waitForRequests(3);
    expect(requests.map((r) => r.options.queryParameters['room_id']), [
      12,
      12,
      34,
    ]);
    requests[0].reply.complete({'code': -403});
    requests[1].reply.complete(emotes('second'));
    requests[2].reply.complete(emotes('third'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(providers[0]).loading, isA<Error>());
    final retry = container.read(providers[0].notifier).retry();
    await interceptor.waitForRequests(4);
    expect(requests.last.options.queryParameters['room_id'], 12);
    subscriptions[0].close();
    await container.pump();
    requests.last.reply.complete(emotes('retired'));
    await retry;
    expect(
      container.read(providers[1]).loading.data.single.currentCover,
      'second',
    );
    expect(
      container.read(providers[2]).loading.data.single.currentCover,
      'third',
    );
  });
  testWidgets('房间变更与卸载销毁 Widget 持有的活动 Tab', (tester) async {
    Widget panel(int room) => ProviderScope(
      overrides: [emoteRepositoryProvider.overrideWithValue(_Repository())],
      child: MaterialApp(
        home: LiveEmotePanel(
          roomId: room,
          onChoose: (_, _, _) {},
          onSendEmoticonUnique: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(panel(12));
    await tester.pumpAndSettle();
    final tabs = DefaultTabController.of(tester.element(find.byType(TabBar)))
      ..animateTo(1);
    await tester.pump();
    await tester.pumpWidget(panel(34));
    await tester.pumpAndSettle();
    expect(tabs.animation, isNull);
    final current = DefaultTabController.of(tester.element(find.byType(TabBar)))
      ..animateTo(1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(current.animation, isNull);
    expect(tester.takeException(), isNull);
  });
}
