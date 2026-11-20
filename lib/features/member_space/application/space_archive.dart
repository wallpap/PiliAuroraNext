import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/archive_order_type_app.dart';
import 'package:pili_aurora_next/features/member_space/domain/archive_sort_type_app.dart';
import 'package:pili_aurora_next/features/member_space/domain/contribute_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/data.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/episodic_button.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/item.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

import 'package:pili_aurora_next/features/member_space/application/space_archive_playback.dart';

typedef SpaceArchiveQuery = ({
  Object owner,
  int mid,
  ContributeType type,
  int? season,
  int? series,
});

final spaceArchiveProvider = NotifierProvider.autoDispose
    .family<SpaceArchive, SpaceArchiveState, SpaceArchiveQuery>(
      SpaceArchive.new,
    );

typedef AnchoredSpaceArchiveQuery = ({Object owner, int mid, String aid});

final anchoredSpaceArchiveProvider = NotifierProvider.autoDispose
    .family<SpaceArchive, SpaceArchiveState, AnchoredSpaceArchiveQuery>(
      (query) => SpaceArchive(
        (
          owner: query.owner,
          mid: query.mid,
          type: .video,
          season: null,
          series: null,
        ),
        initialAnchor: query.aid,
      ),
    );

class SpaceArchiveState {
  const SpaceArchiveState({
    required this.source,
    required this.loading,
    required this.order,
    required this.sort,
    this.count,
    this.button,
    this.hasPrevious = false,
    this.hasNext = false,
    this.busy = false,
    this.pageError,
  });
  final Object source;
  final LoadingState<List<SpaceArchiveItem>> loading;
  final ArchiveOrderTypeApp order;
  final ArchiveSortTypeApp sort;
  final int? count;
  final EpisodicButton? button;
  final bool hasPrevious;
  final bool hasNext;
  final bool busy;
  final Error? pageError;
  bool get canLoadMore => !busy && hasNext && pageError == null;
}

class SpaceArchive extends Notifier<SpaceArchiveState> {
  SpaceArchive(this.query, {this.initialAnchor});
  final SpaceArchiveQuery query;
  final String? initialAnchor;
  late Account _account;
  Object _source = Object();
  Object? _opening;
  int _page = 0;
  int? _cursor;
  ArchiveOrderTypeApp _order = .pubdate;
  ArchiveSortTypeApp _sort = .desc;
  bool get _video => query.type == .video;

  @override
  SpaceArchiveState build() {
    final account = _account = ref.watch(mainAccountProvider);
    final source = _source = Object();
    scheduleMicrotask(() {
      if (_owns(source, account)) unawaited(refresh());
    });
    return _snapshot(LoadingState.loading());
  }

  bool _owns(Object source, Account account) =>
      ref.mounted &&
      identical(_source, source) &&
      identical(account, ref.read(mainAccountProvider));

  SpaceArchiveState _snapshot(
    LoadingState<List<SpaceArchiveItem>> loading, {
    int? count,
    EpisodicButton? button,
    bool hasPrevious = false,
    bool hasNext = false,
    bool busy = false,
    Error? pageError,
  }) => SpaceArchiveState(
    source: _source,
    loading: loading,
    order: _order,
    sort: _sort,
    count: count,
    button: button,
    hasPrevious: hasPrevious,
    hasNext: hasNext,
    busy: busy,
    pageError: pageError,
  );

  Future<void> refresh({bool clear = false, String? anchor}) async {
    if (!_owns(_source, _account)) return;
    _source = Object();
    _page = 0;
    _cursor = null;
    await _load(
      replacing: true,
      clear: clear,
      anchor: anchor ?? initialAnchor,
    );
  }

  Future<void> toggleSort() async {
    if (state.busy) return;
    if (_video) {
      _order = _order == .pubdate ? .click : .pubdate;
    } else {
      _sort = _sort == .desc ? .asc : .desc;
    }
    await refresh(clear: true);
  }

