import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/subscriptions/application/subscription_library.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/feed_view.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/subscription_actions.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/subscription_card.dart';

class SubPage extends ConsumerStatefulWidget {
  const SubPage({super.key});
  @override
  ConsumerState<SubPage> createState() => _SubPageState();
}

class _SubPageState extends ConsumerState<SubPage> {
  final _owner = Object();
  late final _query = SubscriptionQuery(owner: _owner);
  @override
  Widget build(BuildContext context) {
    final value = ref.watch(subscriptionFeedProvider(_query));
    final feed = ref.read(subscriptionFeedProvider(_query).notifier);
    final operation = ref.watch(subscriptionOperationsProvider);
    final data = !value.isLoading && !value.hasError ? value.value : null;
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('我的订阅'),
        actions: [
          TextButton.icon(
            onPressed: data == null || data.loadingMore || operation.busy
                ? null
                : () => cleanSubscriptions(context, ref, feed, data),
            icon: operation.cleaning
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined, size: 20),
            label: Text(operation.cleaning ? '清理中' : '清除失效内容'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SubscriptionFeedView(
        value: value,
        feed: feed,
        enabled: !operation.busy,
        progress: operation.progress,
        itemBuilder: (item) => SubItem(
          item: item as SubItemModel,
          cancelSub:
              operation.busy || data == null || !feed.canCancel(data, item)
              ? null
              : () => cancelSubscription(context, ref, feed, data, item),
        ),
      ),
    );
  }
}
