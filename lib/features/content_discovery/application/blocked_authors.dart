import 'dart:async';

import 'package:pili_aurora_next/features/content_discovery/data/author_filter_preferences.dart';
import 'package:pili_aurora_next/features/content_discovery/data/blocked_author_repository.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class BlockedAuthors {
  BlockedAuthors._(this._account, this._revision, this._mids);

  static const _repository = BlockedAuthorRepository();
  static BlockedAuthors? _session;
  final Account _account;
  final int _revision;
  Set<int> _mids;
  Future<void>? _pending;
  DateTime? _checkedAt;
  final _changes = <int, bool>{};

  static BlockedAuthors get _current {
    final account = Accounts.main;
    final revision = Accounts.mainChanges.value;
    return switch (_session) {
      final session? when session._isCurrent => session,
      _ => _session = BlockedAuthors._(
        account,
        revision,
        _repository.read(account.mid),
      ),
    };
  }

  bool get _isCurrent =>
      identical(_session, this) &&
      identical(_account, Accounts.main) &&
      _revision == Accounts.mainChanges.value;

  static bool get hasBlockedAuthors => _current._mids.isNotEmpty;

  static bool contains(int? mid) =>
      mid != null && mid > 0 && _current._mids.contains(mid);

  static void setBlocked(int mid, bool blocked) {
    final session = _current;
    if (session._pending != null) session._changes[mid] = blocked;
    if (blocked) {
      session._mids.add(mid);
    } else {
      session._mids.remove(mid);
    }
    unawaited(session._persist());
  }

  static Future<void>? ensureLoaded() {
    if (!AuthorFilterPreferences.filterBlockedAuthors ||
        !Accounts.main.isLogin) {
      return null;
    }
    return _current._ensureLoaded();
  }

  Future<void>? _ensureLoaded() {
    if (_pending case final pending?) return pending;
    final now = DateTime.now();
    if (_checkedAt case final checkedAt?
        when now.difference(checkedAt) < const Duration(minutes: 5)) {
      return null;
    }
    _checkedAt = now;
    return _pending = _load().whenComplete(() {
      _pending = null;
      _changes.clear();
    });
  }

  Future<void> _load() async {
    final mids = <int>{};
    try {
      for (var page = 1; ; page++) {
        final response = (await _repository.load(_account, page)).dataOrNull;
        if (!_isCurrent || response == null) return;
        final (:items, :total) = response;
        final previousLength = mids.length;
        mids.addAll(
          items
              .map((item) => item.mid)
              .whereType<int>()
              .where(
                (mid) => mid > 0,
              ),
        );
        if (total != null && mids.length >= total) break;
        if (items.isEmpty || mids.length == previousLength) return;
        if (total == null && items.length < blockedAuthorPageSize) break;
      }
      for (final entry in _changes.entries) {
        if (entry.value) {
          mids.add(entry.key);
        } else {
          mids.remove(entry.key);
        }
      }
      _mids = mids;
      unawaited(_persist());
    } catch (error, stack) {
      logger.w('读取作者黑名单失败', error: error.runtimeType, stackTrace: stack);
    }
  }

  Future<void> _persist() async {
    try {
      await _repository.save(_account.mid, _mids);
    } catch (error, stack) {
      logger.w('保存作者黑名单失败', error: error.runtimeType, stackTrace: stack);
    }
  }
}
