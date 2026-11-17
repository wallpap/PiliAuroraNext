import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_filter.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/application/live_feed.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/remote/live/live_feed_index/card_data_list_item.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';
import 'live_fixture.dart';

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
  }) => source
      .where((item) => item is! CardLiveItem || item.roomid != 1)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor();
  final requests = interceptor.requests;
  late ProviderContainer container;
  LoginAccount account(int mid) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture'}),
    null,
    null,
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    container = ProviderContainer(
      overrides: [discoveryFilterProvider.overrideWithValue(_Filter())],
    );
    Accounts.accountMode[AccountType.main.index] = account(2);
    Accounts.accountMode[AccountType.recommend.index] = account(3);
  });
  tearDown(() => container.dispose());
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });
  test('直播首页换凭据撤销旧列表和关注快照，主账号改变也重新过滤', () async {
    final provider = liveFeedProvider((
      owner: Object(),
      areaId: null,
      parentAreaId: null,
      sortType: null,
    ));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    final replacement = account(3);
    Accounts.replaceCredentials(replacement);
    expect(container.read(provider).metadata, isNull);
    await interceptor.waitForRequests(2);
    expect(requests[1].options.extra['account'], same(replacement));
    requests[1].reply.complete(liveIndex(22));
    await tick();
    requests[0].reply.complete(liveIndex(11));
    await tick();
    expect(container.read(provider).loading.data.single.roomid, 22);
    expect(
      container
          .read(provider)
          .metadata
          ?.followed
          ?.cardData
          ?.myIdolV1
          ?.list
          ?.single
          .roomid,
      22,
    );
    Accounts.replaceCredentials(account(2));
    expect(container.read(provider).loading, isA<Loading>());
    await interceptor.waitForRequests(3);
    expect(requests[2].options.extra['account'], same(replacement));
    requests[2].reply.complete(liveIndex(23));
    await tick();
    expect(container.read(provider).loading.data.single.roomid, 23);
  });
  test('未收藏分区按查询键加载，顶部及标签属于同一快照，原始总数决定结束', () async {
    final provider = liveFeedProvider((
      owner: Object(),
      areaId: 7,
      parentAreaId: 8,
      sortType: 'online',
    ));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    expect(requests[0].options.path, Api.liveSecondList);
    expect(requests[0].options.queryParameters['area_id'], 7);
    expect(requests[0].options.queryParameters['sort_type'], 'online');
    requests[0].reply.complete(liveSecond([1, 2], count: 3));
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(liveIndex(1, area: 9));
    await tick();
    expect(container.read(provider).loading.data.map((item) => item.roomid), [
      2,
    ]);
    expect(
      container.read(provider).metadata?.followed?.cardData?.myIdolV1?.list,
      isEmpty,
    );
    expect(container.read(provider).metadata?.tags.single.sortType, 'online');
    final operation = container.read(provider.notifier).onLoadMore();
    await interceptor.waitForRequests(3);
    expect(requests[2].options.queryParameters['page'], 2);
    requests[2].reply.complete(liveSecond([3], count: 3, tag: null));
    await operation;
    expect(container.read(provider).loading.data.map((item) => item.roomid), [
      2,
      3,
    ]);
    expect(container.read(provider).hasMore, isFalse);
    expect(
      container
          .read(provider)
          .metadata
          ?.areas
          ?.cardData
          ?.areaEntranceV3
          ?.list
          ?.single
          .areaV2Id,
      9,
    );
    expect(container.read(provider).metadata?.tags.single.sortType, 'online');
  });
  test('切换标签并释放旧查询后，旧分区结果不继续读取顶部', () async {
    final owner = Object();
    final before = liveFeedProvider((
      owner: owner,
      areaId: 7,
      parentAreaId: 8,
      sortType: null,
    ));
    final subscription = container.listen(before, (_, _) {});
    container.read(before);
    await interceptor.waitForRequests(1);
    subscription.close();
    await container.pump();
    final next = liveFeedProvider((
      owner: owner,
      areaId: 7,
      parentAreaId: 8,
      sortType: 'online',
    ));
    container
      ..listen(next, (_, _) {})
      ..read(next);
    await interceptor.waitForRequests(2);
    requests[0].reply.complete(liveSecond([11]));
    await tick();
    expect(requests.length, 2);
    requests[1].reply.complete(liveSecond([22]));
    await interceptor.waitForRequests(3);
    requests[2].reply.complete(liveIndex(22));
    await tick();
    expect(container.read(next).loading.data.single.roomid, 22);
  });
  test('过滤空页补读保留同轮顶部和标签，不重复查询顶部', () async {
    final provider = liveFeedProvider((
      owner: Object(),
      areaId: 7,
      parentAreaId: 8,
      sortType: null,
    ));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(liveSecond([1], count: 2));
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(liveIndex(2));
    await interceptor.waitForRequests(3);
    expect(requests[2].options.path, Api.liveSecondList);
    expect(requests[2].options.queryParameters['page'], 2);
    requests[2].reply.complete(liveSecond([2], count: 2, tag: null));
    await tick();
    expect(container.read(provider).loading.data.single.roomid, 2);
    expect(container.read(provider).metadata?.tags.single.sortType, 'online');
    expect(container.read(provider).metadata?.areas, isNotNull);
    expect(requests.length, 3);
  });
  test('直播首页续页保留首页关注和分区快照，不被续页附带顶部替换', () async {
    final provider = liveFeedProvider((
      owner: Object(),
      areaId: null,
      parentAreaId: null,
      sortType: null,
    ));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(liveIndex(2, area: 7, hasMore: 1));
    await tick();
    final before = container.read(provider);
    final operation = container.read(provider.notifier).onLoadMore();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(liveIndex(3, area: 9));
    await operation;
    expect(
      container.read(provider).metadata?.followed,
      same(before.metadata?.followed),
    );
    expect(
      container.read(provider).metadata?.areas,
      same(before.metadata?.areas),
    );
    expect(container.read(provider).loading.data.map((item) => item.roomid), [
      2,
      3,
    ]);
    expect(before.loading.data.single.roomid, 2);
  });
  test('顶部失败保留当前分区数据，并交付独立重试提示', () async {
    final provider = liveFeedProvider((
      owner: Object(),
      areaId: 7,
      parentAreaId: 8,
      sortType: null,
    ));
    container
      ..listen(provider, (_, _) {})
      ..read(provider);
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(liveSecond([22]));
    await interceptor.waitForRequests(2);
    requests[1].reply.complete({'code': -42, 'message': '分区信息暂不可用'});
    await tick();
    expect(container.read(provider).loading.data.single.roomid, 22);
    expect(container.read(provider).metadata?.headerError, '分区信息暂不可用');
  });
}
