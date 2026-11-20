import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/playback/data/video_media_repository.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/playback/domain/playlist/media_list.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

class VideoPlaylist {
  VideoPlaylist({
    required this.source,
    required this.id,
    required this.type,
    required this._descending,
    this.count,
    this.continueFromAnchor = false,
    this.anchor,
    this.sortField,
    this.ownedFavorite = false,
  }) {
    Accounts.mainChanges.addListener(_accountChanged);
  }

  final SourceType source;
  final Object id;
  final Object type;
  final int? count;
  final bool continueFromAnchor;
  final Object? anchor;
  final Object? sortField;
  final bool ownedFavorite;
  final _account = Accounts.main;
  final _items = ValueNotifier<List<MediaListItemModel>>(const []);
  final _removed = <(int?, int?, String?)>{};
  final _pending = <bool>{};
  final _exhausted = <bool>{};
  bool _closed = false;
  bool _invalidated = false;
  bool _reversing = false;
  bool _descending;
  int _revision = 0;

  ValueListenable<List<MediaListItemModel>> get items => _items;
  bool get descending => _descending;
  bool get canRemove =>
      source == SourceType.watchLater ||
      (source == SourceType.fav && ownedFavorite);
  bool get _isCurrent =>
      !_closed && !_invalidated && identical(_account, Accounts.main);

  void _accountChanged() {
    if (identical(_account, Accounts.main)) return;
    _invalidated = true;
    _items.value = const [];
  }

  static (int?, int?, String?) _key(MediaListItemModel item) =>
      (item.aid, item.type, item.bvid);

  Future<LoadingState<MediaListItemModel?>?> load({
    bool previous = false,
    bool reverse = false,
  }) async {
    if (!_isCurrent || _reversing) return null;
    if (reverse) {
      _reversing = true;
      _revision++;
      _pending.clear();
    } else {
      if ((count != null && items.value.length >= count!) ||
          _exhausted.contains(previous) ||
          !_pending.add(previous)) {
        return null;
      }
    }

    final revision = _revision;
    final loaded = items.value;
    final edge = previous ? loaded.firstOrNull : loaded.lastOrNull;
    try {
      final result = await VideoMediaRepository.playlist(
        account: _account,
        type: type,
        id: id,
        previous: previous,
        anchor: reverse
            ? null
            : edge != null
            ? edge.aid
            : (continueFromAnchor ? anchor : null),
        anchorType: reverse ? null : edge?.type,
        descending: reverse ? !descending : descending,
        sortField: sortField ?? 1,
        includeAnchor: !reverse && loaded.isEmpty && continueFromAnchor,
      );
      if (!_isCurrent || revision != _revision) return null;
      if (result case Error()) return result;
      final response = result.dataOrNull;
      if (response == null) return null;
      final current = items.value;
      final known = {..._removed, if (!reverse) ...current.map(_key)};
      final incoming = [
        for (final item in response.mediaList)
          if (known.add(_key(item))) item,
      ];
      if (incoming.isEmpty) {
        if (!reverse && current.isNotEmpty) _exhausted.add(previous);
        return const Success(null);
      }
      if (reverse) {
        _descending = !_descending;
        _exhausted.clear();
        _items.value = List.unmodifiable(incoming);
        for (final item in incoming) {
          if (item.cid != null) return Success(item);
        }
      } else {
        _items.value = List.unmodifiable(
          previous ? [...incoming, ...current] : [...current, ...incoming],
        );
      }
      return const Success(null);
    } finally {
      if (revision == _revision) {
        if (reverse) {
          _reversing = false;
        } else {
          _pending.remove(previous);
        }
      }
    }
  }

  Future<LoadingState<void>?> remove(MediaListItemModel item) async {
    if (!_isCurrent || !canRemove || !items.value.contains(item)) return null;
    final result = source == SourceType.watchLater
        ? await LaterLibrary.legacy.remove(
            [?item.aid],
            account: _account,
          )
        : await FavoriteLibrary.legacy.video(
            _account,
            '${item.aid}:${item.type}',
            remove: '$id',
          );
    if (!_isCurrent) return null;
    if (result.isSuccess) {
      final key = _key(item);
      _removed.add(key);
      _items.value = List.unmodifiable(
        items.value.where((entry) => _key(entry) != key),
      );
      return const Success(null);
    }
    return items.value.contains(item) ? result : null;
  }

  void recordProgress(int aid) {
    final account = Accounts.heartbeat;
    if (_isCurrent &&
        account.isLogin &&
        !Pref.historyPause &&
        sortField != null) {
      VideoMediaRepository.recordPlaylistProgress(
        account,
        descending: descending,
        aid: aid,
        listId: id,
      );
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    Accounts.mainChanges.removeListener(_accountChanged);
    _items.dispose();
  }
}
