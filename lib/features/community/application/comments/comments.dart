import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/comments/comments_repository.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/features/community/domain/comment_filter.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/comments/reply_sort_type.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/community/application/comments/comment_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/application/blocked_authors.dart';

typedef CommentTarget = ({int oid, int type});
typedef CommentThread = ({int root, int? reply, int? dialog, int? seedAuthor});
typedef CommentsQuery = ({
  Object owner,
  CommentTarget target,
  CommentThread? thread,
});

const commentActions = CommentsRepository();

final commentsProvider = NotifierProvider.autoDispose
    .family<Comments, CommentsState, CommentsQuery>(Comments.new);

class CommentsState {
  const CommentsState({
    required this.source,
    required this.loading,
    required this.sort,
    this.subject,
    this.vote,
    this.root,
    this.count = -1,
    this.hasMore = true,
    this.busy = false,
    this.pageError,
  });

  final Object source;
  final LoadingState<List<CommentReply>> loading;
  final ReplySortType sort;
  final CommentSubject? subject;
  final CommentVoteCard? vote;
  final CommentReply? root;
  final int count;
  final bool hasMore;
  final bool busy;
  final Error? pageError;
  Int64? get upMid => subject?.upMid;
  bool get canLoadMore =>
      hasMore && !busy && pageError == null && loading is Success;
}

class _Owner {
  _Owner(this.account);
  final Account account;
  Int64? cursor;
  String? offset;
  bool disposed = false;
  int? replyAnchor;
}

class Comments extends Notifier<CommentsState> {
  Comments(this.query);
  final CommentsQuery query;
  late _Owner _owner;
  late Object _accountGeneration;
  Object? _pinOperation;
  bool get _writingPin => identical(_pinOperation, _accountGeneration);
  late ReplySortType _sort;

  @override
  CommentsState build() {
    final account = ref.watch(mainAccountProvider);
    _accountGeneration = Object();
    _sort = query.thread == null
        ? CommentPreferences.defaultSort
        : CommentPreferences.threadSort;
    final owner = _owner = _Owner(account)..replyAnchor = query.thread?.reply;
    final blocks = BlockedAuthors.blocks.listen((change) {
      final current = _owner;
      if (_current(current) && identical(current.account, change.account)) {
        _applyBlock(change.mid);
      }
    });
    ref.onDispose(() {
      _owner.disposed = true;
      unawaited(blocks.cancel());
    });
    scheduleMicrotask(() {
      if (_current(owner)) unawaited(_load(owner, replacing: true));
    });
    return CommentsState(
      source: owner,
      loading: LoadingState.loading(),
      sort: _sort,
    );
  }

  bool _current(_Owner owner) =>
      !owner.disposed &&
      ref.mounted &&
      identical(owner, _owner) &&
      identical(owner.account, ref.read(mainAccountProvider));

  bool get checkCommentVisibility =>
      CommentPreferences.checkSendCriteria || sendVisibilityCheck;
  bool get sendVisibilityCheck => CommentPreferences.checkSendVisibility;

  Account get accountIdentity => _owner.account;

  bool isAuthorBlocked(CommentReply reply) =>
      _owner.account.isLogin &&
      BlockedAuthors.contains(reply.authorMid.toInt());

  CommentReply? _filterRoot(
    CommentReply? root,
    bool Function(CommentReply) isBlocked,
  ) {
    if (root == null || isBlocked(root)) return null;
    final replies = filterRepliesByAuthor(root.replies, isBlocked);
    return identical(replies, root.replies)
        ? root
        : root.copy(replies: replies);
  }

  void _applyBlock(int mid) {
    final before = state;
    final rows = before.loading.dataOrNull;
    bool isBlocked(CommentReply reply) => reply.authorMid.toInt() == mid;
    final filtered = rows == null
        ? null
        : filterRepliesByAuthor(rows, isBlocked);
    final root = _filterRoot(before.root, isBlocked);
    final hidesSeed = before.root == null && query.thread?.seedAuthor == mid;
    if (!hidesSeed &&
        identical(filtered, rows) &&
        identical(root, before.root)) {
      return;
    }
    _replaceSnapshot(
      before,
      loading: identical(filtered, rows)
          ? before.loading
          : Success(List.unmodifiable(filtered!)),
      root: root,
      count: before.count,
    );
  }

  bool Function() capture() {
    final generation = _accountGeneration;
    final account = _owner.account;
    return () =>
        ref.mounted &&
        identical(generation, _accountGeneration) &&
        identical(account, ref.read(mainAccountProvider));
  }

