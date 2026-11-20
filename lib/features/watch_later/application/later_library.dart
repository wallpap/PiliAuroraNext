import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_library/application/library_module.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/watch_later/data/later_repository.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/watch_later/domain/list.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

class LaterLibrary extends LibraryModule {
  LaterLibrary(this._repository);
  final LaterRepository _repository;

  /// 兼容尚未迁移的播放器入口；新页面通过 provider 注入同一个 Module。
  static final legacy = LaterLibrary(LaterRepository());
  Future<List<FavFolderInfo>> destinations(Account account) {
    if (!owns(account)) return Future.error(const Error('账号已切换'));
    return _repository.folders(account);
  }

  @override
  bool owns(Account account) => identical(account, Accounts.main);
  Future<LoadingState<void>> add({
    String? bvid,
    Object? aid,
    Account? account,
  }) {
    final owner = account ?? Accounts.main;
    return write(owner, () => _repository.add(owner, bvid: bvid, aid: aid));
  }

  Future<LoadingState<void>> remove(Iterable<int> aids, {Account? account}) {
    final ids = aids.toSet();
    if (ids.isEmpty || ids.any((id) => id <= 0)) {
      return Future.value(const Error('视频标识无效'));
    }
    final owner = account ?? Accounts.main;
    return write(owner, () => _repository.remove(owner, ids));
  }

  Future<LoadingState<void>> clear(int? type, {Account? account}) {
    final owner = account ?? Accounts.main;
    return write(owner, () => _repository.clear(owner, type));
  }

  Future<LoadingState<void>> transfer(
    List<int> aids,
    int folder,
    bool copy, {
    required Account account,
  }) {
    if (aids.isEmpty || aids.any((id) => id <= 0) || folder <= 0) {
      return Future.value(const Error('内容标识无效'));
    }
    final ids = List<int>.of(aids);
    return write(
      account,
      () => FavoriteLibrary.legacy.write(
        account,
        () => _repository.transfer(account, ids, folder, copy),
      ),
    );
  }
}

final laterLibraryProvider = Provider<LaterLibrary>(
  (ref) => LaterLibrary.legacy,
);
typedef LaterQuery = ({Object owner, int viewed, String keyword, bool asc});
typedef LaterState = FeedState<LaterItemModel, int>;
final laterFeedProvider = AsyncNotifierProvider.autoDispose
    .family<LaterFeed, LaterState, LaterQuery>(
      LaterFeed.new,
      retry: (_, _) => null,
    );

class LaterFeed extends PagedFeed<LaterItemModel, int> {
  LaterFeed(this.query);
  final LaterQuery query;
  late LaterLibrary _library;
  @override
  Account watchAccount() {
    _library = ref.watch(laterLibraryProvider);
    final account = ref.watch(mainAccountProvider);
    final owner = ref;
    final sub = _library.changes.listen((changed) {
      if (owner.mounted && identical(account, changed)) owner.invalidateSelf();
    });
    owner.onDispose(sub.cancel);
    return account;
  }

  @override
  bool ownsAccount(Account account) => _library.owns(account);
  @override
  Object itemKey(LaterItemModel item) => item.aid ?? item;
  @override
  Future<FeedPage<LaterItemModel, int>> fetch(
    Account account,
    Object? cursor,
  ) async {
    final page = cursor as int? ?? 1;
    final data = await _library._repository.page(
      account,
      page: page,
      viewed: query.viewed,
      keyword: query.keyword,
      asc: query.asc,
    );
    final items = data.list ?? [];
    final total = data.count ?? 0;
    return FeedPage(
      items,
      metadata: total,
      next:
          items.isNotEmpty &&
              (data.count == null ? items.length >= 20 : page * 20 < total)
          ? page + 1
          : null,
    );
  }

  Future<LoadingState<void>> remove(
    LaterState source,
    Iterable<LaterItemModel> items,
  ) {
    final selected = items.toList();
    if (!isCurrent(source) ||
        selected.isEmpty ||
        selected.any(
          (item) => !source.items.contains(item) || item.aid == null,
        )) {
      return Future.value(const Error('列表已更新，请重试'));
    }
    return _library.remove(
      selected.map((item) => item.aid!),
      account: source.account,
    );
  }
}
