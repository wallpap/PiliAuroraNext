import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/emote_management.dart';
import 'package:pili_aurora_next/features/community/application/emote_panel.dart';
import 'package:pili_aurora_next/features/community/domain/emote/emote.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  final cache = _FailingCache();
  LoginAccount account(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  Map<String, dynamic> emotes(String cover) => {
    'code': 0,
    'data': {
      'packages': [
        {'text': cover},
      ],
    },
  };

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = cache;
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  setUp(cache.data.clear);

  test('评论表情绑定主账号，凭据替换后拒绝旧结果并释放旧页签', () async {
    final original = account('original');
    Accounts.accountMode[AccountType.main.index] = original;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = emotePackagesProvider(Object());
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    await interceptor.waitForRequests(1);
    expect(requests.single.options.path, Api.myEmote);
    expect(requests.single.options.extra['account'], same(original));
    final replacement = account('replacement');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(2);
    expect(requests.last.options.extra['account'], same(replacement));
    requests.last.reply.complete(emotes('new'));
    await Future<void>.delayed(Duration.zero);
    final refresh = controller.onRefresh();
    await interceptor.waitForRequests(3);
    expect(container.read(provider).loading.data.single.text, 'new');
    requests.last.reply.complete(emotes('refreshed'));
    await refresh;
    requests.first.reply.complete(emotes('old'));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(provider).loading.data.single.text,
      'refreshed',
    );
    expect(container.read(provider).loading, isA<Success>());
    container.dispose();
    Accounts.replaceCredentials(account('after-close'));
    expect(requests, hasLength(3));
  });

  test('表情管理切换凭据后丢弃旧写入并停止旧分类翻页', () async {
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account('old');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = emoteManagementProvider(Object());
    container.listen(provider, (_, _) {});
    final manager = container.read(provider.notifier);
    Map<String, dynamic> panel(int id) => {
      'code': 0,
      'data': {
        'user_panel_packages': [
          {'id': id, 'text': '包 $id'},
        ],
      },
    };
    Map<String, dynamic> category(int total, int id) => {
      'code': 0,
      'data': {
        'total': total,
        'packages': [
          {'id': id, 'text': '包 $id'},
        ],
      },
    };
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(panel(1));
    await interceptor.waitForRequests(2);
    final removed = manager.changePackage(
      container.read(provider).added.single,
      add: false,
    );
    await interceptor.waitForRequests(3);
    expect(requests[2].options.path, Api.removeEmotePackage);
    expect(container.read(provider).added.single.id, 1);

    final replacement = account('new');
    Accounts.replaceCredentials(replacement);
    await interceptor.waitForRequests(4);
    expect(requests[3].options.extra['account'], same(replacement));
    requests[3].reply.complete(panel(2));
    await interceptor.waitForRequests(5);
    requests[4].reply.complete(category(1, 3));
    requests[1].reply.complete(category(2, 4));
    requests[2].reply.complete({'code': 0});
    expect(await removed, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).added.single.id, 2);
    expect(container.read(provider).available.single.id, 3);
    expect(requests, hasLength(5));
  });

  for (final history in [
    'invalid',
    [
      12,
      {'text': 7},
      {'text': 'valid', 'width': 24},
    ],
  ]) {
    test('损坏历史缓存不阻止表情查询：$history', () async {
      requests.clear();
      cache.data[LocalCacheKey.recentEmotes] = history;
      final container = ProviderContainer();
      final provider = emotePackagesProvider(Object());
      container.listen(provider, (_, _) {});
      await interceptor.waitForRequests(1);
      requests.single.reply.complete(emotes('available'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).loading, isA<Success>());
      expect(
        container.read(recentEmotesProvider).length,
        history is List ? 1 : 0,
      );
      container.dispose();
    });
  }

  test('连续选择按顺序保存各自快照，最后保留最新历史', () async {
    final gate = Completer<void>();
    cache.gate = gate;
    final container = ProviderContainer();
    final controller = container.read(recentEmotesProvider.notifier);
    final first = controller.record(Emote(text: 'first'), 24);
    final second = controller.record(Emote(text: 'second'), 24);
    await Future<void>.delayed(Duration.zero);
    expect(cache.gate, isNull);
    var secondDone = false;
    unawaited(second.then((_) => secondDone = true));
    expect(secondDone, false);
    gate.complete();
    await Future.wait([first, second]);
    final history = cache.get(LocalCacheKey.recentEmotes) as List;
    expect(history.map((item) => item['text']), ['second', 'first']);
    container.dispose();
  });

  test('历史保存失败被消费，后续选择仍可保存', () async {
    cache
      ..failNext = true
      ..writes = 0;
    final container = ProviderContainer();
    final controller = container.read(recentEmotesProvider.notifier);
    await controller.record(Emote(text: 'first'), 24);
    await controller.record(Emote(text: 'second'), 24);
    expect(container.read(recentEmotesProvider).first.emote.text, 'second');
    expect((GStorage.localCache as _FailingCache).writes, 2);
    expect(
      (GStorage.localCache.get(LocalCacheKey.recentEmotes) as List).length,
      2,
    );
    container.dispose();
  });
  test('共享历史去重限长，并保存独立于调用方后续修改的快照', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final history = container.read(recentEmotesProvider.notifier);
    for (var i = 0; i < 45; i++) {
      await history.record(Emote(text: '$i'), 24);
    }
    final item = Emote(text: '44');
    await history.record(item, 24);
    item.text = 'modified';
    expect(container.read(recentEmotesProvider), hasLength(40));
    expect(container.read(recentEmotesProvider).first.emote.text, '44');
  });
}

class _FailingCache extends MemoryBox {
  int writes = 0;
  bool failNext = false;
  Completer<void>? gate;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    writes++;
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (failNext) {
      failNext = false;
      throw StateError('cache unavailable');
    }
    await super.put(key, value);
  }
}
