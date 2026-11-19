import 'package:flutter/foundation.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/pgc.dart';
import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/remote/pgc/season_follow_status.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef CollectionState<T> = ({LoadingState<T> result, bool busy});

enum SeasonFollowChange { add, remove, changeGroup }

class SeasonCollection {
  SeasonCollection({
    required this.trackedSeason,
    required this.course,
    required this.initialBookmark,
  });

  final int? Function() trackedSeason;
  final ({int? season, int? episode}) Function() course;
  final bool? Function() initialBookmark;
  final _tracking = _CollectionSlot<SeasonFollowStatus>(LoadingState.loading());
  _CollectionSlot<bool>? _courseSlot;
  _CollectionSlot<bool> get _bookmark =>
      _courseSlot ??= _CollectionSlot<bool>(switch (initialBookmark()) {
        final value? => Success(value),
        _ => const Error('收藏状态未加载，请重试'),
      });

  ValueListenable<CollectionState<SeasonFollowStatus>> get tracking =>
      _tracking.state;
  ValueListenable<CollectionState<bool>> get bookmark => _bookmark.state;

  VoidCallback? _accountListener;
  bool _closed = false;

  void observeAccount({required bool pgc}) {
    if (_accountListener != null || _closed) return;
    var owner = Accounts.main;
    void changed() {
      final next = Accounts.main;
      if (identical(owner, next)) return;
      owner = next;
      if (pgc) {
        _tracking.reset();
        refreshTracking();
      } else {
        _bookmark.reset();
        refreshBookmark();
      }
    }

    _accountListener = changed;
    Accounts.mainChanges.addListener(changed);
  }

  void dispose() {
    _closed = true;
    if (_accountListener case final listener?) {
      Accounts.mainChanges.removeListener(listener);
    }
    _tracking.dispose();
    _courseSlot?.dispose();
  }

  bool Function() captureTracking() {
    final season = trackedSeason();
    final account = Accounts.main;
    return () => _owns(account) && trackedSeason() == season;
  }

  bool _owns(Account account) => !_closed && identical(account, Accounts.main);

  Future<void> refreshTracking() async {
    if (_closed || _tracking.state.value.busy) return;
    final current = captureTracking();
    final account = Accounts.main;
    await _tracking.refresh(
      current,
      () => account.isLogin
          ? PgcHttp.seasonStatus(trackedSeason(), account: account)
          : Future.value(const Success(SeasonFollowStatus(followed: false))),
    );
  }

  Future<LoadingState<String>?> changeTracking(
    SeasonFollowChange change, {
    int? group,
  }) async {
    if (_closed || _tracking.state.value.busy) return null;
    final account = Accounts.main;
    if (!account.isLogin) return const Error('账号未登录');
    if (change == .changeGroup && group == null) return const Error('追番分组无效');
    final season = trackedSeason();
    final current = captureTracking();
    final wasLoading = _tracking.state.value.result is Loading;
    return _tracking.write(current, () async {
      final result = await FavoriteLibrary.legacy.write(
        account,
        () => switch (change) {
          .add => VideoHttp.pgcAdd(seasonId: season, account: account),
          .remove => VideoHttp.pgcDel(seasonId: season, account: account),
          .changeGroup => VideoHttp.pgcUpdate(
            seasonId: '$season',
            status: group!,
            account: account,
          ),
        },
      );
      final removed = change == .remove;
      final LoadingState<SeasonFollowStatus>? next = result.isSuccess
          ? Success(
              SeasonFollowStatus(
                followed: !removed,
                status: removed ? null : group ?? 2,
              ),
            )
          : wasLoading
          ? result as Error
          : null;
      return (result, next);
    });
  }

  Future<void> refreshBookmark() async {
    if (_closed || _bookmark.state.value.busy) return;
    final account = Accounts.main;
    final target = course();
    await _bookmark.refresh(
      () => _owns(account) && course() == target,
      () async {
        if (!account.isLogin) return const Success(false);
        final result = await SearchHttp.pugvInfo(
          account: account,
          seasonId: target.season,
          epId: target.episode,
        );
        return switch (result) {
          Success(:final response) when response.userStatus?.favored != null =>
            Success(response.userStatus!.favored == 1),
          Error() => result,
          _ => const Error('收藏状态未加载，请重试'),
        };
      },
    );
  }

  Future<LoadingState<String>?> toggleBookmark() async {
    if (_closed || _bookmark.state.value.busy) return null;
    final account = Accounts.main;
    final season = course().season;
    if (season == null || season <= 0) return null;
    if (!account.isLogin) return const Error('账号未登录');
    final before = _bookmark.state.value.result.dataOrNull;
    if (before == null) {
      await refreshBookmark();
      return null;
    }
    return _bookmark.write(
      () => _owns(account) && course().season == season,
      () async {
        final result = await FavoriteLibrary.legacy.cheese(
          account,
          season,
          !before,
        );
        if (result.isSuccess) {
          return (Success('${before ? '取消' : ''}收藏成功'), Success(!before));
        }
        return (result as Error, result is UnknownResult ? result : null);
      },
    );
  }
}

class _CollectionSlot<T> {
  _CollectionSlot(LoadingState<T> initial)
    : state = ValueNotifier((result: initial, busy: false));

  final ValueNotifier<CollectionState<T>> state;
  int _revision = 0;

  void reset() {
    _revision++;
    state.value = (result: LoadingState.loading(), busy: false);
  }

  Future<void> refresh(
    bool Function() owns,
    Future<LoadingState<T>> Function() read,
  ) async {
    reset();
    final revision = _revision;
    final result = await read();
    if (owns() && revision == _revision) {
      state.value = (result: result, busy: false);
    }
  }

  Future<LoadingState<String>?> write(
    bool Function() owns,
    Future<(LoadingState<String>, LoadingState<T>?)> Function() perform,
  ) async {
    final revision = ++_revision;
    state.value = (result: state.value.result, busy: true);
    try {
      final (receipt, next) = await perform();
      if (!owns() || revision != _revision) return null;
      if (next != null) state.value = (result: next, busy: true);
      return receipt;
    } finally {
      if (revision == _revision) {
        state.value = (result: state.value.result, busy: false);
      }
    }
  }

  void dispose() {
    _revision++;
    state.dispose();
  }
}
