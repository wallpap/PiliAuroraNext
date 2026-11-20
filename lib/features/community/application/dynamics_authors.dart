import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_selection.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/up.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class DynamicsAuthorsState {
  DynamicsAuthorsState({
    required this.source,
    LoadingState<FollowUpModel>? loading,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  }) : loading = loading ?? LoadingState.loading();
  final Object source;
  final LoadingState<FollowUpModel> loading;
  final bool loadingMore, hasMore;
  final Error? error;
  bool get canLoadMore =>
      !loadingMore && hasMore && error == null && loading is Success;
}

class _Owner {
  _Owner(this.account);
  final Account account;
  bool disposed = false, dynamicEnd = false, hasSnapshot = false;
  String? offset;
  int page = 1;
  final offsets = <String>{}, read = <int>{};
}

final dynamicsAuthorsProvider = NotifierProvider.autoDispose
    .family<DynamicsAuthors, DynamicsAuthorsState, Object>(DynamicsAuthors.new);

class DynamicsAuthors extends Notifier<DynamicsAuthorsState> {
  DynamicsAuthors(this.pageOwner);
  final Object pageOwner;
  late _Owner _owner;
  @override
  DynamicsAuthorsState build() {
    final owner = _owner = _Owner(ref.watch(mainAccountProvider));
    ref.onDispose(() => owner.disposed = true);
    scheduleMicrotask(() {
      if (_current(owner)) unawaited(_load(owner));
    });
    return DynamicsAuthorsState(source: owner);
  }

  bool _current(_Owner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(owner, _owner) &&
      identical(owner.account, ref.read(mainAccountProvider));
  Future<void> onRefresh() {
    final previous = _current(_owner) ? state : null;
    _owner.disposed = true;
    final owner = _owner = _Owner(ref.read(mainAccountProvider));
    state = DynamicsAuthorsState(
      source: owner,
      loading: previous?.loading is Success ? previous!.loading : null,
      hasMore: previous?.hasMore ?? true,
    );
    return _load(owner);
  }

  Future<void> onLoadMore() =>
      state.canLoadMore ? _load(_owner) : Future.value();
  Future<void> retry() =>
      state.loading is Success ? _load(_owner) : onRefresh();
  void markRead(int mid) {
    _owner.read.add(mid);
    final data = state.loading.dataOrNull;
    if (data == null) return;
    final items = (data.upList ?? [])
        .map(
          (up) => UpItem(
            mid: up.mid,
            face: up.face,
            uname: up.uname,
            hasUpdate: up.mid == mid ? false : up.hasUpdate,
          ),
        )
        .toList();
    state = DynamicsAuthorsState(
      source: _owner,
      loading: Success(
        FollowUpModel.fromUpList(null)
          ..upList = items
          ..liveUsers = data.liveUsers,
      ),
      loadingMore: state.loadingMore,
      hasMore: state.hasMore,
      error: state.error,
    );
  }

  Future<void> _load(_Owner owner) async {
    if (!_current(owner) || state.loadingMore) return;
    state = DynamicsAuthorsState(
      source: owner,
      loading: state.loading,
      loadingMore: true,
      hasMore: state.hasMore,
    );
    // 同账号刷新期间保留面板，首包成功后再替换旧作者与直播资料。
    var data = owner.hasSnapshot ? state.loading.dataOrNull : null;
    var hasMore = state.hasMore;
    Error? error;
    final all = ref.read(dynamicsPreferencesProvider).allFollowed;
    try {
      for (var attempt = 0; attempt < 5 && _current(owner); attempt++) {
        final following = owner.dynamicEnd;
        final result = await ref
            .read(dynamicsRepositoryProvider)
            .authors(
              owner.account,
              offset: owner.offset,
              followingPage: following ? owner.page : null,
            );
        if (!_current(owner)) return;
        if (result case Error failure) {
          error = failure;
          break;
        }
        if (result is! Success<FollowUpModel>) break;
        final response = result.response;
        var incoming = response.upList ?? <UpItem>[];
        if (following) {
          owner.page++;
          hasMore = incoming.isNotEmpty;
        } else {
          final offset = response.offset;
          final repeated = offset != null && !owner.offsets.add(offset);
          owner
            ..dynamicEnd =
                response.hasMore != true ||
                offset == null ||
                offset.isEmpty ||
                repeated
            ..offset = offset;
          if (repeated) incoming = [];
          hasMore = all || !owner.dynamicEnd;
        }
        // 分页在途时仍保留当前已读标记及已确认资料。
        final merged = {
          for (final up in data?.upList ?? <UpItem>[])
            up.mid: UpItem(
              mid: up.mid,
              face: up.face,
              uname: up.uname,
              hasUpdate: owner.read.contains(up.mid) ? false : up.hasUpdate,
            ),
        };
        var added = 0;
        for (final up in incoming) {
          final old = merged[up.mid];
          if (old == null) added++;
          merged[up.mid] = UpItem(
            mid: up.mid,
            face: old?.face ?? up.face,
            uname: old?.uname ?? up.uname,
            hasUpdate: owner.read.contains(up.mid)
                ? false
                : old?.hasUpdate ?? up.hasUpdate,
          );
        }
        final ordered = [
          ...merged.values.where((up) => up.hasUpdate == true),
          ...merged.values.where((up) => up.hasUpdate != true),
        ];
        data = FollowUpModel.fromUpList(null)
          ..upList = List.unmodifiable(ordered)
          ..liveUsers = response.liveUsers ?? data?.liveUsers;
        owner.hasSnapshot = true;
        if (added > 0 || !hasMore) break;
        if (attempt == 4) error = const Error('连续多页无新增作者，点击继续加载');
      }
    } catch (cause, stack) {
      error = Error.fromException(cause, stack);
    }
    if (!_current(owner)) return;
    state = DynamicsAuthorsState(
      source: owner,
      loading: data == null && error != null
          ? state.loading is Success
                ? state.loading
                : error
          : Success(data ?? FollowUpModel.fromUpList(null)),
      hasMore: hasMore,
      error: error,
    );
  }
}
