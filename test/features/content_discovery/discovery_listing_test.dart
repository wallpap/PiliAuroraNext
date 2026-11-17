import 'dart:async';

import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_filter.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

Account _testAccount() => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': 'fixture'}),
  null,
  null,
);

class _Account extends MainAccountNotifier {
  @override
  Account build() => _testAccount();
  void replace(Account value) => state = value;
}

class _Recommend extends RecommendAccountNotifier {
  @override
  Account build() => _testAccount();
  void replace(Account value) => state = value;
}

class _Filter extends DiscoveryFilter {
  @override
  Future<void>? prepare() => null;
  @override
  Iterable<Never> authorsToCheck(Object? items) => [];
  @override
  List<T> filter<T>(
    Iterable<T> source, {
    Iterable<T> existing = const [],
    bool deduplicate = false,
  }) => source.where((item) => item != -1 && !existing.contains(item)).toList();
}

class _Feed extends DiscoveryListing<int, String> {
  final requests =
      <
        ({
          Account account,
          int page,
          Completer<LoadingState<DiscoveryPage<int, String>>> result,
        })
      >[];
  @override
  Future<LoadingState<DiscoveryPage<int, String>>> fetch(
    Account account,
    int page,
  ) {
    final result = Completer<LoadingState<DiscoveryPage<int, String>>>();
    requests.add((account: account, page: page, result: result));
    return result.future;
  }

  void reply(int index, List<int> items, {int? total, bool? hasMore}) =>
      requests[index].result.complete(
        Success(
          DiscoveryPage(
            items,
            metadata: 'page${requests[index].page}',
            total: total,
            hasMore: hasMore,
          ),
        ),
      );
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GStorage.localCache = MemoryBox();
    GStorage.setting = MemoryBox();
  });
  late _Feed feed;
  late ProviderContainer container;
  final provider =
      NotifierProvider.autoDispose<_Feed, DiscoveryListingState<int, String>>(
        _Feed.new,
      );
  setUp(() {
    feed = _Feed();
    container = ProviderContainer(
      overrides: [
        mainAccountProvider.overrideWith(_Account.new),
        recommendAccountProvider.overrideWith(_Recommend.new),
        discoveryFilterProvider.overrideWithValue(_Filter()),
        provider.overrideWith(() => feed),
      ],
    );
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
  });
  tearDown(() => container.dispose());
  test('刷新撤销旧请求，分页失败保留快照和页码，显式重试串行执行', () async {
    await tick();
    final old = feed.onRefresh();
    await tick();
    feed.reply(0, [99]);
    await tick();
    expect(container.read(provider).loading, isA<Loading>());
    feed.reply(1, [1]);
    await old;
    final more = feed.onLoadMore();
    await tick();
    await feed.onLoadMore();
    expect(feed.requests.length, 3);
    feed.requests[2].result.complete(const Error('离线'));
    await more;
    expect(container.read(provider).loading.data, [1]);
    expect(container.read(provider).canLoadMore, isFalse);
    final retry = feed.retry();
    await tick();
    expect(feed.requests[3].page, 2);
    feed.reply(3, [1, 2]);
    await retry;
    expect(container.read(provider).loading.data, [1, 2]);
  });
  test('切换推荐凭据立即重建归属，旧响应不能发布，释放后不续页', () async {
    await tick();
    final before = feed.requests.single.account;
    (container.read(recommendAccountProvider.notifier) as _Recommend).replace(
      _testAccount(),
    );
    expect(container.read(provider).loading, isA<Loading>());
    await tick();
    expect(feed.requests[1].account, isNot(same(before)));
    feed.reply(0, [99]);
    await tick();
    expect(container.read(provider).loading, isA<Loading>());
    container.dispose();
    // tearDown 使用独立空容器，保持真实释放只发生一次。
    container = ProviderContainer();
    feed.reply(1, [-1]);
    await tick();
    expect(feed.requests.length, 2);
  });
  test('过滤补位沿原始数量计算结束，五页无增长后由用户继续', () async {
    await tick();
    for (var i = 0; i < 5; i++) {
      feed.reply(i, [-1]);
      await tick();
    }
    expect(feed.requests.length, 5);
    expect(container.read(provider).canLoadMore, isFalse);
    final retry = feed.retry();
    await tick();
    expect(feed.requests.last.page, 6);
    feed.reply(5, [2], total: 6);
    await retry;
    expect(container.read(provider).loading.data, [2]);
    expect(container.read(provider).hasMore, isFalse);
  });
  test('页面移除期间分页完成不会恢复已移除内容，元数据与列表同批发布', () async {
    await tick();
    feed.reply(0, [1, 2]);
    await tick();
    final operation = feed.onLoadMore();
    await tick();
    feed
      ..remove(1)
      ..reply(1, [3]);
    await operation;
    expect(container.read(provider).loading.data, [2, 3]);
    expect(container.read(provider).metadata, 'page2');
  });
}
