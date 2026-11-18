import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/content_library/presentation/feed_view.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

LoginAccount _account(String id) =>
    LoginAccount(BiliCookieJar.fromJson({'DedeUserID': id}), null, null)
      ..activated = true;

class _Account extends Notifier<Account> {
  @override
  Account build() => _account('1');
  void replace() => state = _account('2');
}

final _accountProvider = NotifierProvider<_Account, Account>(_Account.new);
final _feedProvider = AsyncNotifierProvider<_Feed, FeedState<String, void>>(
  _Feed.new,
  retry: (_, _) => null,
);

class _Feed extends PagedFeed<String, void> {
  final requests = <Completer<FeedPage<String, void>>>[];

  @override
  Account watchAccount() => ref.watch(_accountProvider);
  @override
  bool ownsAccount(Account account) =>
      identical(account, ref.read(_accountProvider));
  @override
  String itemKey(String item) => item;
  @override
  Future<FeedPage<String, void>> fetch(Account account, Object? cursor) {
    final response = Completer<FeedPage<String, void>>();
    requests.add(response);
    return response.future;
  }
}

void main() {
  testWidgets('内容库刷新保留已确认内容，失败可重试，切号隐藏旧账号内容', (tester) async {
    GStorage.setting = MemoryBox();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (_, ref, _) => LibraryFeedView(
                value: ref.watch(_feedProvider),
                feed: ref.read(_feedProvider.notifier),
                itemBuilder: (_, item, _) => Text(item),
              ),
            ),
          ),
        ),
      ),
    );
    final feed = container.read(_feedProvider.notifier);
    feed.requests.single.complete(FeedPage(['已确认'], metadata: null));
    await tester.pumpAndSettle();
    expect(find.text('已确认'), findsOneWidget);

    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(find.text('已确认'), findsOneWidget);
    feed.requests[1].completeError(const Error('离线'));
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('已确认'), findsOneWidget);

    await tester.tap(find.textContaining('离线'));
    await tester.pump();
    feed.requests[2].complete(FeedPage(['已刷新'], metadata: null));
    await tester.pumpAndSettle();
    expect(find.text('已确认'), findsNothing);
    expect(find.text('已刷新'), findsOneWidget);
    expect(find.textContaining('离线'), findsNothing);

    container.read(_accountProvider.notifier).replace();
    await tester.pump();
    expect(find.text('已刷新'), findsNothing);
    feed.requests[3].complete(FeedPage(['新账号'], metadata: null));
    await tester.pumpAndSettle();
    expect(find.text('新账号'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
