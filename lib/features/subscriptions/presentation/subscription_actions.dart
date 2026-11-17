import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_library/presentation/operation_dialog.dart';
import 'package:pili_aurora_next/features/subscriptions/application/subscription_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';

Future<void> cancelSubscription(
  BuildContext context,
  WidgetRef ref,
  SubscriptionFeed feed,
  SubscriptionState source,
  SubItemModel item,
) async {
  final operations = ref.read(subscriptionOperationsProvider.notifier);
  String? message;
  final success = await libraryConfirm(
    context,
    title: '确定取消订阅吗？',
    isCurrent: () => context.mounted && feed.canCancel(source, item),
    ownsResult: () =>
        context.mounted &&
        identical(source.account, ref.read(mainAccountProvider)),
    submit: () async {
      final result = await operations.cancel(
        source,
        item,
        isCurrent: () => context.mounted && feed.canCancel(source, item),
      );
      if (result case Success(:final response)) {
        message = response.message;
        return const Success(null);
      }
      return result as Error;
    },
  );
  if (success && context.mounted) SmartDialog.showToast(message!);
}

Future<void> cleanSubscriptions(
  BuildContext context,
  WidgetRef ref,
  SubscriptionFeed feed,
  SubscriptionState source,
) async {
  final operations = ref.read(subscriptionOperationsProvider.notifier);
  final hideInvalid = operations.hideInvalid;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('清除失效内容'),
      content: Text(
        '扫描全部订阅，取消已失效或全部内容失效的订阅。\n'
        '${hideInvalid ? '有效订阅中的失效视频将本地隐藏，有效内容保留。' : '保留仍有有效内容的订阅。可在“设置 → 其他设置”开启本地隐藏失效视频。'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted || !feed.isCurrent(source)) return;
  final result = await operations.clean(
    source.account,
    hideInvalid: hideInvalid,
    isCurrent: () => context.mounted,
  );
  if (!context.mounted ||
      !identical(source.account, ref.read(mainAccountProvider))) {
    return;
  }
  SmartDialog.showToast(switch (result) {
    Success(:final response) => response.message,
    _ => result.toString(),
  });
}
