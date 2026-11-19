import 'dart:async';
import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/pgc_review_repository.dart';
import 'package:pili_aurora_next/features/community/domain/pgc_review.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef PgcReviewsQuery = ({Object owner, Object? mediaId, PgcReviewType type});

final pgcReviewsProvider = NotifierProvider.autoDispose
    .family<PgcReviews, PgcReviewsState, PgcReviewsQuery>(PgcReviews.new);

class PgcReviewsState {
  const PgcReviewsState({
    required this.account,
    required this.source,
    required this.loading,
    this.sort = .def,
    this.count,
    this.next,
    this.busy = false,
    this.replacing = false,
    this.pageError,
  });

  final Account account;
  final Object source;
  final LoadingState<List<PgcReviewItem>> loading;
  final PgcReviewSortType sort;
  final int? count;
  final String? next;
  final bool busy;
  final bool replacing;
  final Error? pageError;
  bool get canLoadMore => !busy && pageError == null && next != null;
}

class PgcReviews extends Notifier<PgcReviewsState> {
  PgcReviews(this.query);
  final PgcReviewsQuery query;
  final _seenCursors = <String>{};
  final _deleted = <int>{};
  PgcReviewSortType _sort = .def;

  @override
  PgcReviewsState build() {
    final next = _start(ref.watch(mainAccountProvider), _sort);
    scheduleMicrotask(() {
      if (_owns(next) && !state.busy) unawaited(_load(next, first: true));
    });
    return next;
  }

  PgcReviewsState _start(
    Account account,
    PgcReviewSortType sort, {
    PgcReviewsState? previous,
  }) {
    _seenCursors.clear();
    _deleted.clear();
    return PgcReviewsState(
      account: account,
      source: Object(),
      sort: sort,
      loading: previous?.loading ?? LoadingState.loading(),
      count: previous?.count,
    );
  }

  bool _owns(PgcReviewsState snapshot) =>
      ref.mounted &&
      identical(snapshot.account, ref.read(mainAccountProvider)) &&
      identical(snapshot.source, state.source);

  bool contains(PgcReviewsState snapshot, PgcReviewItem item) =>
      _owns(snapshot) &&
      !state.replacing &&
      state.loading.dataOrNull?.contains(item) == true;

  Future<void> refresh({bool clear = false}) {
    final before = state;
    final account = ref.read(mainAccountProvider);
    final next = _start(
      account,
      before.sort,
      previous:
          !clear &&
              identical(account, before.account) &&
              before.loading.isSuccess
          ? before
          : null,
    );
    state = next;
    return _load(next, first: true);
  }

  Future<void> toggleSort() async {
    final before = state;
    if (before.busy) return;
    _sort = before.sort == .def ? .latest : .def;
    final next = _start(ref.read(mainAccountProvider), _sort);
    state = next;
    await _load(next, first: true);
  }

  Future<void> more({bool retry = false}) async {
    final before = state;
    if (!before.busy &&
        before.next != null &&
        (before.pageError == null || retry)) {
      await _load(before, first: false);
    }
  }

  Future<void> _load(PgcReviewsState before, {required bool first}) async {
    if (!_owns(before)) return;
    var cursor = first ? null : before.next;
    int? count = first ? null : before.count;
    state = PgcReviewsState(
      account: before.account,
      source: before.source,
      sort: before.sort,
      loading: before.loading,
      count: before.count,
      next: cursor,
      busy: true,
      replacing: first,
    );
    for (var attempt = 0; attempt < 5; attempt++) {
      final response = await PgcReviewRepository.list(
        account: before.account,
        type: query.type,
        mediaId: query.mediaId,
        sort: before.sort,
        next: cursor,
      );
      if (!_owns(before)) return;
      if (response is! Success<PgcReviewPageData>) {
        final error = response is Error ? response : const Error('点评未返回结果，请重试');
        state = PgcReviewsState(
          account: before.account,
          source: before.source,
          sort: before.sort,
          loading: first ? error : state.loading,
          count: first ? null : state.count,
          next: first ? null : cursor,
          pageError: first ? null : error,
        );
        return;
      }

      final page = response.response;
      final existing = first
          ? const <PgcReviewItem>[]
          : state.loading.dataOrNull ?? const [];
      final seen = <int>{
        ..._deleted,
        for (final item in existing) ?item.reviewId,
      };
      final incoming = [
        for (final item in page.items)
          if (item.reviewId == null || seen.add(item.reviewId!)) item,
      ];
      count = query.type == .long && before.sort == .latest
          ? null
          : page.count ?? (first ? count : state.count);
      if (cursor != null) _seenCursors.add(cursor);
      final next = page.next;
      cursor =
          next != null &&
              next.isNotEmpty &&
              !_seenCursors.contains(next) &&
              (count == null || existing.length + incoming.length < count)
          ? next
          : null;
      if (incoming.isEmpty && cursor != null && attempt < 4) continue;
      state = PgcReviewsState(
        account: before.account,
        source: before.source,
        sort: before.sort,
        loading: Success(List.unmodifiable([...existing, ...incoming])),
        count: count,
        next: cursor,
        pageError: incoming.isEmpty && cursor != null
            ? const Error('连续五页没有新增点评，请继续加载')
            : null,
      );
      return;
    }
  }

