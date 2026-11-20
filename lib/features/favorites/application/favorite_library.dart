import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_library/application/library_module.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/favorites/data/favorite_repository.dart';
import 'package:pili_aurora_next/features/favorites/domain/favorite_items.dart';
import 'package:pili_aurora_next/features/favorites/domain/favorite_query.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

export 'package:pili_aurora_next/features/favorites/domain/favorite_items.dart';
export 'package:pili_aurora_next/features/favorites/domain/favorite_query.dart';

typedef FavoriteState = FeedState<Object, FavoriteMetadata>;
typedef FavoriteTarget = (Object, int);

class FavoriteMembership {
  FavoriteMembership(
    this.account,
    this.target,
    Iterable<FavFolderInfo> folders,
    this.revision,
  ) : folders = List.unmodifiable(folders);
  final Account account;
  final FavoriteTarget target;
  final List<FavFolderInfo> folders;
  final int revision;
  Set<int> get selected => {
    for (final folder in folders)
      if (folder.favState == 1) folder.id,
  };
}

/// 成功写入的失效、账号锁和跨入口一致性集中于此，不向调用者暴露可变列表。
class FavoriteLibrary extends LibraryModule {
  FavoriteLibrary(this._repository) {
    _revisionSubscription = changes.listen((_) => _revision++);
  }
  final FavoriteRepository _repository;
  late final StreamSubscription<Account> _revisionSubscription;
  int _revision = 0;
  int get revision => _revision;
  static FavoriteLibrary? _applicationLibrary;
  static FavoriteLibrary get legacy =>
      _applicationLibrary ??= FavoriteLibrary(FavoriteRepository());
  static Future<void> closeApplication() =>
      _applicationLibrary?.close() ?? Future.value();

  @override
  bool owns(Account account) => !isClosed && identical(account, Accounts.main);
  Future<List<FavFolderInfo>> destinations(Account account) {
    if (!owns(account) || !account.isLogin) {
      return Future.error(const Error('账号已切换或未登录'));
    }
    return _repository.folders(account);
  }

  int? get quickFolder => _repository.quickFolder;
  bool get quickEnabled => _repository.quickEnabled;

  Future<void> setQuickFolder(Account account, int? id) async {
    if (!owns(account) || !account.isLogin) throw const Error('账号已切换或未登录');
    await _repository.setQuickFolder(id);
  }

  Future<FavFolderInfo> folder(Account account, int id) async {
    if (!owns(account) || id <= 0) throw const Error('账号或收藏夹已更新');
    return (await _repository.folder(account, id)).data;
  }

  Future<FavoriteMembership> membership(
    Account account,
    FavoriteTarget target,
  ) async {
    if (!owns(account) || !account.isLogin) throw const Error('账号已切换或未登录');
    final version = revision;
    final data = (await _repository.membership(account, target)).data;
    if (!owns(account) || version != revision) throw const Error('收藏夹已更新，请重试');
    return FavoriteMembership(account, target, data.list ?? [], version);
  }

  bool ownsMembership(FavoriteMembership source) =>
      owns(source.account) && source.revision == revision;
  Future<LoadingState<bool>> select(
    FavoriteMembership source,
    Set<int> selected,
  ) {
    final ids = Set<int>.of(selected);
    if (!ownsMembership(source) ||
        ids.any(
          (id) => id <= 0 || !source.folders.any((item) => item.id == id),
        )) {
      return Future.value(const Error('收藏夹已更新，请重新打开'));
    }
    final previous = source.selected;
    final add = ids.difference(previous), remove = previous.difference(ids);
    if (add.isEmpty && remove.isEmpty) {
      return Future.value(Success(ids.isNotEmpty));
    }
    return write(source.account, () async {
      final result = await _repository.video(
        source.account,
        '${source.target.$1}:${source.target.$2}',
        add: add.join(','),
        remove: remove.join(','),
      );
      return result.isSuccess
          ? Success(ids.isNotEmpty)
          : result as LoadingState<bool>;
    });
  }

