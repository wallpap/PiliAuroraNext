import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_actions.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef MemberDynamicsQuery = ({Object owner, int mid});
final memberDynamicsProvider = NotifierProvider.autoDispose
    .family<
      MemberDynamics,
      DiscoveryListingState<DynamicItemModel, DynamicCursor>,
      MemberDynamicsQuery
    >(MemberDynamics.new);

class MemberDynamics extends DiscoveryListing<DynamicItemModel, DynamicCursor> {
  MemberDynamics(this.query);
  final MemberDynamicsQuery query;
  // 空间只有一个置顶；已确认取消与尚未操作分别表示，显式刷新后采用远端状态。
  bool _hasPinChange = false;
  String? _pinnedId;
  @override
  bool get usesMainAccount => true;
  @override
  bool get filterAuthors => false;
  @override
  Object itemKey(DynamicItemModel item) => item.idStr?.toString() ?? item;

  @override
  DiscoveryListingState<DynamicItemModel, DynamicCursor> build() {
    _hasPinChange = false;
    _pinnedId = null;
    final account = ref.watch(mainAccountProvider);
    final updates = ref.read(dynamicsUpdatesProvider).changes.listen((change) {
      if (!ref.mounted || !identical(account, change.account)) return;
      if (change.removed case final id?) {
        excludeKey(id);
      } else if (change.pin case final pin?) {
        if (query.mid == account.mid) {
          _hasPinChange = true;
          _pinnedId = pin.pinned ? pin.id : null;
          final items = state.loading.dataOrNull;
          if (items != null) {
            _applyPin(items);
            state = DiscoveryListingState(
              source: state.source,
              loading: Success(orderItems(items)),
              metadata: state.metadata,
              loadingMore: state.loadingMore,
              hasMore: state.hasMore,
              error: state.error,
            );
          }
        }
      } else {
        unawaited(onRefresh());
      }
    });
    ref.onDispose(() => unawaited(updates.cancel()));
    return super.build();
  }

  @override
  Future<void> onRefresh() {
    _hasPinChange = false;
    _pinnedId = null;
    return super.onRefresh();
  }

  void _applyPin(Iterable<DynamicItemModel> items) {
    if (!_hasPinChange) return;
    for (final item in items) {
      if (itemKey(item) == _pinnedId) {
        item.modules
          ..moduleTag = ModuleTag(text: '置顶')
          ..moduleAuthor?.isTop = true;
      } else if (item.isPinned) {
        item.modules
          ..moduleTag = null
          ..moduleAuthor?.isTop = false;
      }
    }
  }

  @override
  List<DynamicItemModel> orderItems(List<DynamicItemModel> items) =>
      List.unmodifiable([
        ...items.where((item) => itemKey(item) == _pinnedId),
        ...items.where((item) => itemKey(item) != _pinnedId),
      ]);

  @override
  Future<LoadingState<DiscoveryPage<DynamicItemModel, DynamicCursor>>> fetch(
    Account account,
    int page,
  ) async {
    final current = captureQuery();
    final result = await ref
        .read(dynamicsRepositoryProvider)
        .member(account, query.mid, queryMetadata);
    if (result case Success(:final response) when current()) {
      _applyPin(response.items);
      return Success(
        DiscoveryPage(
          response.items,
          metadata: response.metadata,
          hasMore: response.hasMore,
        ),
      );
    }
    return result;
  }

  bool Function() captureItem(DynamicItemModel item) {
    final current = captureQuery();
    final source = state.source;
    return () =>
        current() &&
        identical(source, state.source) &&
        !state.loadingMore &&
        (state.loading.dataOrNull?.contains(item) ?? false);
  }

  Future<LoadingState<void>> removeItem(DynamicItemModel item, Object source) =>
      _write(item, source, null);
  Future<LoadingState<void>> setPinned(
    DynamicItemModel item,
    Object source,
    bool wasPinned,
  ) => item.isPinned == wasPinned
      ? _write(item, source, !wasPinned)
      : Future.value(const Error('动态置顶状态已更新，请重试'));

  Future<LoadingState<void>> _write(
    DynamicItemModel item,
    Object source,
    bool? pinned,
  ) {
    final account = ref.read(mainAccountProvider);
    if (!identical(source, state.source) ||
        !captureItem(item)() ||
        query.mid != account.mid) {
      return Future.value(const Error('账号或动态已更新，请刷新'));
    }
    final actions = ref.read(dynamicsActionsProvider);
    final id = item.idStr.toString();
    return pinned == null
        ? actions.remove(account, id)
        : actions.pin(account, id, pinned);
  }
}
