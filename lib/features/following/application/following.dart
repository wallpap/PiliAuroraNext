import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/following/data/following_repository.dart';
import 'package:pili_aurora_next/features/following/domain/following.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/follow_order_type.dart';
import 'package:pili_aurora_next/models/remote/follow/data.dart';
import 'package:pili_aurora_next/models/remote/follow/list.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

export 'package:pili_aurora_next/features/following/domain/following.dart'
    show FollowTag;

const _repository = FollowingRepository();

final followOrderProvider =
    NotifierProvider<FollowOrderNotifier, FollowOrderType>(
      FollowOrderNotifier.new,
    );

class FollowOrderNotifier extends Notifier<FollowOrderType> {
  @override
  FollowOrderType build() => _repository.order;
  void toggle() {
    state = state == FollowOrderType.def
        ? FollowOrderType.attention
        : FollowOrderType.def;
    unawaited(_repository.saveOrder(state));
  }
}

typedef FollowingQuery = ({int? mid, int? tagid, String? keyword});
final followingProvider =
    AsyncNotifierProvider.family<
      FollowingNotifier,
      FollowingState,
      FollowingQuery
    >(FollowingNotifier.new, isAutoDispose: true, retry: (_, _) => null);

class FollowingState {
  FollowingState({
    required this.source,
    required Iterable<FollowItemModel> items,
    required this.total,
    required this.nextPage,
    required this.hasMore,
    this.isLoadingMore = false,
    this.pageError,
  }) : items = List.unmodifiable(items);
  final Object source;
  final List<FollowItemModel> items;
  final int? total;
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String? pageError;
  bool get canLoadMore => hasMore && !isLoadingMore && pageError == null;
  FollowingState operation({bool isLoadingMore = false, String? pageError}) =>
      FollowingState(
        source: source,
        items: items,
        total: total,
        nextPage: nextPage,
        hasMore: hasMore,
        isLoadingMore: isLoadingMore,
        pageError: pageError,
      );
}

class FollowingNotifier extends AsyncNotifier<FollowingState> {
  FollowingNotifier(this.query);
  final FollowingQuery query;
  static const pageSize = 20;
  @override
  Future<FollowingState> build() async {
    final account = ref.watch(mainAccountProvider);
    final order = query.keyword == null
        ? ref.watch(followOrderProvider)
        : FollowOrderType.attention;
    return _merge(null, await _page(account, order, 1), 1);
  }

  Future<FollowData> _page(
    Account account,
    FollowOrderType order,
    int page,
  ) => _repository.following(
    account: account,
    mid: query.mid ?? account.mid,
    page: page,
    pageSize: pageSize,
    order: order,
    tag: query.tagid,
    keyword: query.keyword,
  );

  FollowingState _merge(
    FollowingState? current,
    FollowData response,
    int page,
  ) {
    final rows = response.list ?? const <FollowItemModel>[];
    final ids = <int>{};
    final items = [
      for (final row in [...?current?.items, ...rows])
        if (ids.add(row.mid)) row,
    ];
    final total = response.total ?? current?.total;
    return FollowingState(
      source: current?.source ?? Object(),
      items: items,
      total: total,
      nextPage: page + 1,
      hasMore:
          rows.isNotEmpty &&
          (total == null ? rows.length >= pageSize : page * pageSize < total) &&
          (current == null || items.length > current.items.length),
    );
  }

  Future<void> loadMore({bool retry = false}) async {
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        (!retry && current.pageError != null)) {
      return;
    }
    final owner = ref;
    final account = owner.read(mainAccountProvider);
    bool ownsQuery() =>
        owner.mounted && identical(account, owner.read(mainAccountProvider));
    final order = query.keyword == null
        ? owner.read(followOrderProvider)
        : FollowOrderType.attention;
    state = AsyncData(current.operation(isLoadingMore: true));
    try {
      final response = await _page(account, order, current.nextPage);
      if (!ownsQuery()) return;
      state = AsyncData(_merge(current, response, current.nextPage));
    } catch (_) {
      if (ownsQuery()) {
        state = AsyncData(current.operation(pageError: '加载失败，点击重试'));
      }
    }
  }
}

class FollowTagsState {
  FollowTagsState(
    Iterable<FollowTag> tags, {
    Object? source,
    this.isSaving = false,
  }) : tags = List.unmodifiable(tags),
       source = source ?? Object();
  final List<FollowTag> tags;
  final Object source;
  final bool isSaving;
}

final followTagsProvider =
    AsyncNotifierProvider<FollowTagsNotifier, FollowTagsState>(
      FollowTagsNotifier.new,
      isAutoDispose: true,
      retry: (_, _) => null,
    );

final _tagWritesProvider = Provider(
  (ref) => <int, ({Account account, Completer<void> done})>{},
);

class FollowTagsNotifier extends AsyncNotifier<FollowTagsState> {
  @override
  Future<FollowTagsState> build() async {
    final owner = ref;
    final account = owner.watch(mainAccountProvider);
    if (!account.isLogin) throw const Error('账号未登录');
    final pending = owner.read(_tagWritesProvider)[account.mid];
    if (pending != null && identical(pending.account, account)) {
      await pending.done.future;
      if (!owner.mounted ||
          !identical(account, owner.read(mainAccountProvider))) {
        throw const Error('分组或账号已更新，请重试');
      }
    }
    return FollowTagsState(await _repository.tags(account));
  }

