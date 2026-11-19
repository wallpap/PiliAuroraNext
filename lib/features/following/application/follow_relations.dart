import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/following/data/following_repository.dart';
import 'package:pili_aurora_next/features/following/domain/following.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/follow/data.dart';
import 'package:pili_aurora_next/models/remote/follow/list.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

export 'package:pili_aurora_next/features/following/domain/following.dart'
    show FollowKind;

const _repository = FollowingRepository();

// 同一账号的关系写入互斥，避免其他入口刷新与并发写入交错。
final _writeGateProvider = Provider<_WriteGate>((ref) => _WriteGate());

class _WriteGate {
  final _pending = <int>{};
  bool acquire(int accountMid) => _pending.add(accountMid);
  void release(int accountMid) => _pending.remove(accountMid);
}

typedef FollowQuery = ({FollowKind kind, int? mid, bool newFans});

final followNameProvider = FutureProvider.family<String?, int?>(
  (ref, mid) {
    final account = ref.watch(mainAccountProvider);
    return _repository.memberName(account, mid ?? account.mid);
  },
  isAutoDispose: true,
  retry: (_, _) => null,
);

final followQueryProvider =
    AsyncNotifierProvider.family<
      FollowQueryNotifier,
      FollowQueryState,
      FollowQuery
    >(FollowQueryNotifier.new, isAutoDispose: true, retry: (_, _) => null);

class FollowQueryState {
  FollowQueryState({
    required this.source,
    required Iterable<FollowItemModel> items,
    required this.total,
    required this.nextPage,
    required this.hasMore,
    this.isLoadingMore = false,
    this.busyMid,
    this.pageError,
  }) : items = List.unmodifiable(items);
  final Object source;
  final List<FollowItemModel> items;
  final int? total;
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final int? busyMid;
  final String? pageError;
  bool get canLoadMore =>
      hasMore && !isLoadingMore && busyMid == null && pageError == null;
  FollowQueryState operation({
    bool isLoadingMore = false,
    int? busyMid,
    String? pageError,
  }) => FollowQueryState(
    source: source,
    items: items,
    total: total,
    nextPage: nextPage,
    hasMore: hasMore,
    isLoadingMore: isLoadingMore,
    busyMid: busyMid,
    pageError: pageError,
  );
}

class FollowQueryNotifier extends AsyncNotifier<FollowQueryState> {
  FollowQueryNotifier(this.query);
  final FollowQuery query;
  static const pageSize = 20;
  @override
  Future<FollowQueryState> build() async {
    final account = ref.watch(mainAccountProvider);
    return _merge(null, await _page(account, 1), 1);
  }

  Future<FollowData> _page(Account account, int page) => _repository.relations(
    account: account,
    mid: query.mid ?? account.mid,
    kind: query.kind,
    page: page,
    pageSize: pageSize,
    newestFirst: query.newFans,
  );

  FollowQueryState _merge(
    FollowQueryState? current,
    FollowData response,
    int page,
  ) {
    final pageItems = response.list ?? const <FollowItemModel>[];
    final ids = <int>{};
    final items = [
      for (final item in [...?current?.items, ...pageItems])
        if (ids.add(item.mid)) item,
    ];
    final total = response.total ?? current?.total;
    final replay =
        current != null && page <= (current.items.length / pageSize).ceil();
    return FollowQueryState(
      source: current?.source ?? Object(),
      items: items,
      total: total,
      nextPage: page + 1,
      hasMore:
          pageItems.isNotEmpty &&
          (total == null
              ? pageItems.length >= pageSize
              : items.length < total) &&
          (current == null || items.length > current.items.length || replay),
    );
  }

  Future<void> loadMore({bool retry = false}) async {
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        current.busyMid != null ||
        (!retry && current.pageError != null)) {
      return;
    }
    final requestRef = ref;
    final account = requestRef.read(mainAccountProvider);
    bool ownsQuery() =>
        requestRef.mounted &&
        identical(account, requestRef.read(mainAccountProvider));
    state = AsyncData(current.operation(isLoadingMore: true));
    try {
      final response = await _page(account, current.nextPage);
      if (!ownsQuery()) return;
      state = AsyncData(_merge(current, response, current.nextPage));
    } catch (_) {
      if (ownsQuery()) {
        state = AsyncData(current.operation(pageError: '加载失败，点击重试'));
      }
    }
  }

  Future<LoadingState<void>> followBack(int mid) => _write(mid, remove: false);
  Future<LoadingState<void>> remove(int mid) => _write(mid, remove: true);
  Future<LoadingState<void>> _write(int mid, {required bool remove}) async {
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        current.isLoadingMore ||
        current.busyMid != null) {
      return const Error('请等待当前操作完成');
    }
    final matching = current.items.where((item) => item.mid == mid);
    if (matching.isEmpty) return const Error('列表已更新');
    final item = matching.first;
    final requestRef = ref;
    final account = requestRef.read(mainAccountProvider);
    bool ownsQuery() =>
        requestRef.mounted &&
        identical(account, requestRef.read(mainAccountProvider));
    if (!account.isLogin ||
        query.kind != FollowKind.fans ||
        (query.mid ?? account.mid) != account.mid) {
      return const Error('账号已切换或无操作权限');
    }
    final gate = requestRef.read(_writeGateProvider);
    if (!gate.acquire(account.mid)) return const Error('请等待当前操作完成');
    final isFollowing = item.attribute == 2 || item.attribute == 6;
    state = AsyncData(current.operation(busyMid: mid));
    try {
      final result = await _repository.updateFan(
        account,
        mid,
        remove: remove,
        isFollowing: isFollowing,
      );
      if (!ownsQuery()) {
        return const Error('账号已切换或页面已关闭');
      }
      if (!result.isSuccess) {
        state = AsyncData(current);
        return result;
      }
      if (remove) {
        final items = current.items.where((item) => item.mid != mid).toList();
        final total = current.total == null
            ? null
            : math.max(
                0,
                current.total! - (current.items.length - items.length),
              );
        state = AsyncData(
          FollowQueryState(
            source: current.source,
            items: items,
            total: total,
            nextPage: math.min(current.nextPage, items.length ~/ pageSize + 1),
            hasMore: current.hasMore && (total == null || items.length < total),
          ),
        );
      } else {
        final updated = FollowItemModel(
          mid: item.mid,
          uname: item.uname,
          face: item.face,
          attribute: isFollowing ? 0 : 6,
          mtime: item.mtime,
          sign: item.sign,
          officialVerify: item.officialVerify,
        );
        state = AsyncData(
          FollowQueryState(
            source: current.source,
            items: [
              for (final value in current.items)
                if (value.mid == mid) updated else value,
            ],
            total: current.total,
            nextPage: current.nextPage,
            hasMore: current.hasMore,
          ),
        );
      }
      // 同账号的其他粉丝入口可能持有旧关系或旧偏移，成功后重新查询。
      for (final target in <int?>[null, account.mid]) {
        for (final recent in [false, true]) {
          final other = (kind: FollowKind.fans, mid: target, newFans: recent);
          if (other != query) requestRef.invalidate(followQueryProvider(other));
        }
      }
      return const Success(null);
    } catch (_) {
      if (ownsQuery()) {
        state = AsyncData(current);
      }
      return const Error('操作未完成，请刷新后核对');
    } finally {
      gate.release(account.mid);
    }
  }
}
