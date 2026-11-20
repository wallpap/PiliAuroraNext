import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_discovery/data/blocked_author_repository.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/blocked_author.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final blackListProvider =
    AsyncNotifierProvider<BlackListNotifier, BlackListState>(
      BlackListNotifier.new,
      isAutoDispose: true,
      retry: (_, _) => null,
    );

class BlackListState {
  const BlackListState._({
    required this.source,
    required this.items,
    required this.total,
    required this.nextPage,
    required this.hasMore,
    this.isLoadingMore = false,
    this.removingMid,
    this.pageError,
  });

  final List<BlockedAuthor> items;
  final Object source;
  final int? total;
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final int? removingMid;
  final String? pageError;

  bool get canLoadMore =>
      hasMore && !isLoadingMore && removingMid == null && pageError == null;

  BlackListState _withOperation({
    bool isLoadingMore = false,
    int? removingMid,
    String? pageError,
  }) => BlackListState._(
    source: source,
    items: items,
    total: total,
    nextPage: nextPage,
    hasMore: hasMore,
    isLoadingMore: isLoadingMore,
    removingMid: removingMid,
    pageError: pageError,
  );
}

class BlackListNotifier extends AsyncNotifier<BlackListState> {
  static const _repository = BlockedAuthorRepository();

  @override
  Future<BlackListState> build() async {
    final account = ref.watch(mainAccountProvider);
    if (!account.isLogin) throw const Error('账号未登录');
    final response = await _page(account, 1);
    return _merge(null, response, 1);
  }

  Future<BlockedAuthorPage> _page(Account account, int page) async {
    final result = await _repository.load(account, page);
    return switch (result) {
      Success(:final response) => response,
      _ => throw result,
    };
  }

  BlackListState _merge(
    BlackListState? current,
    BlockedAuthorPage response,
    int page,
  ) {
    final source = response.items;
    final seen = <int>{};
    final items = [
      if (current != null)
        for (final item in current.items)
          if (item.mid == null || seen.add(item.mid!)) item,
      for (final item in source)
        if (item.mid == null || seen.add(item.mid!)) item,
    ];
    final total = response.total ?? current?.total;
    // 移除后重读末页时允许一次无增长；普通重复页则停止，避免循环请求。
    final replay =
        current != null &&
        page <= (current.items.length / blockedAuthorPageSize).ceil();
    return BlackListState._(
      source: current?.source ?? Object(),
      items: List.unmodifiable(items),
      total: total,
      nextPage: page + 1,
      hasMore:
          source.length >= blockedAuthorPageSize &&
          (total == null || page * blockedAuthorPageSize < total) &&
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
        current.removingMid != null ||
        (!retry && current.pageError != null)) {
      return;
    }
    final requestRef = ref;
    final account = requestRef.read(mainAccountProvider);
    state = AsyncData(current._withOperation(isLoadingMore: true));
    try {
      final response = await _page(account, current.nextPage);
      if (!requestRef.mounted || !identical(account, Accounts.main)) return;
      state = AsyncData(_merge(current, response, current.nextPage));
    } catch (_) {
      if (requestRef.mounted && identical(account, Accounts.main)) {
        state = AsyncData(current._withOperation(pageError: '加载失败，点击重试'));
      }
    }
  }

  Future<LoadingState<void>> remove(int mid) async {
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        current.isLoadingMore ||
        current.removingMid != null) {
      return const Error('请等待当前操作完成');
    }
    if (!current.items.any((item) => item.mid == mid)) {
      return const Error('列表已更新');
    }
    final requestRef = ref;
    final account = requestRef.read(mainAccountProvider);
    if (!identical(account, Accounts.main)) return const Error('账号已切换');
    state = AsyncData(current._withOperation(removingMid: mid));
    try {
      final result = await _repository.remove(account, mid);
      if (!requestRef.mounted || !identical(account, Accounts.main)) {
        return const Error('账号已切换或页面已关闭');
      }
      if (result.isSuccess) {
        final items = current.items.where((item) => item.mid != mid).toList();
        final total = current.total == null
            ? null
            : math.max(
                0,
                current.total! - (current.items.length - items.length),
              );
        state = AsyncData(
          BlackListState._(
            source: current.source,
            items: List.unmodifiable(items),
            total: total,
            // 页码按远端偏移计算；删除会使后续内容前移，重读边界页后按 UID 合并。
            nextPage: math.min(
              current.nextPage,
              items.length ~/ blockedAuthorPageSize + 1,
            ),
            hasMore: current.hasMore && (total == null || items.length < total),
          ),
        );
      } else {
        state = AsyncData(current);
      }
      return result;
    } catch (_) {
      if (requestRef.mounted && identical(account, Accounts.main)) {
        state = AsyncData(current);
      }
      return const Error('操作未完成，请刷新黑名单后核对');
    }
  }
}
