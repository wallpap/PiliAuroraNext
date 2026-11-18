import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/comments/comments_repository.dart';
import 'package:pili_aurora_next/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/reply/reply_sort_type.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/reply_filter.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

typedef CommentTarget = ({int oid, int type});
typedef CommentThread = ({int root, int? reply, int? dialog});
typedef CommentsQuery = ({
  Object owner,
  CommentTarget target,
  CommentThread? thread,
});

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
  final LoadingState<List<ReplyInfo>> loading;
  final ReplySortType sort;
  final SubjectControl? subject;
  final VoteCard? vote;
  final ReplyInfo? root;
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
    _sort = query.thread == null ? Pref.replySortType : Pref.reply2SortType;
    final owner = _owner = _Owner(account)..replyAnchor = query.thread?.reply;
    ref.onDispose(() => owner.disposed = true);
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
      Pref.enableCommAntifraud || sendVisibilityCheck;
  bool get sendVisibilityCheck => Pref.biliSendCommAntifraud;

  Account get accountIdentity => _owner.account;

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
    final mode = _sort == ReplySortType.time
        ? Mode.MAIN_LIST_TIME
        : Mode.MAIN_LIST_HOT;
    final minLevel = Pref.minimumReplyUserLevel;
    final items = <ReplyInfo>[if (!replacing) ...?before.loading.dataOrNull];
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
                mode,
                owner.cursor,
                owner.offset,
              )
            : await repository.thread(
                owner.account,
                query.target,
                thread.root,
                thread.dialog,
                owner.replyAnchor,
                mode,
                owner.offset,
              );
        if (!_current(owner)) return;
        if (response case Error failure) {
          error = failure;
          break;
        }
        final page = switch (response) {
          Success(response: MainListReply data) => (
            cursor: data.cursor,
            offset: data.paginationReply.nextOffset,
            subject: data.subjectControl,
            count: data.subjectControl.hasCount()
                ? data.subjectControl.count.toInt()
                : -1,
            vote: data.hasVoteCard() ? data.voteCard : null,
            top: data.hasUpTop() ? data.upTop : null,
            root: null,
            rows: data.replies,
          ),
          Success(response: DetailListReply data) => (
            cursor: data.cursor,
            offset: data.paginationReply.nextOffset,
            subject: data.subjectControl,
            count: data.root.count.toInt(),
            vote: null,
            top: null,
            root: data.hasRoot() ? data.root : null,
            rows: data.root.replies,
          ),
          Success(response: DialogListReply data) => (
            cursor: data.cursor,
            offset: data.paginationReply.nextOffset,
            subject: data.subjectControl,
            count: -1,
            vote: null,
            top: null,
            root: null,
            rows: data.replies,
          ),
          _ => null,
        };
        if (page != null) {
          owner.replyAnchor = null;
          final first = replacing && !applied;
          final oldCursor = owner.cursor;
          final oldOffset = owner.offset;
          owner
            ..cursor = page.cursor.next
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
          final rows = <ReplyInfo>[
            if (first)
              if (page.top case final top?)
                top.deepCopy()..ensureReplyControl().isUpTop = true,
            ...page.rows.map((item) => item.deepCopy()),
          ];
          final unique = <Int64>{...seen};
          rows.removeWhere((item) => !unique.add(item.id));
          final incoming = rows.length;
          filterRepliesByLevel(rows, minLevel);
          seen.addAll(rows.map((item) => item.id));
          items.addAll(rows);
          hasMore =
              !page.cursor.isEnd &&
              (first ||
                  oldCursor != owner.cursor ||
                  oldOffset != owner.offset) &&
              (minLevel > 0 || count < 0 || items.length < count);
          applied = true;
          remaining = remaining > 0
              ? remaining - rows.length
              : incoming - rows.length;
          if (!hasMore || (rows.isNotEmpty && remaining <= 0)) break;
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
          : Success(List.unmodifiable(items)),
      sort: sort,
      count: count,
      subject: subject,
      vote: vote,
      root: root,
      hasMore: hasMore,
      pageError: !replacing || applied ? error : null,
    );
  }

  void touch() {
    if (!_current(_owner)) return;
    final items = state.loading.dataOrNull;
    if (items != null) _replace(items, state.count);
  }

  void published(ReplyInfo? item, {ReplyInfo? parent}) {
    if (!_current(_owner)) return;
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
      items[index] = match.deepCopy()
        ..count += Int64.ONE
        ..replies.add(item);
    }
    _replace(items, state.count < 0 ? -1 : state.count + 1);
  }

  void remove(ReplyInfo item, int? childIndex) {
    if (!_current(_owner)) return;
    final current = state.loading.dataOrNull;
    if (state.busy) {
      unawaited(refresh());
      return;
    }
    if (current == null) return;
    final items = [...current];
    final index = items.indexWhere((row) => row.id == item.id);
    if (index < 0) return;
    if (childIndex == null) {
      items.removeAt(index);
    } else {
      if (!identical(item, items[index]) ||
          childIndex < 0 ||
          childIndex >= item.replies.length) {
        return;
      }
      final updated = item.deepCopy()..replies.removeAt(childIndex);
      if (updated.count > Int64.ZERO) updated.count -= Int64.ONE;
      items[index] = updated;
    }
    _replace(items, state.count > 0 ? state.count - 1 : state.count);
  }

  Future<LoadingState<void>?> togglePinned(
    ReplyInfo item, {
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
        final updated = items[index].deepCopy()
          ..ensureReplyControl().isUpTop = !isPinned;
        items[index] = updated;
        if (!isPinned) {
          for (var i = 0; i < items.length; i++) {
            if (i != index && items[i].replyControl.isUpTop) {
              items[i] = items[i].deepCopy()
                ..ensureReplyControl().isUpTop = false;
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

  void _replace(List<ReplyInfo> items, int count) {
    final before = state;
    state = CommentsState(
      source: before.source,
      loading: Success(List.unmodifiable(items)),
      sort: before.sort,
      count: count,
      subject: before.subject,
      vote: before.vote,
      root: before.root,
      hasMore: before.hasMore,
      busy: before.busy,
      pageError: before.pageError,
    );
  }
}
