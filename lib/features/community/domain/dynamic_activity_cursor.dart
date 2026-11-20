/// 名单计数和游标随同一响应确认，刷新失败保留上一份快照。
class DynamicActivityCursor {
  const DynamicActivityCursor(this.offset, this.seen, this.total);
  final String? offset;
  final Set<String> seen;
  final int total;
}
