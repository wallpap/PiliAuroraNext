import 'package:pili_aurora_next/features/content_discovery/application/cooperative_authors.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_filter.dart';
import 'package:pili_aurora_next/pages/common/common_list_controller.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

/// 发现类内容在进入页面状态前过滤，并沿原来源补足当前批次。
abstract class DiscoveryListController<R, T>
    extends CommonListController<R, T> {
  bool get supportsPagination => true;

  @override
  bool get canLoadMore => supportsPagination && super.canLoadMore;

  @override
  bool get refillFilteredPages =>
      supportsPagination && const DiscoveryFilter().enabled;

  Account get queryAccount => Accounts.main;

  Account? _contextMain;
  Account? _contextQuery;
  Object _context = Object();
  Object? _listContext;

  @override
  Object get queryContext {
    final main = Accounts.main;
    final query = queryAccount;
    // 屏蔽规则属于主账号，内容请求可使用独立推荐账号。
    if (!identical(main, _contextMain) || !identical(query, _contextQuery)) {
      _contextMain = main;
      _contextQuery = query;
      _context = Object();
    }
    return _context;
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    final context = queryContext;
    if (!isRefresh && !identical(_listContext, context)) {
      return onReload();
    }
    _listContext = context;
    return super.queryData(isRefresh);
  }

  @override
  Future<void>? prepareQuery() => const DiscoveryFilter().prepare();

  CooperativeAuthors get cooperativeAuthors => CooperativeAuthors.shared;

  @override
  Future<void>? prepareResponse(R response, bool Function() isCurrent) {
    final videos = const DiscoveryFilter().authorsToCheck([
      response,
      loadingState.value.dataOrNull,
    ]).toList();
    return videos.isEmpty
        ? null
        : cooperativeAuthors.prepare(videos, isCurrent: isCurrent);
  }

  List<T> filterCandidates(
    Iterable<T> source, {
    Iterable<T> existing = const [],
  }) => const DiscoveryFilter().filter(source, existing: existing);

  @override
  List<T> filterList(List<T> source, bool isRefresh) => filterCandidates(
    source,
    existing: isRefresh ? const [] : loadingState.value.dataOrNull ?? const [],
  );
}