  Future<LoadingState<bool>> quick(
    Account account,
    FavoriteTarget target, {
    required bool Function() isCurrent,
  }) => write(account, () async {
    FavoriteMembership source;
    try {
      source = await membership(account, target);
    } catch (error, stack) {
      return error is Error ? error : Error.fromException(error, stack);
    }
    if (!isCurrent() || !ownsMembership(source)) return const Error('视频或账号已更新');
    final removing = source.selected.isNotEmpty;
    final preferred = _repository.quickFolder;
    final folder =
        source.folders.where((item) => item.id == preferred).firstOrNull ??
        source.folders.firstOrNull;
    if (!removing && folder == null) return const Error('暂无可用收藏夹，请先创建');
    final result = removing
        ? await _repository.unfavorite(account, target)
        : await _repository.video(
            account,
            '${target.$1}:${target.$2}',
            add: '${folder!.id}',
          );
    return result.isSuccess ? Success(!removing) : result as LoadingState<bool>;
  });
  Future<LoadingState<void>> video(
    Account account,
    String resources, {
    String? add,
    String? remove,
  }) => write(
    account,
    () => _repository.video(account, resources, add: add, remove: remove),
  );
  Future<LoadingState<FavFolderInfo>> saveFolder(
    Account account, {
    int? id,
    required String title,
    required bool public,
    required String cover,
    required String intro,
  }) {
    if (title.trim().isEmpty || (id != null && id <= 0)) {
      return Future.value(const Error('收藏夹名称或标识无效'));
    }
    return write(
      account,
      () => _repository.saveFolder(
        account,
        id: id,
        title: title,
        public: public,
        cover: cover,
        intro: intro,
      ),
    );
  }

  Future<LoadingState<void>> folderAction(
    Account account,
    int id,
    FolderAction action,
  ) {
    if (id <= 0) return Future.value(const Error('收藏夹标识无效'));
    return write(account, () => _repository.folderAction(account, id, action));
  }

  Future<LoadingState<void>> cheese(Account account, int id, bool favorite) =>
      write(account, () => _repository.cheese(account, id, favorite));

  Future<LoadingState<void>> article(
    Account account, {
    required int articleId,
    String? opusId,
    required bool remove,
  }) => write(
    account,
    () => _repository.article(
      account,
      articleId: articleId,
      opusId: opusId,
      remove: remove,
    ),
  );

  Future<LoadingState<void>> season(Account account, int id, bool remove) =>
      write(account, () => _repository.season(account, id, remove));

  Future<String> uploadCover(Account account, String path) {
    if (!owns(account)) return Future.error(const Error('账号已切换'));
    return _repository.uploadCover(account, path);
  }

  Future<LoadingState<void>> sort(
    FavoriteState source,
    List<Object> original,
    String order, {
    int? folder,
  }) {
    if (!owns(source.account) || original.isEmpty || order.isEmpty) {
      return Future.value(const Error('排序内容已更新'));
    }
    return write(
      source.account,
      () => _repository.sort(source.account, folder: folder, order: order),
    );
  }

  @override
  Future<void> close() async {
    await _revisionSubscription.cancel();
    await super.close();
  }
}

final favoriteLibraryProvider = Provider<FavoriteLibrary>(
  (ref) => FavoriteLibrary.legacy,
);
final favoriteFeedProvider = AsyncNotifierProvider.autoDispose
    .family<FavoriteFeed, FavoriteState, FavoriteQuery>(
      FavoriteFeed.new,
      retry: (_, _) => null,
    );

class FavoriteFeed extends PagedFeed<Object, FavoriteMetadata> {
  FavoriteFeed(this.query);
  final FavoriteQuery query;
  late FavoriteLibrary _library;
  int _revision = 0;
  @override
  Account watchAccount() {
    _library = ref.watch(favoriteLibraryProvider);
    _revision = _library.revision;
    final account = ref.watch(mainAccountProvider);
    final owner = ref;
    final sub = _library.changes.listen((changed) {
      if (owner.mounted && identical(account, changed)) owner.invalidateSelf();
    });
    owner.onDispose(sub.cancel);
    return account;
  }

  @override
  bool ownsAccount(Account account) =>
      _library.owns(account) && _library.revision == _revision;
  @override
  Object itemKey(Object item) => favoriteKey(item);
  @override
  Future<FeedPage<Object, FavoriteMetadata>> fetch(
    Account account,
    Object? cursor,
  ) {
    final owner = ref;
    return _library._repository.page(
      account,
      query,
      cursor,
      isCurrent: () => owner.mounted && ownsAccount(account),
    );
  }

