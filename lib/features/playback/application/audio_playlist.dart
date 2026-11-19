import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/playback/data/audio_playlist_repository.dart';
import 'package:pili_aurora_next/generated/bilibili/app/listener/v1.pb.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef AudioPlaylistSnapshot = ({
  List<DetailItem>? items,
  int? index,
  ListOrder order,
  LoadingState<void> status,
  LoadingState<void> pageStatus,
  bool hasPrevious,
  bool hasNext,
});

class AudioPlaylist {
  AudioPlaylist({
    required this._anchor,
    required this._onAnchorLoaded,
    List<DetailItem>? initialItems,
  }) : _items = initialItems == null ? null : List.unmodifiable(initialItems) {
    _knownItems.addAll(_items?.map(_key) ?? const []);
  }

  final AudioPlaylistAnchor Function() _anchor;
  final void Function(DetailItem) _onAnchorLoaded;
  late final _state = ValueNotifier(_snapshot);
  ValueListenable<AudioPlaylistSnapshot> get state => _state;

  List<DetailItem>? _items;
  int? _index;
  ListOrder _order = ListOrder.ORDER_NORMAL;
  LoadingState<void> _status = LoadingState.loading();
  LoadingState<void> _pageStatus = const Success(null);
  final _previous = _PageCursor();
  final _next = _PageCursor();
  final _knownItems = <(int, Int64)>{};
  final _removedItems = <(int, Int64)>{};
  _PageCursor? _failedPage;
  Object? _pendingPage;
  int _revision = 0;
  Account? _account;
  bool _closed = false;

  AudioPlaylistSnapshot get _snapshot => (
    items: _items,
    index: _index,
    order: _order,
    status: _status,
    pageStatus: _pageStatus,
    hasPrevious: _previous.cursor != null,
    hasNext: _next.cursor != null,
  );

  void _publish() => _state.value = _snapshot;

  bool _owns(int revision, Account account) =>
      !_closed && revision == _revision && identical(account, Accounts.main);

  void _onAccountChanged() {
    if (!identical(_account, Accounts.main)) reload();
  }

  static (int, Int64) _key(DetailItem entry) =>
      (entry.item.itemType, entry.item.oid);

  Future<bool> reload() async {
    if (_closed) return false;
    if (_account == null) Accounts.mainChanges.addListener(_onAccountChanged);
    final account = Accounts.main;
    if (!identical(account, _account)) {
      _items = null;
      _index = null;
      _previous.cursor = _next.cursor = null;
    }
    _account = account;
    final revision = ++_revision;
    _pendingPage = _failedPage = null;
    _previous.reset();
    _next.reset();
    _removedItems.clear();
    _status = LoadingState.loading();
    _pageStatus = const Success(null);
    final target = _anchor();
    _publish();
    final result = await _fetch(target, account);
    if (!_owns(revision, account)) return false;
    if (result case Success(:final response)) {
      _knownItems
        ..clear()
        ..addAll(_removedItems);
      _items = List.unmodifiable(
        response.items.where((entry) => _knownItems.add(_key(entry))),
      );
      final current = _anchor();
      final selected = _items!.indexWhere(
        (entry) => _key(entry) == (current.itemType, current.oid),
      );
      _index = selected < 0 ? null : selected;
      _previous.cursor = response.previous;
      _next.cursor = response.next;
      if (selected >= 0 &&
          current.oid == target.oid &&
          current.itemType == target.itemType &&
          listEquals(current.subIds, target.subIds)) {
        _onAnchorLoaded(_items![selected]);
      }
      _status = const Success(null);
    } else {
      _status = result as Error;
    }
    _publish();
    return _status.isSuccess;
  }

  Future<bool> changeOrder(ListOrder order) {
    if (_order == order &&
        _status is! Error &&
        identical(_account, Accounts.main)) {
      return Future.value(false);
    }
    _order = order;
    return reload();
  }

  Future<bool> loadPrevious() => _page(_previous, retry: true);
  Future<bool> loadNext() => _page(_next);

  Future<bool> retryPage() => switch (_failedPage) {
    final page? => _page(page, retry: true),
    null => Future.value(false),
  };

  Future<bool> _page(_PageCursor page, {bool retry = false}) async {
    final account = _account;
    final cursor = page.cursor;
    if (_closed ||
        account == null ||
        !identical(account, Accounts.main) ||
        cursor == null ||
        _pendingPage != null ||
        !_status.isSuccess ||
        (_failedPage != null && (!retry || _failedPage != page))) {
      return false;
    }

    final revision = _revision;
    final operation = _pendingPage = Object();
    _pageStatus = LoadingState.loading();
    _publish();
    try {
      final result = await _fetch(_anchor(), account, cursor: cursor);
      if (!_owns(revision, account)) return false;
      if (result case Success(:final response)) {
        final added = response.items
            .where((entry) => _knownItems.add(_key(entry)))
            .toList();
        final before = identical(page, _previous);
        page.advance(
          cursor,
          before ? response.previous : response.next,
          added.length,
        );
        if (added.isNotEmpty) {
          if (before) {
            _items = List.unmodifiable([...added, ..._items!]);
            if (_index case final index?) _index = index + added.length;
          } else {
            _items = List.unmodifiable([..._items!, ...added]);
          }
        }
        _failedPage = null;
        _pageStatus = const Success(null);
      } else {
        _failedPage = page;
        _pageStatus = result as Error;
      }
      _publish();
      return _pageStatus.isSuccess;
    } finally {
      if (identical(_pendingPage, operation)) _pendingPage = null;
    }
  }

  Future<LoadingState<AudioPlaylistPage>> _fetch(
    AudioPlaylistAnchor anchor,
    Account account, {
    String? cursor,
  }) async {
    try {
      return await AudioPlaylistRepository.fetch(
        anchor,
        account,
        _order,
        cursor: cursor,
      );
    } catch (error, stack) {
      logger
          .scoped('audio')
          .w(
            '音频列表加载失败',
            error: error.runtimeType,
            stackTrace: stack,
          );
      return Error('播放列表加载失败，请重试', cause: error, stackTrace: stack);
    }
  }

  int? indexOf(DetailItem item) {
    final index = _items?.indexWhere((entry) => identical(entry, item)) ?? -1;
    return index < 0 ? null : index;
  }

  void select(int index) {
    _index = index;
    _publish();
  }

  void remove(DetailItem item) {
    if (_closed) return;
    final removed = indexOf(item);
    if (removed == null || removed == _index) return;
    final key = _key(item);
    _knownItems.add(key);
    _removedItems.add(key);
    _items = List.unmodifiable([..._items!]..removeAt(removed));
    if (_index case final index? when removed < index) _index = index - 1;
    _publish();
  }

  void dispose() {
    _closed = true;
    if (_account != null) {
      Accounts.mainChanges.removeListener(_onAccountChanged);
    }
    _state.dispose();
  }
}

class _PageCursor {
  String? cursor;
  int _empty = 0;
  final _visited = <String>{};

  void reset() {
    _empty = 0;
    _visited.clear();
  }

  void advance(String consumed, String? next, int added) {
    _visited.add(consumed);
    _empty = added == 0 ? _empty + 1 : 0;
    cursor = _empty >= 5 || _visited.contains(next) ? null : next;
  }
}
