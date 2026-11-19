import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/emote_repository.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final emotePackagePreviewProvider = FutureProvider.autoDispose
    .family<Package, int?>((ref, id) async {
      final account = ref.watch(mainAccountProvider);
      if (id == null) throw const Error('表情包信息缺失');
      return (await ref
              .read(emoteRepositoryProvider)
              .packageDetail(account, id))
          .data;
    }, retry: (_, _) => null);

final emoteManagementProvider = NotifierProvider.autoDispose
    .family<EmoteManagement, EmoteManagementState, Object>(EmoteManagement.new);

class EmoteManagementState {
  EmoteManagementState({
    required this.category,
    LoadingState<List<Package>>? panel,
    this.categories = const {},
    this.busyIds = const {},
    this.removed = const {},
  }) : panel = panel ?? LoadingState.loading();

  final int category;
  final LoadingState<List<Package>> panel;
  final Map<int, LoadingState<List<Package>>> categories;
  final Set<int> busyIds;
  final Map<int, Package> removed;

  LoadingState<List<Package>>? get selected => categories[category];

  static bool _visible(Package package) =>
      (package.id ?? 0) > 0 && package.text != '收藏';

  List<Package> get added =>
      panel.dataOrNull?.where(_visible).toList(growable: false) ?? const [];

  List<Package> get available {
    final packages = selected?.dataOrNull;
    if (packages == null) return const [];
    final ids = <int?>{
      for (final package in panel.dataOrNull ?? []) package.id,
    };
    return [
      for (final package in packages)
        if (_visible(package) && ids.add(package.id)) package,
      if (category == 0)
        for (final package in removed.values)
          if (_visible(package) && ids.add(package.id)) package,
    ];
  }

  EmoteManagementState _with({
    int? category,
    LoadingState<List<Package>>? panel,
    Map<int, LoadingState<List<Package>>>? categories,
    Set<int>? busyIds,
    Map<int, Package>? removed,
  }) => EmoteManagementState(
    category: category ?? this.category,
    panel: panel ?? this.panel,
    categories: categories == null
        ? this.categories
        : Map.unmodifiable(categories),
    busyIds: busyIds == null ? this.busyIds : Set.unmodifiable(busyIds),
    removed: removed == null ? this.removed : Map.unmodifiable(removed),
  );
}

class _EmoteManagementOwner {
  _EmoteManagementOwner(this.account);

  final Account account;
  bool disposed = false;
}

class EmoteManagement extends Notifier<EmoteManagementState> {
  EmoteManagement(Object _);

  late _EmoteManagementOwner _owner;
  int _category = 0;

  @override
  EmoteManagementState build() {
    final owner = _owner = _EmoteManagementOwner(
      ref.watch(mainAccountProvider),
    );
    ref.onDispose(() => _owner.disposed = true);
    scheduleMicrotask(() => unawaited(_load(owner)));
    return EmoteManagementState(category: _category);
  }

  bool _current(_EmoteManagementOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(owner, _owner) &&
      identical(owner.account, ref.read(mainAccountProvider));

  Future<void> refresh() {
    if (state.busyIds.isNotEmpty) return Future.value();
    final owner = _owner = _EmoteManagementOwner(ref.read(mainAccountProvider));
    state = EmoteManagementState(category: _category);
    return _load(owner);
  }

  Future<void> _load(_EmoteManagementOwner owner) async {
    if (!_current(owner)) return;
    final result = await ref
        .read(emoteRepositoryProvider)
        .settingPanel(owner.account);
    if (!_current(owner)) return;
    state = state._with(
      panel: switch (result) {
        Success(:final response) => Success(
          List.unmodifiable(response.userPanelPackages),
        ),
        Error error => error,
        Loading() => LoadingState.loading(),
      },
    );
    if (result.isSuccess) await selectCategory(_category);
  }

  Future<void> selectCategory(int category) async {
    final owner = _owner;
    if (!_current(owner) || !state.panel.isSuccess) return;
    _category = category;
    final previous = state.categories[category];
    if (previous is Success || previous is Loading) {
      if (state.category != category) state = state._with(category: category);
      return;
    }
    state = state._with(
      category: category,
      categories: {...state.categories, category: LoadingState.loading()},
    );
    final result = await ref
        .read(emoteRepositoryProvider)
        .categoryPackages(
          owner.account,
          category,
          isCurrent: () => _current(owner),
        );
    if (!_current(owner)) return;
    state = state._with(categories: {...state.categories, category: result});
  }

  Future<LoadingState<void>?> changePackage(
    Package package, {
    required bool add,
  }) async {
    final owner = _owner;
    final id = package.id;
    final panel = state.panel.dataOrNull;
    if (!_current(owner) ||
        id == null ||
        panel == null ||
        state.busyIds.contains(id) ||
        panel.any((item) => item.id == id) == add) {
      return null;
    }
    state = state._with(busyIds: {...state.busyIds, id});
    try {
      final result = await ref
          .read(emoteRepositoryProvider)
          .changePackage(owner.account, id, add: add);
      if (!_current(owner)) return null;
      if (result.isSuccess) {
        final current = state.panel.data;
        final removed = {...state.removed};
        if (add) {
          removed.remove(id);
        } else {
          removed[id] = package;
        }
        state = state._with(
          panel: Success(
            List.unmodifiable([
              for (final item in current)
                if (item.id != id) item,
              if (add) package,
            ]),
          ),
          removed: removed,
        );
      }
      return result;
    } finally {
      if (_current(owner)) {
        state = state._with(busyIds: {...state.busyIds}..remove(id));
      }
    }
  }
}