  Future<void> refresh({bool clear = false}) async {
    if (!_current(_owner)) return;
    _owner.disposed = true;
    final owner = _owner = _Owner(_owner.account);
    final previous = state;
    state = CommentsState(
      source: owner,
      loading: clear ? LoadingState.loading() : previous.loading,
      sort: _sort,
      count: previous.count,
      root: previous.root,
      subject: clear ? null : previous.subject,
      vote: clear ? null : previous.vote,
    );
    await _load(owner, replacing: true);
  }

  Future<void> toggleSort() async {
    if (state.busy || state.sort == ReplySortType.select) return;
    _sort = _sort == ReplySortType.hot ? .time : .hot;
    await refresh(clear: true);
  }

  Future<void> loadMore({bool retry = false}) async {
    final before = state;
    if (!_current(_owner) ||
        _writingPin ||
        before.busy ||
        !before.hasMore ||
        before.loading is! Success ||
        (!retry && before.pageError != null)) {
      return;
    }
    await _load(_owner, replacing: false);
  }

  Future<void> _load(_Owner owner, {required bool replacing}) async {
    final before = state;
    state = CommentsState(
      source: owner,
      loading: before.loading,
      sort: before.sort,
      count: before.count,
      subject: before.subject,
      vote: before.vote,
      root: before.root,
      hasMore: before.hasMore,
      busy: true,
    );
    final repository = ref.read(commentsRepositoryProvider);
    final minLevel = CommentPreferences.minimumUserLevel;
    final items = <CommentReply>[if (!replacing) ...?before.loading.dataOrNull];
    final seen = <Int64>{for (final item in items) item.id};
    var count = before.count;
    var subject = before.subject;
    var vote = before.vote;
    var root = before.root;
    var hasMore = before.hasMore;
    var sort = before.sort;
    var applied = false;
    Error? error;
    try {
      var remaining = 0;
      for (var attempt = 0; attempt < 5 && _current(owner); attempt++) {
        final thread = query.thread;
        final response = thread == null
            ? await repository.main(
                owner.account,
                query.target,
                _sort,
                owner.cursor,
                owner.offset,
              )
            : await repository.thread(
                owner.account,
                query.target,
                thread.root,
                thread.dialog,
                owner.replyAnchor,
                _sort,
                owner.offset,
              );
        if (!_current(owner)) return;
        if (response case Error failure) {
          error = failure;
          break;
        }
        final page = response.dataOrNull;
        if (page != null) {
          owner.replyAnchor = null;
          final first = replacing && !applied;
          final oldCursor = owner.cursor;
          final oldOffset = owner.offset;
          owner
            ..cursor = page.cursor
            ..offset = page.offset;
          if (first) {
            subject = page.subject;
            vote = page.vote;
            root = page.root;
            if (thread == null && subject.title == ReplySortType.select.desc) {
              sort = .select;
            }
          }
          count = page.count;
          final rows = <CommentReply>[
            if (first)
              if (page.top case final top?)
                top.copy()..replyControl.isUpTop = true,
            ...page.rows.map((item) => item.copy()),
          ];
          final unique = <Int64>{...seen};
          rows.removeWhere((item) => !unique.add(item.id));
          final incoming = rows.length;
          final upMid = page.subject.upMid;
          filterRepliesByLevel(
            rows,
            minLevel,
            upMid == Int64.ZERO ? subject?.upMid : upMid,
          );
          final visible = filterRepliesByAuthor(rows, isAuthorBlocked);
          seen.addAll(visible.map((item) => item.id));
          items.addAll(visible);
          hasMore =
              !page.isEnd &&
              (first ||
                  oldCursor != owner.cursor ||
                  oldOffset != owner.offset) &&
              (minLevel > 0 || count < 0 || items.length < count);
          applied = true;
          remaining = remaining > 0
              ? remaining - visible.length
              : incoming - visible.length;
          if (!hasMore || (visible.isNotEmpty && remaining <= 0)) break;
          if (attempt == 4) error = const Error('连续多页无可展示评论，点击继续加载');
        } else {
          error = const Error('评论请求没有返回结果');
          break;
        }
      }
    } catch (cause, stack) {
      error = Error.fromException(cause, stack);
    }
    if (!_current(owner)) return;
    state = CommentsState(
      source: owner,
      loading: replacing && !applied && error != null
          ? error
          : Success(
              List.unmodifiable(filterRepliesByAuthor(items, isAuthorBlocked)),
            ),
      sort: sort,
      count: count,
      subject: subject,
      vote: vote,
      root: _filterRoot(root, isAuthorBlocked),
      hasMore: hasMore,
      pageError: !replacing || applied ? error : null,
    );
  }