  Future<void> more({bool retry = false}) async {
    if (state.busy || !state.hasNext || (!retry && state.pageError != null)) {
      return;
    }
    await _load(replacing: false);
  }

  Future<LoadingState<int>> previous() async {
    if (state.busy || !state.hasPrevious) return const Success(0);
    return _load(replacing: false, previous: true);
  }

  Future<LoadingState<int>> _load({
    required bool replacing,
    bool previous = false,
    bool clear = false,
    String? anchor,
  }) async {
    final source = _source;
    final account = _account;
    if (!_owns(source, account)) return const Success(0);
    final before = state;
    final rows = before.loading.dataOrNull ?? const [];
    state = _snapshot(
      clear ? LoadingState.loading() : before.loading,
      count: before.count,
      button: before.button,
      hasPrevious: before.hasPrevious,
      hasNext: before.hasNext,
      busy: true,
    );
    late final LoadingState<SpaceArchiveData> response;
    try {
      response = await ref
          .read(spaceRepositoryProvider)
          .archives(
            account,
            query.mid,
            query.type,
            anchor: _video
                ? anchor ??
                      (replacing
                          ? null
                          : previous
                          ? rows.firstOrNull?.param
                          : rows.lastOrNull?.param)
                : null,
            order: _video ? _order : null,
            sort: _video ? (previous ? .asc : null) : _sort,
            page: query.type == .charging ? _page : null,
            cursor: initialAnchor == null ? _cursor : null,
            season: query.season,
            series: query.series,
            includeCursor: anchor != null
                ? true
                : initialAnchor == null
                ? false
                : null,
          );
    } catch (error, stack) {
      response = Error.fromException(error, stack);
    }
    if (!_owns(source, account)) return const Success(0);
    if (response case Success(:final response)) {
      final incoming = List<SpaceArchiveItem>.of(
        response.item ?? const <SpaceArchiveItem>[],
      );
      if (!previous) {
        _cursor = response.next;
        _page++;
      }
      final seen = <String>{
        if (!replacing)
          for (final row in rows) ?row.param,
      };
      incoming.removeWhere((row) => row.param != null && !seen.add(row.param!));
      final result = List<SpaceArchiveItem>.unmodifiable([
        if (!replacing && !previous) ...rows,
        ...incoming,
        if (previous) ...rows,
      ]);
      state = _snapshot(
        Success(result),
        count: query.type == .season
            ? result.length
            : response.count ?? before.count,
        button: response.episodicButton ?? (replacing ? null : before.button),
        hasPrevious: previous || replacing
            ? response.hasPrev == true
            : before.hasPrevious,
        hasNext: previous
            ? before.hasNext
            : query.type != .season &&
                  incoming.isNotEmpty &&
                  (_video
                      ? response.hasNext ??
                            (initialAnchor == null ||
                                (!replacing && before.hasNext))
                      : response.next != 0),
        pageError: previous ? before.pageError : null,
      );
      return Success(incoming.length);
    }
    final error = response is Error ? response : const Error('投稿未返回结果，请重试');
    state = replacing
        ? _snapshot(error)
        : _snapshot(
            before.loading,
            count: before.count,
            button: before.button,
            hasPrevious: before.hasPrevious,
            hasNext: before.hasNext,
            pageError: previous ? before.pageError : error,
          );
    return error;
  }

  Future<LoadingState<ArchivePlayback?>?> playback({
    String? username,
    String? title,
  }) async {
    final current = state;
    final operation = current.source;
    final account = _account;
    if (!_owns(operation, account) ||
        current.busy ||
        current.button == null ||
        identical(_opening, operation)) {
      return null;
    }
    _opening = operation;
    try {
      final result = await resolveArchivePlayback(
        ref.read(spaceRepositoryProvider),
        account,
        query,
        current,
        username,
        title,
      );
      return _owns(operation, account) && identical(current, state)
          ? result
          : null;
    } finally {
      if (identical(_opening, operation)) _opening = null;
    }
  }
}
