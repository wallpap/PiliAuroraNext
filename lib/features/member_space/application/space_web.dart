import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/archive_order_type_web.dart';
import 'package:pili_aurora_next/features/member_space/domain/archive_sort_type_app.dart';
import 'package:pili_aurora_next/features/member_space/domain/web_ss_type.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/horizontal_video.dart';
import 'package:pili_aurora_next/features/member_space/domain/archives/search_archive/slist.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef SpaceWebQuery = ({
  Object owner,
  Object mid,
  WebSsType? type,
  Object? id,
});

final spaceWebProvider = NotifierProvider.autoDispose
    .family<SpaceWeb, SpaceWebState, SpaceWebQuery>(SpaceWeb.new);

class SpaceWebState {
  const SpaceWebState({
    required this.source,
    required this.loading,
    this.page = 1,
    this.count,
    this.tags,
    this.busy = false,
    this.pageError,
    this.hasMore = false,
  });
  final Object source;
  final LoadingState<List<HorizontalVideoModel>> loading;
  final int page;
  final int? count;
  int? get totalPage => count == null ? null : (count! / 30).ceil();
  final List<ListTag>? tags;
  final bool busy;
  final Error? pageError;
  final bool hasMore;
  bool get canLoadMore => hasMore && !busy && pageError == null;
}

class SpaceWeb extends Notifier<SpaceWebState> {
  SpaceWeb(this.query);
  final SpaceWebQuery query;
  late Account _account;
  Object _source = Object();
  ArchiveOrderTypeWeb order = .pubdate;
  ArchiveSortTypeApp sort = .desc;
  int tid = 0;
  String? specialType;
  int? _totalCount;

  @override
  SpaceWebState build() {
    final account = _account = ref.watch(mainAccountProvider);
    final source = _source = Object();
    _totalCount = null;
    scheduleMicrotask(() {
      if (_owns(source, account)) unawaited(refresh());
    });
    return SpaceWebState(source: source, loading: LoadingState.loading());
  }

  bool _owns(Object source, Account account) =>
      ref.mounted &&
      identical(source, _source) &&
      identical(account, ref.read(mainAccountProvider));

  bool Function() capture() {
    final snapshot = state;
    final account = _account;
    return () =>
        _owns(snapshot.source, account) &&
        identical(state.loading, snapshot.loading);
  }

  Future<void> selectOrder(Object value) async {
    if (state.busy) return;
    if (value is ArchiveOrderTypeWeb) order = value;
    if (value is ArchiveSortTypeApp) sort = value;
    await refresh(clear: true);
  }

  Future<void> selectTag(ListTag tag) async {
    tid = tag.tid ?? 0;
    specialType = tag.specialType;
    await refresh(clear: true);
  }

  Future<void> refresh({bool clear = false}) => _replace(1, clear: clear);

  Future<void> jump(int page) async {
    final total = state.totalPage;
    if (page < 1 || (total != null && page > total)) return;
    await _replace(page, clear: true);
  }

  Future<void> _replace(int page, {required bool clear}) async {
    if (!_owns(_source, _account)) return;
    _source = Object();
    await _load(page, replace: true, clear: clear);
  }

  Future<void> more({bool retry = false}) async {
    if (state.busy || !state.hasMore || (!retry && state.pageError != null)) {
      return;
    }
    await _load(state.page + 1, replace: false);
  }

  Future<void> _load(
    int page, {
    required bool replace,
    bool clear = false,
  }) async {
    final account = _account;
    final source = _source;
    if (!_owns(source, account)) return;
    final before = state;
    state = SpaceWebState(
      source: source,
      loading: clear ? LoadingState.loading() : before.loading,
      page: before.page,
      count: before.count,
      tags: before.tags,
      busy: true,
      hasMore: before.hasMore,
    );
    final repository = ref.read(spaceRepositoryProvider);
    var count = before.count;
    var tags = before.tags;
    List<HorizontalVideoModel>? items;
    Error? error;
    try {
      if (query.type case final type?) {
        final response = await repository.webCollection(
          account,
          query.mid,
          type,
          query.id!,
          page,
          sort,
        );
        if (!_owns(source, account)) return;
        if (response case Success(:final response)) {
          if (replace) count = response.page?.total;
          items = response.archives ?? const [];
        } else if (response case Error failure) {
          error = failure;
        }
      } else {
        final response = await repository.webArchive(
          account,
          query.mid,
          page,
          order,
          tid,
          specialType,
        );
        if (!_owns(source, account)) return;
        if (response case Success(:final response)) {
          if (replace) {
            count = response.page?.count;
            if (tid == 0 && specialType == null) _totalCount = count;
            final incoming = response.list?.tags;
            if (incoming != null && incoming.isNotEmpty) {
              tags = List.unmodifiable([
                ListTag(tid: 0, name: '全部类型', count: _totalCount),
                ...incoming,
              ]);
            }
          }
          items = response.list?.vlist ?? const [];
        } else if (response case Error failure) {
          error = failure;
        }
      }
    } catch (cause, stack) {
      error = Error.fromException(cause, stack);
    }
    if (!_owns(source, account)) return;
    if (items == null) {
      final failure = error ?? const Error('投稿未返回结果，请重试');
      state = SpaceWebState(
        source: source,
        loading: replace ? failure : before.loading,
        page: replace ? page : before.page,
        count: before.count,
        tags: before.tags,
        hasMore: !replace && before.hasMore,
        pageError: replace ? null : failure,
      );
      return;
    }
    final rows = List<HorizontalVideoModel>.unmodifiable([
      if (!replace) ...?before.loading.dataOrNull,
      ...items,
    ]);
    state = SpaceWebState(
      source: source,
      loading: Success(rows),
      page: page,
      count: count,
      tags: tags,
      hasMore:
          items.isNotEmpty &&
          (count == null ||
              (page < (count / 30).ceil() && rows.length < count)),
    );
  }
}
