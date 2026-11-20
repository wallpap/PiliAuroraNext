import 'dart:async';

import 'package:pili_aurora_next/features/community/application/dynamics_actions.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_selection.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/dynamics_type.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/result.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef DynamicsQuery = ({Object owner, DynamicsTabType type, int hostMid});
final dynamicsFeedProvider = NotifierProvider.autoDispose
    .family<
      DynamicsFeed,
      DiscoveryListingState<DynamicItemModel, DynamicCursor>,
      DynamicsQuery
    >(DynamicsFeed.new);

class DynamicsFeed extends DiscoveryListing<DynamicItemModel, DynamicCursor> {
  DynamicsFeed(this.query);
  final DynamicsQuery query;
  late Set<int> _banned;
  @override
  bool get usesMainAccount => true;
  @override
  Object itemKey(DynamicItemModel item) => item.idStr?.toString() ?? item;
  @override
  DiscoveryListingState<DynamicItemModel, DynamicCursor> build() {
    _banned = ref.watch(
      dynamicsSelectionProvider.select((value) => value.banned),
    );
    final account = ref.watch(mainAccountProvider);
    final subscription = ref.read(dynamicsUpdatesProvider).changes.listen((
      change,
    ) {
      if (!ref.mounted ||
          !identical(account, change.account) ||
          change.pin != null) {
        return;
      }
      if (change.removed == null) {
        unawaited(onRefresh());
      } else {
        excludeKey(change.removed!);
      }
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    return super.build();
  }

  @override
  Future<LoadingState<DiscoveryPage<DynamicItemModel, DynamicCursor>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(dynamicsRepositoryProvider)
      .feed(account, query.type, query.hostMid, _banned, queryMetadata);
  Future<LoadingState<void>> onRemove(String id) async {
    final account = ref.read(mainAccountProvider);
    if (!account.isLogin ||
        state.loading is! Success ||
        !(state.loading.dataOrNull?.any((item) => itemKey(item) == id) ??
            false)) {
      return const Error('账号或动态已更新，请刷新');
    }
    return ref.read(dynamicsActionsProvider).remove(account, id);
  }

  void onUnfold(DynamicItemModel item) {
    final items = state.loading.dataOrNull;
    final ids = item.modules.moduleFold?.ids?.toSet();
    if (items == null || ids == null || !items.contains(item)) return;
    for (final candidate in items) {
      if (ids.contains(candidate.idStr.toString())) candidate.visible = true;
    }
    item.modules.moduleFold = null;
    state = DiscoveryListingState(
      source: state.source,
      loading: Success(List.unmodifiable(items)),
      metadata: state.metadata,
      loadingMore: state.loadingMore,
      hasMore: state.hasMore,
      error: state.error,
    );
  }
}