  void touch() {
    if (!_current(_owner)) return;
    final items = state.loading.dataOrNull;
    if (items != null) _replace(items, state.count);
  }

  void published(CommentReply? item, {CommentReply? parent}) {
    if (!_current(_owner)) return;
    if ((item != null && isAuthorBlocked(item)) ||
        (parent != null && isAuthorBlocked(parent))) {
      return;
    }
    final current = state.loading.dataOrNull;
    if (item == null || current == null || state.busy) {
      unawaited(refresh(clear: true));
      return;
    }
    final items = [...current];
    if (query.thread case final thread?) {
      if (items.any((row) => row.id == item.id)) return;
      final index = items.indexWhere((row) => row.id == parent?.id);
      if (parent == null || (index < 0 && parent.id.toInt() != thread.root)) {
        unawaited(refresh(clear: true));
        return;
      }
      items.insert(index + 1, item);
    } else if (parent == null) {
      if (items.any((row) => row.id == item.id)) return;
      items.insert(
        items.firstOrNull?.replyControl.isUpTop == true ? 1 : 0,
        item,
      );
    } else {
      final index = items.indexWhere((row) => row.id == parent.id);
      if (index < 0) {
        unawaited(refresh(clear: true));
        return;
      }
      final match = items[index];
      if (match.replies.any((row) => row.id == item.id)) return;
      items[index] = match.copy()
        ..count += Int64.ONE
        ..replies.add(item);
    }
    _replace(items, state.count < 0 ? -1 : state.count + 1);
  }

  void remove(CommentReply item, int? childIndex) {
    if (!_current(_owner)) return;
    final current = state.loading.dataOrNull;
    if (current == null) return;
    final index = current.indexWhere((row) => row.id == item.id);
    if (index < 0) return;
    if (childIndex != null &&
        (!identical(item, current[index]) ||
            childIndex < 0 ||
            childIndex >= item.replies.length)) {
      return;
    }
    if (state.busy) {
      unawaited(refresh());
      return;
    }
    final items = [...current];
    if (childIndex == null) {
      items.removeAt(index);
    } else {
      final updated = item.copy()..replies.removeAt(childIndex);
      if (updated.count > Int64.ZERO) updated.count -= Int64.ONE;
      items[index] = updated;
    }
    _replace(items, state.count > 0 ? state.count - 1 : state.count);
  }

  Future<LoadingState<void>?> togglePinned(
    CommentReply item, {
    CommentTarget? target,
  }) async {
    final owner = _owner;
    if (!_current(owner) ||
        _writingPin ||
        state.loading.dataOrNull?.any((row) => identical(row, item)) != true) {
      return null;
    }
    final isPinned = item.replyControl.isUpTop;
    final generation = _accountGeneration;
    final current = capture();
    _pinOperation = generation;
    try {
      final result = await ref
          .read(commentsRepositoryProvider)
          .togglePinned(owner.account, target ?? query.target, item);
      if (!current()) return null;
      final items = [...?state.loading.dataOrNull];
      final index = items.indexWhere((row) => row.id == item.id);
      if (result.isSuccess && (!_current(owner) || state.busy || index < 0)) {
        unawaited(refresh());
        return result;
      }
      if (result.isSuccess) {
        final updated = items[index].copy()..replyControl.isUpTop = !isPinned;
        items[index] = updated;
        if (!isPinned) {
          for (var i = 0; i < items.length; i++) {
            if (i != index && items[i].replyControl.isUpTop) {
              items[i] = items[i].copy()..replyControl.isUpTop = false;
            }
          }
          if (index != 0) items.insert(0, items.removeAt(index));
        }
        _replace(items, state.count);
      }
      return result;
    } finally {
      if (identical(_pinOperation, generation)) _pinOperation = null;
    }
  }

  void _replace(List<CommentReply> items, int count) {
    final before = state;
    _replaceSnapshot(
      before,
      loading: Success(List.unmodifiable(items)),
      root: before.root,
      count: count,
    );
  }

  void _replaceSnapshot(
    CommentsState before, {
    required LoadingState<List<CommentReply>> loading,
    required CommentReply? root,
    required int count,
  }) {
    state = CommentsState(
      source: before.source,
      loading: loading,
      sort: before.sort,
      count: count,
      subject: before.subject,
      vote: before.vote,
      root: root,
      hasMore: before.hasMore,
      busy: before.busy,
      pageError: before.pageError,
    );
  }
}