  Future<LoadingState<void>?> act(
    PgcReviewsState snapshot,
    PgcReviewItem item,
    PgcReviewAction action,
  ) async {
    final id = item.reviewId;
    if (query.type != .short ||
        id == null ||
        id <= 0 ||
        !contains(snapshot, item)) {
      return null;
    }
    final result = await ref
        .read(pgcReviewWritesProvider.notifier)
        .act(
          snapshot.account,
          query.mediaId,
          id,
          action,
        );
    if (!contains(snapshot, item)) return null;
    if (result?.isSuccess == true) {
      final current = state;
      final deleting = action == .delete;
      if (deleting) _deleted.add(id);
      final stat = item.stat;
      final likes = stat.likes;
      final replacement = switch (action) {
        .like => item.withStat((
          liked: !stat.liked,
          disliked: stat.liked && stat.disliked,
          likes: likes == null ? null : max(0, likes + (stat.liked ? -1 : 1)),
        )),
        .dislike => item.withStat((
          liked: stat.disliked && stat.liked,
          disliked: !stat.disliked,
          likes: likes != null && !stat.disliked && stat.liked
              ? max(0, likes - 1)
              : likes,
        )),
        .delete => null,
      };
      final count = current.count;
      state = PgcReviewsState(
        account: current.account,
        source: current.source,
        sort: current.sort,
        loading: Success(
          List.unmodifiable([
            for (final row in current.loading.data)
              if (!identical(row, item)) row else ?replacement,
          ]),
        ),
        count: deleting && count != null ? max(0, count - 1) : count,
        next: current.next,
        busy: current.busy,
        pageError: current.pageError,
      );
    }
    return result;
  }
}

typedef PgcReviewWrite = ({Account account, String media, String? review});

final pgcReviewWritesProvider =
    NotifierProvider<PgcReviewWrites, List<PgcReviewWrite>>(
      PgcReviewWrites.new,
    );

class PgcReviewWrites extends Notifier<List<PgcReviewWrite>> {
  @override
  List<PgcReviewWrite> build() => const [];

  Future<LoadingState<void>?> act(
    Account account,
    Object? mediaId,
    int reviewId,
    PgcReviewAction action,
  ) => _run(
    account,
    mediaId,
    reviewId,
    () => PgcReviewRepository.act(
      account: account,
      mediaId: mediaId,
      reviewId: reviewId,
      action: action,
    ),
  );

  Future<LoadingState<void>?> submit(
    Account account, {
    required Object? mediaId,
    required int score,
    required String content,
    Object? reviewId,
    required bool shareFeed,
  }) => _run(
    account,
    mediaId,
    reviewId,
    () => PgcReviewRepository.submit(
      account: account,
      mediaId: mediaId,
      score: score,
      content: content,
      reviewId: reviewId,
      shareFeed: shareFeed,
    ),
  );

  Future<LoadingState<void>?> _run(
    Account account,
    Object? mediaId,
    Object? reviewId,
    Future<LoadingState<void>> Function() write,
  ) async {
    if (!identical(account, ref.read(mainAccountProvider))) return null;
    if (!account.isLogin) return const Error('账号未登录');
    final key = (
      account: account,
      media: '$mediaId',
      review: reviewId?.toString(),
    );
    bool matches(PgcReviewWrite pending) =>
        identical(pending.account, account) &&
        pending.media == key.media &&
        pending.review == key.review;
    if (state.any(matches)) return null;
    final owner = ref;
    state = [...state, key];
    try {
      return await write();
    } finally {
      if (owner.mounted) {
        state = [
          for (final pending in state)
            if (!matches(pending)) pending,
        ];
      }
    }
  }
}
