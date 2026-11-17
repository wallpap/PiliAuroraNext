import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/topic_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/top_details.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

/// 页面离开后仍持有已发出的写入锁，重新打开不能重复发送同一操作。
class TopicWrites {
  final _pending = HashMap<Account, Set<(String, bool)>>.identity();
  final _changes = StreamController<({Account account, String id})>.broadcast(
    sync: true,
  );
  Stream<({Account account, String id})> get changes => _changes.stream;
  Future<void> close() => _changes.close();
  Future<LoadingState<void>> run(
    Account account,
    String id,
    bool favorite,
    Future<LoadingState<void>> Function() send,
  ) async {
    final keys = _pending.putIfAbsent(account, () => {});
    final key = (id, favorite);
    if (!keys.add(key)) return const Error('操作进行中');
    try {
      final result = await send();
      if (result.isSuccess && !favorite && !_changes.isClosed) {
        _changes.add((account: account, id: id));
      }
      return result;
    } catch (cause, stack) {
      return UnknownResult(cause: cause, stackTrace: stack);
    } finally {
      keys.remove(key);
      if (keys.isEmpty) _pending.remove(account);
    }
  }
}

final topicWritesProvider = Provider((ref) {
  final writes = TopicWrites();
  ref.onDispose(() => unawaited(writes.close()));
  return writes;
});

class TopicHeaderState {
  const TopicHeaderState(
    this.loading, {
    this.refreshing = false,
    this.error,
    this.savingFav = false,
    this.savingLike = false,
  });
  final LoadingState<TopDetails?> loading;
  final bool refreshing, savingFav, savingLike;
  final Error? error;
}

final topicHeaderProvider = NotifierProvider.autoDispose
    .family<TopicHeader, TopicHeaderState, String>(TopicHeader.new);

class TopicHeader extends Notifier<TopicHeaderState> {
  TopicHeader(this.id);
  final String id;
  int _version = 0;
  Object? _favorite, _like;
  @override
  TopicHeaderState build() {
    final account = ref.watch(mainAccountProvider);
    final version = ++_version;
    _favorite = _like = null;
    final sub = ref.read(favoriteLibraryProvider).changes.listen((changed) {
      if (ref.mounted && identical(account, changed) && _favorite == null) {
        unawaited(refresh());
      }
    });
    final likes = ref.read(topicWritesProvider).changes.listen((changed) {
      if (ref.mounted &&
          identical(account, changed.account) &&
          changed.id == id &&
          _like == null) {
        unawaited(refresh());
      }
    });
    ref.onDispose(() {
      _version++;
      unawaited(sub.cancel());
      unawaited(likes.cancel());
    });
    scheduleMicrotask(() {
      if (_owns(account, version)) unawaited(refresh());
    });
    return TopicHeaderState(LoadingState.loading());
  }

  bool _owns(Account account, int version) =>
      ref.mounted &&
      version == _version &&
      identical(account, ref.read(mainAccountProvider));
  void _publish(
    LoadingState<TopDetails?> loading, {
    bool refreshing = false,
    Error? error,
  }) {
    state = TopicHeaderState(
      loading,
      refreshing: refreshing,
      error: error,
      savingFav: _favorite != null,
      savingLike: _like != null,
    );
  }

  Future<void> refresh() async {
    final account = ref.read(mainAccountProvider);
    final version = ++_version;
    _publish(state.loading, refreshing: true);
    LoadingState<TopDetails?> result;
    try {
      result = await ref.read(topicRepositoryProvider).top(account, id);
    } catch (cause, stack) {
      result = Error.fromException(cause, stack);
    }
    if (!_owns(account, version)) return;
    _publish(
      result is Error && state.loading is Success ? state.loading : result,
      error: result is Error ? result : null,
    );
  }

  Future<LoadingState<void>> toggle({required bool favorite}) async {
    final account = ref.read(mainAccountProvider);
    if (!account.isLogin) return const Error('账号未登录');
    final details = state.loading.dataOrNull;
    final item = details?.topicItem;
    if (item == null) return const Error('请先刷新话题信息');
    if ((favorite ? _favorite : _like) != null) return const Error('操作进行中');
    final operation = Object();
    if (favorite) {
      _favorite = operation;
    } else {
      _like = operation;
    }
    final version = ++_version;
    _publish(state.loading);
    final repository = ref.read(topicRepositoryProvider);
    final library = ref.read(favoriteLibraryProvider);
    final wasSet = (favorite ? item.isFav : item.isLike) ?? false;
    final result = await ref
        .read(topicWritesProvider)
        .run(
          account,
          id,
          favorite,
          () => favorite
              ? library.write(
                  account,
                  () => repository.favorite(account, id, wasSet),
                )
              : repository.like(account, id, wasSet),
        );
    if (!ref.mounted || !identical(account, ref.read(mainAccountProvider))) {
      return result;
    }
    if (favorite && identical(_favorite, operation)) _favorite = null;
    if (!favorite && identical(_like, operation)) _like = null;
    if (result.isSuccess) {
      final latest = state.loading.dataOrNull;
      if (identical(details, latest) && version == _version) {
        // 发布新的头部快照，旧详情与其他查询持有的模型不被写入修改。
        final count = wasSet ? -1 : 1;
        final updated = TopicItem(
          id: item.id,
          name: item.name,
          view: item.view,
          discuss: item.discuss,
          description: item.description,
          fav: favorite ? (item.fav + count).clamp(0, 1 << 53) : item.fav,
          like: favorite ? item.like : (item.like + count).clamp(0, 1 << 53),
          isFav: favorite ? !wasSet : item.isFav,
          isLike: favorite ? item.isLike : !wasSet,
        );
        _publish(
          Success(
            TopDetails(topicItem: updated, topicCreator: details!.topicCreator),
          ),
        );
      } else {
        // 刷新或另一种写入已改变快照时重新核对，已确认成功仍按成功交付。
        unawaited(refresh());
      }
    } else {
      _publish(state.loading, refreshing: state.refreshing, error: state.error);
    }
    return result;
  }
}
