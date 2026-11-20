import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/video_notes.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

class _AccountSource extends MainAccountNotifier {
  _AccountSource(this.account);
  final ValueNotifier<Account> account;

  @override
  Account build() {
    void changed() => state = account.value;
    account.addListener(changed);
    ref.onDispose(() => account.removeListener(changed));
    return account.value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledInterceptor wire;
  late ProviderContainer container;
  late ValueNotifier<Account> account;
  final query = videoNotesProvider((owner: Object(), oid: 23));

  Map<String, Object> page(int total, List<int> ids) => {
    'code': 0,
    'data': {
      'page': {'total': total},
      'list': [
        for (final id in ids) {'cvid': id, 'summary': '笔记 $id'},
      ],
    },
  };

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
  });
  setUp(() {
    wire = ControlledInterceptor();
    Request.dio.interceptors
      ..clear()
      ..add(wire);
    account = ValueNotifier(AnonymousAccount());
    container = ProviderContainer(
      overrides: [
        mainAccountProvider.overrideWith(() => _AccountSource(account)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      account.dispose();
      await wire.close();
    });
    container.listen(query, (_, _) {});
  });
  tearDownAll(() => Request.dio.close(force: true));

  test('匿名可读；续页失败保留总数和已有笔记，显式重试原页并去重', () async {
    await wire.waitForRequests(1);
    expect(wire.requests.first.options.extra['account'], same(account.value));
    expect(wire.requests.first.options.queryParameters['oid'], 23);
    wire.requests.first.reply.complete(page(11, [8]));
    final first = await container.read(query.future);
    expect(first.metadata, 11);
    final notes = container.read(query.notifier);
    final failure = notes.loadMore();
    await wire.waitForRequests(2);
    wire.requests[1].reply.complete({'code': -403, 'message': '续页失败'});
    await failure;
    expect(notes.displayState!.items.map((note) => note.id), [8]);
    expect(notes.displayState!.metadata, 11);
    expect(notes.displayState!.error?.code, -403);
    await notes.loadMore();
    expect(wire.requests, hasLength(2));

    final retry = notes.loadMore(retry: true);
    await wire.waitForRequests(3);
    expect(wire.requests.skip(1).map((r) => r.options.queryParameters['pn']), [
      2,
      2,
    ]);
    wire.requests[2].reply.complete(page(11, [8, 9]));
    await retry;
    expect(notes.displayState!.items.map((note) => note.id), [8, 9]);
    expect(notes.displayState!.canLoadMore, isFalse);
  });

  test('切换账号重读首屏，旧页迟到不覆盖新列表和总数', () async {
    await wire.waitForRequests(1);
    account.value = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': 'new-csrf'}),
      null,
      null,
    );
    await container.pump();
    await wire.waitForRequests(2);
    expect(wire.requests[1].options.extra['account'], same(account.value));
    expect(wire.requests[1].options.queryParameters['csrf'], 'new-csrf');
    wire.requests[1].reply.complete(page(1, [9]));
    await container.read(query.future);
    wire.requests.first.reply.complete(page(33, [8]));
    await container.pump();
    final data = container.read(query.notifier).displayState!;
    expect(data.metadata, 1);
    expect(data.items.single.id, 9);
  });
}
