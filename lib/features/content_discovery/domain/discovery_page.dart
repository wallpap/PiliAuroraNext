/// 远端游标按过滤前的数量推进，展示列表的移除不改变分页位置。
class DiscoveryPage<T, M> {
  const DiscoveryPage(
    this.items, {
    required this.metadata,
    this.hasMore,
    this.total,
  });
  final List<T> items;
  final M metadata;
  final bool? hasMore;
  final int? total;
}