  @override
  FavoriteMetadata mergeMetadata(
    FavoriteMetadata previous,
    FavoriteMetadata next,
  ) => FavoriteMetadata(
    folder: next.folder ?? previous.folder,
    total: next.total ?? previous.total,
  );
  bool _valid(FavoriteState source, List<Object> items) =>
      isCurrent(source) &&
      items.isNotEmpty &&
      items.every(source.items.contains);
  Future<LoadingState<void>> remove(
    FavoriteState source,
    Iterable<Object> items,
  ) {
    final selected = items.toList();
    if (!_valid(source, selected)) return Future.value(const Error('收藏列表已更新'));
    for (final item in selected) {
      final id = switch (item) {
        FavDetailItemModel(:final id, :final type)
            when type != null && type > 0 =>
          id,
        FavArticleItemModel(:final opusId) => int.tryParse(opusId ?? ''),
        FavTopicItem(:final id) => id,
        SpaceCheeseItem(:final seasonId) => seasonId,
        FavNoteItemModel(:final cvid, :final noteId) => int.tryParse(
          '${query.published ? cvid : noteId}',
        ),
        _ => null,
      };
      if (id == null || id <= 0) return Future.value(const Error('所选内容缺少有效标识'));
    }
    if (query.kind == FavoriteKind.detail &&
        source.metadata.folder?.mid != source.account.mid) {
      return Future.value(const Error('只能修改自己的收藏夹'));
    }
    return _library.write(
      source.account,
      () => _library._repository.remove(source.account, query, selected),
    );
  }

  Future<LoadingState<void>> pgc(
    FavoriteState source,
    Iterable<Object> items,
    int? status,
  ) {
    final selected = items.toList();
    final ids = selected
        .whereType<FavPgcItemModel>()
        .map((item) => item.seasonId)
        .toList();
    if (!_valid(source, selected) ||
        query.kind != FavoriteKind.pgc ||
        ids.length != selected.length ||
        ids.any((id) => id == null || id <= 0) ||
        (status == null && ids.length != 1) ||
        (status != null && (status < 1 || status > 3))) {
      return Future.value(const Error('追番列表已更新'));
    }
    return _library.write(
      source.account,
      () => _library._repository.pgc(source.account, ids.cast<int>(), status),
    );
  }

  Future<LoadingState<void>> transfer(
    FavoriteState source,
    Iterable<Object> items,
    int destination,
    bool copy,
  ) {
    final selected = items.toList();
    if (!_valid(source, selected) ||
        query.kind != FavoriteKind.detail ||
        destination <= 0 ||
        destination == query.mediaId ||
        source.metadata.folder?.mid != source.account.mid ||
        selected.any(
          (item) =>
              item is! FavDetailItemModel ||
              item.id == null ||
              item.id! <= 0 ||
              item.type == null ||
              item.type! <= 0,
        )) {
      return Future.value(const Error('收藏列表或目标已更新'));
    }
    final resources = selected
        .cast<FavDetailItemModel>()
        .toList()
        .reversed
        .map((item) => '${item.id}:${item.type}')
        .join(',');
    return _library.write(
      source.account,
      () => _library._repository.transfer(
        source.account,
        source: query.mediaId,
        destination: destination,
        copy: copy,
        resources: resources,
      ),
    );
  }

  Future<LoadingState<void>> sort(
    FavoriteState source,
    List<Object> original,
    String order,
  ) {
    final current = state.value;
    if (!isCurrent(source) ||
        current == null ||
        original.length != current.items.length ||
        !Iterable<int>.generate(
          original.length,
        ).every((index) => identical(original[index], current.items[index])) ||
        (query.kind != FavoriteKind.folders &&
            query.kind != FavoriteKind.detail) ||
        (query.kind == FavoriteKind.folders && current.next != null) ||
        (query.kind == FavoriteKind.detail &&
            source.metadata.folder?.mid != source.account.mid)) {
      return Future.value(const Error('排序内容已更新，请重新打开'));
    }
    return _library.sort(
      source,
      original,
      order,
      folder: query.kind == FavoriteKind.detail ? query.mediaId : null,
    );
  }
}

typedef MembershipQuery = ({Object owner, FavoriteTarget target});
final favoriteMembershipProvider = FutureProvider.autoDispose
    .family<FavoriteMembership, MembershipQuery>((ref, query) {
      final account = ref.watch(mainAccountProvider);
      final library = ref.watch(favoriteLibraryProvider);
      final sub = library.changes.listen((changed) {
        if (ref.mounted && identical(account, changed)) ref.invalidateSelf();
      });
      ref.onDispose(sub.cancel);
      return library.membership(account, query.target);
    }, retry: (_, _) => null);
