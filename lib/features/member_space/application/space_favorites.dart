import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_fav/data.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_fav/list.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef SpaceFavoritesQuery = ({Object owner, int mid});

final spaceFavoritesProvider = NotifierProvider.autoDispose
    .family<
      SpaceFavorites,
      LoadingState<FavoriteSections>,
      SpaceFavoritesQuery
    >(SpaceFavorites.new);

typedef FavoriteSections = ({
  FavoriteSection? folders,
  FavoriteSection? subscriptions,
});
typedef FavoriteSection = ({
  String? name,
  int count,
  List<SpaceFavItemModel> items,
  int? nextPage,
});

class SpaceFavorites extends Notifier<LoadingState<FavoriteSections>> {
  SpaceFavorites(this.query);
  final SpaceFavoritesQuery query;
  late Account _account;
  Object _source = Object();
  bool _refreshing = false;
  final _loading = <bool, Object>{};

  @override
  LoadingState<FavoriteSections> build() {
    _account = ref.watch(mainAccountProvider);
    _source = Object();
    _refreshing = false;
    _loading.clear();
    final source = _source;
    final account = _account;
    scheduleMicrotask(() {
      if (_owns(source, account)) unawaited(refresh());
    });
    return LoadingState.loading();
  }

  bool _owns(Object source, Account account) =>
      ref.mounted &&
      identical(source, _source) &&
      identical(account, ref.read(mainAccountProvider));

  Future<void> refresh({bool clear = false}) async {
    if (!_owns(_source, _account)) return;
    final source = _source = Object();
    _refreshing = true;
    final account = _account;
    _loading.clear();
    if (clear) state = LoadingState.loading();
    late final LoadingState<List<SpaceFavData>?> res;
    try {
      res = await ref
          .read(spaceRepositoryProvider)
          .favorites(account, query.mid);
    } catch (error, stack) {
      res = Error.fromException(error, stack);
    }
    if (!_owns(source, account)) return;
    _refreshing = false;
    if (res case Error error) {
      state = error;
    } else if (res case Success(:final response)) {
      if (response == null || response.isEmpty) {
        state = const Success((folders: null, subscriptions: null));
        return;
      }
      if (response.length < 2 ||
          response.take(2).any((row) {
            final list = row.mediaListResponse;
            return list == null ||
                (list.count ?? -1) < 0 ||
                (list.list == null && list.count! > 0);
          })) {
        state = const Error('收藏分区响应不完整，请重试');
        return;
      }
      FavoriteSection section(SpaceFavData data) {
        final list = data.mediaListResponse!;
        final items = List<SpaceFavItemModel>.unmodifiable(
          list.list ?? const [],
        );
        return (
          name: data.name,
          count: list.count!,
          items: items,
          nextPage: list.count! > items.length ? 2 : null,
        );
      }

      state = Success((
        folders: section(response.first),
        subscriptions: section(response[1]),
      ));
    }
  }

  Future<LoadingState<void>?> more({required bool subscribed}) async {
    final sections = state.dataOrNull;
    final section = subscribed ? sections?.subscriptions : sections?.folders;
    final page = section?.nextPage;
    if (_refreshing ||
        section == null ||
        page == null ||
        _loading.containsKey(subscribed)) {
      return null;
    }
    final source = _source;
    final account = _account;
    if (!_owns(source, account)) return null;
    final lock = _loading[subscribed] = Object();
    try {
      final result = await ref
          .read(spaceRepositoryProvider)
          .favoriteFolders(account, query.mid, page, subscribed);
      if (!_owns(source, account)) return null;
      if (result case Success(:final response)) {
        final ids = section.items.map((item) => item.id).toSet();
        final updated = (
          name: section.name,
          count: section.count,
          items: List<SpaceFavItemModel>.unmodifiable([
            ...section.items,
            ...response.items.where((item) => ids.add(item.id)),
          ]),
          nextPage: response.hasMore && response.items.isNotEmpty
              ? page + 1
              : null,
        );
        final current = state.data;
        state = Success(
          subscribed
              ? (folders: current.folders, subscriptions: updated)
              : (folders: updated, subscriptions: current.subscriptions),
        );
      } else if (result case Error error) {
        return error;
      }
      return const Success(null);
    } catch (error, stack) {
      return _owns(source, account) ? Error.fromException(error, stack) : null;
    } finally {
      if (identical(_loading[subscribed], lock)) _loading.remove(subscribed);
    }
  }

  void Function(bool?) deletionAction(bool subscribed, SpaceFavItemModel item) {
    final source = _source;
    final account = _account;
    return (deleted) {
      if (deleted != true || _refreshing || !_owns(source, account)) return;
      final current = state.dataOrNull;
      final section = subscribed ? current?.subscriptions : current?.folders;
      if (current == null || section == null || !section.items.contains(item)) {
        return;
      }
      final updated = (
        name: section.name,
        count: section.count,
        items: List<SpaceFavItemModel>.unmodifiable(
          section.items.where((entry) => !identical(entry, item)),
        ),
        nextPage: section.nextPage,
      );
      state = Success(
        subscribed
            ? (folders: current.folders, subscriptions: updated)
            : (folders: updated, subscriptions: current.subscriptions),
      );
      // 删除后远端偏移已变化，旧页不能接在新列表后面。
      unawaited(refresh());
    };
  }
}
