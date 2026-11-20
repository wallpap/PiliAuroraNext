/// 页面实例与合集 ID 共同隔离查询；null ID 表示当前账号的订阅列表。
class SubscriptionQuery {
  const SubscriptionQuery({required this.owner, this.id});
  final Object owner;
  final int? id;
  @override
  bool operator ==(Object other) =>
      other is SubscriptionQuery && owner == other.owner && id == other.id;
  @override
  int get hashCode => Object.hash(owner, id);
}