  Future<LoadingState<T>> _write<T>(
    Object source,
    Future<LoadingState<T>> Function(Account) send,
    List<FollowTag> Function(List<FollowTag>, T) apply, {
    bool reloadLists = false,
    Object? nextSource,
  }) async {
    final before = state.value;
    final owner = ref;
    final account = owner.read(mainAccountProvider);
    final writes = owner.read(_tagWritesProvider);
    bool ownsWrite() =>
        owner.mounted && identical(account, owner.read(mainAccountProvider));
    if (state.isLoading ||
        state.hasError ||
        before == null ||
        before.isSaving ||
        !identical(source, before.source) ||
        !account.isLogin ||
        writes.containsKey(account.mid)) {
      return const Error('分组或账号已更新，请重试');
    }
    final done = Completer<void>();
    writes[account.mid] = (account: account, done: done);
    state = AsyncData(
      FollowTagsState(before.tags, source: before.source, isSaving: true),
    );
    try {
      final result = await send(account);
      if (!ownsWrite()) {
        return const Error('账号已切换或页面已关闭');
      }
      if (result case Success(:final response)) {
        state = AsyncData(
          FollowTagsState(apply(before.tags, response), source: nextSource),
        );
        if (reloadLists) owner.invalidate(followingProvider);
      } else {
        state = AsyncData(before);
      }
      return result;
    } catch (error, stackTrace) {
      if (ownsWrite()) {
        state = AsyncData(before);
      }
      final failure = Error.fromException(error, stackTrace);
      return UnknownResult(
        message: '操作结果待确认，请刷新分组后核对',
        cause: failure.cause,
        stackTrace: failure.stackTrace,
      );
    } finally {
      writes.remove(account.mid);
      done.complete();
    }
  }

  Future<LoadingState<({int id, Object source})>> create(
    String name,
    Object source,
  ) async {
    name = name.trim();
    if (name.isEmpty || name.runes.length > 16) {
      return const Error('分组名称须为 1–16 个字符');
    }
    final nextSource = Object();
    final result = await _write(
      source,
      (account) => _repository.createTag(account, name),
      (tags, id) => [...tags, FollowTag(id: id, name: name, count: 0)],
      nextSource: nextSource,
    );
    return switch (result) {
      Success(:final response) => Success((id: response, source: nextSource)),
      Error() => result,
      _ => const Error('创建未完成'),
    };
  }

  Future<LoadingState<void>> rename(int id, String name, Object source) {
    name = name.trim();
    if (!isCustomFollowTag(id) ||
        name.isEmpty ||
        name.runes.length > 16 ||
        !(state.value?.tags.any((tag) => tag.id == id) ?? false)) {
      return Future.value(const Error('分组已更新或名称无效'));
    }
    return _write(
      source,
      (account) => _repository.renameTag(account, id, name),
      (tags, _) => [
        for (final tag in tags)
          if (tag.id == id)
            FollowTag(id: id, name: name, count: tag.count, tip: tag.tip)
          else
            tag,
      ],
    );
  }

  Future<LoadingState<void>> remove(int id, Object source) {
    if (!isCustomFollowTag(id) ||
        !(state.value?.tags.any((tag) => tag.id == id) ?? false)) {
      return Future.value(const Error('分组已更新'));
    }
    return _write(
      source,
      (account) => _repository.deleteTag(account, id),
      (tags, _) => tags.where((tag) => tag.id != id).toList(),
      reloadLists: true,
    );
  }

  Future<LoadingState<void>> reorder(List<int> ids, Object source) {
    final custom =
        state.value?.tags.where((tag) => tag.isCustom).toList() ?? [];
    if (ids.isEmpty ||
        ids.length != custom.length ||
        ids.toSet().length != ids.length ||
        !custom.every((tag) => ids.contains(tag.id))) {
      return Future.value(const Error('分组已更新，请重新排序'));
    }
    final order = List<int>.of(ids);
    return _write(
      source,
      (account) => _repository.sortTags(account, order),
      (tags, _) => [
        ...tags.where((tag) => !tag.isCustom),
        for (final id in order) custom.firstWhere((tag) => tag.id == id),
      ],
    );
  }

  Future<LoadingState<void>> assign(
    int mid,
    Set<int> ids,
    Object source,
  ) async {
    final selected = Set<int>.of(ids);
    if (!(state.value?.tags
            .map((tag) => tag.id)
            .toSet()
            .containsAll(selected) ??
        false)) {
      return const Error('分组已更新，请重试');
    }
    final owner = ref;
    final result = await _write(
      source,
      (account) => _repository.assignTags(account, mid, selected),
      (tags, _) => tags,
      reloadLists: true,
    );
    // 成员变动后的计数由服务端重新确认，不推算未知的旧分组归属。
    if (result.isSuccess && owner.mounted) owner.invalidateSelf();
    return result;
  }
}
