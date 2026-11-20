import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/favorites/domain/favorite_items.dart';
import 'package:pili_aurora_next/features/favorites/domain/favorite_query.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_folder/data.dart';
import 'package:pili_aurora_next/http/fav.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/http/msg.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/subscriptions/data/hidden_media.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

class FavoriteRepository {
  Future<LoadingState<void>> article(
    Account account, {
    required int articleId,
    required String? opusId,
    required bool remove,
  }) => opusId != null
      ? FavHttp.communityAction(
          account: account,
          opusId: opusId,
          action: remove ? 4 : 3,
        )
      : remove
      ? FavHttp.delFavArticle(account: account, id: articleId)
      : FavHttp.addFavArticle(account: account, id: articleId);

  Future<LoadingState<void>> season(Account account, int id, bool remove) =>
      FavHttp.seasonFav(account: account, isFav: remove, seasonId: id);

  Future<FeedPage<Object, FavoriteMetadata>> page(
    Account account,
    FavoriteQuery query,
    Object? cursor, {
    bool Function()? isCurrent,
  }) async {
    var page = cursor is (int, int) ? cursor.$1 : cursor as int? ?? 1;
    switch (query.kind) {
      case FavoriteKind.folders:
        final data = (await FavHttp.userfavFolder(
          account: account,
          pn: page,
          ps: 20,
          mid: account.mid,
        )).data;
        final items = data.list ?? <FavFolderInfo>[];
        return FeedPage(
          items,
          metadata: FavoriteMetadata(total: data.count),
          next: _next(page, items.length, 20, data.hasMore, data.count),
        );
      case FavoriteKind.detail:
        if (query.mediaId <= 0) throw const Error('收藏夹标识无效，请重新打开页面');
        if (query.reverse && cursor == null) {
          final info = (await folder(account, query.mediaId)).data;
          if (isCurrent?.call() == false) throw const Error('账号或查询已更新');
          page = (info.mediaCount / 20).ceil().clamp(1, 1 << 30);
        }
        final data = (await FavHttp.userFavFolderDetail(
          account: account,
          mediaId: query.mediaId,
          pn: page,
          ps: 20,
          keyword: query.keyword,
          type: query.type,
          order: query.order,
        )).data;
        final info = data.info;
        if (info == null) throw const Error('收藏夹信息不完整，请重试');
        var items = data.medias ?? <FavDetailItemModel>[];
        final next = query.reverse
            ? (page > 1 ? page - 1 : null)
            : _next(page, items.length, 20, data.hasMore, null);
        if (info.mid != account.mid && Pref.hideInvalidSubscriptionVideos) {
          final hidden = HiddenSubscriptionMedia(
            GStorage.localCache,
            account.mid,
          ).read(11, query.mediaId);
          items = items
              .where((item) => !hidden.contains('${item.type ?? 2}:${item.id}'))
              .toList();
        }
        return FeedPage(
          query.reverse ? items.reversed : items,
          metadata: FavoriteMetadata(folder: info, total: info.mediaCount),
          next: next,
        );
      case FavoriteKind.pgc:
        final data = (await FavHttp.favPgc(
          account: account,
          type: query.type,
          followStatus: query.status,
          pn: page,
        )).data;
        final items = data.list ?? <FavPgcItemModel>[];
        return FeedPage(
          items,
          metadata: FavoriteMetadata(total: data.total),
          next:
              items.isNotEmpty &&
                  (data.total == null ||
                      (cursor is (int, int) ? cursor.$2 : 0) + items.length <
                          data.total!)
              ? (
                  page + 1,
                  (cursor is (int, int) ? cursor.$2 : 0) + items.length,
                )
              : null,
        );
      case FavoriteKind.article:
        final data = (await FavHttp.favArticle(
          account: account,
          page: page,
        )).data;
        final items = data.items ?? <FavArticleItemModel>[];
        return FeedPage(
          items,
          metadata: const FavoriteMetadata(),
          next: _next(page, items.length, 20, data.hasMore, null),
        );
      case FavoriteKind.note:
        final items =
            (await (query.published
                    ? FavHttp.userNoteList(account: account, page: page)
                    : FavHttp.noteList(account: account, page: page)))
                .data ??
            <FavNoteItemModel>[];
        return FeedPage(
          items,
          metadata: const FavoriteMetadata(),
          next: _next(page, items.length, 10, null, null),
        );
      case FavoriteKind.topic:
        final data = (await FavHttp.favTopic(
          account: account,
          page: page,
        )).data;
        final items = data.topicList?.topicItems ?? <FavTopicItem>[];
        final total = data.topicList?.pageInfo?.total;
        return FeedPage(
          items,
          metadata: FavoriteMetadata(total: total),
          next: _next(page, items.length, 24, null, total),
        );
      case FavoriteKind.cheese:
        final data = (await FavHttp.favPugv(
          account: account,
          mid: account.mid,
          page: page,
        )).data;
        final items = data.items ?? <SpaceCheeseItem>[];
        return FeedPage(
          items,
          metadata: const FavoriteMetadata(),
          next: _next(page, items.length, 20, data.page?.next, null),
        );
    }
  }

  int? _next(int page, int length, int size, bool? more, int? total) =>
      length > 0 &&
          (more ?? (total == null ? length >= size : page * size < total))
      ? page + 1
      : null;
  Future<LoadingState<FavFolderInfo>> folder(Account account, int id) =>
      FavHttp.favFolderInfo(account: account, mediaId: id);
  Future<List<FavFolderInfo>> folders(Account account) async =>
      (await FavHttp.allFavFolders(account.mid, account: account)).data.list ??
      [];
  Future<LoadingState<FavFolderData>> membership(
    Account account,
    (Object, int) target,
  ) => FavHttp.videoInFolder(
    account: account,
    mid: account.mid,
    rid: target.$1,
    type: target.$2,
  );
  Future<LoadingState<void>> video(
    Account account,
    String resources, {
    String? add,
    String? remove,
  }) => FavHttp.favVideo(
    account: account,
    resources: resources,
    addIds: add,
    delIds: remove,
  );
  Future<LoadingState<void>> unfavorite(
    Account account,
    (Object, int) target,
  ) => FavHttp.unfavAll(account: account, rid: target.$1, type: target.$2);
  Future<LoadingState<FavFolderInfo>> saveFolder(
    Account account, {
    int? id,
    required String title,
    required bool public,
    required String cover,
    required String intro,
  }) => FavHttp.addOrEditFolder(
    account: account,
    isAdd: id == null,
    mediaId: id,
    title: title,
    privacy: public ? 0 : 1,
    cover: cover,
    intro: intro,
  );
  Future<LoadingState<void>> folderAction(
    Account account,
    int id,
    FolderAction action,
  ) => switch (action) {
    FolderAction.clean => FavHttp.cleanFav(account: account, mediaId: id),
    FolderAction.delete => FavHttp.deleteFolder(
      account: account,
      mediaIds: '$id',
    ),
    FolderAction.follow => FavHttp.favFavFolder(id, account: account),
    FolderAction.unfollow => FavHttp.unfavFavFolder(id, account: account),
  };
  Future<LoadingState<void>> sort(
    Account account, {
    int? folder,
    required String order,
  }) => folder == null
      ? FavHttp.sortFavFolder(account: account, sort: order)
      : FavHttp.sortFav(account: account, mediaId: folder, sort: order);
  Future<LoadingState<void>> transfer(
    Account account, {
    required int source,
    required int destination,
    required bool copy,
    required String resources,
  }) => FavHttp.copyOrMoveFav(
    account: account,
    isCopy: copy,
    isFav: true,
    srcMediaId: source,
    tarMediaId: destination,
    resources: resources,
    mid: copy ? account.mid : null,
  );
  Future<LoadingState<void>> remove(
    Account account,
    FavoriteQuery query,
    List<Object> items,
  ) => switch (query.kind) {
    FavoriteKind.detail => video(
      account,
      items
          .cast<FavDetailItemModel>()
          .map((item) => '${item.id}:${item.type}')
          .join(','),
      remove: '${query.mediaId}',
    ),
    FavoriteKind.article => FavHttp.communityAction(
      account: account,
      opusId: (items.single as FavArticleItemModel).opusId!,
      action: 4,
    ),
    FavoriteKind.topic => FavHttp.delFavTopic(
      (items.single as FavTopicItem).id!,
      account: account,
    ),
    FavoriteKind.cheese => FavHttp.delFavPugv(
      (items.single as SpaceCheeseItem).seasonId!,
      account: account,
    ),
    FavoriteKind.note => FavHttp.delNote(
      account: account,
      isPublish: query.published,
      noteIds: items
          .cast<FavNoteItemModel>()
          .map((item) => query.published ? item.cvid : item.noteId)
          .join(','),
    ),
    _ => Future.value(const Error('此分类不支持删除')),
  };
  Future<LoadingState<void>> pgc(
    Account account,
    List<int> ids,
    int? status,
  ) async => status == null
      ? await VideoHttp.pgcDel(account: account, seasonId: ids.single)
      : await VideoHttp.pgcUpdate(
          account: account,
          seasonId: ids.join(','),
          status: status,
        );
  Future<LoadingState<void>> cheese(Account account, int id, bool favorite) =>
      favorite
      ? FavHttp.addFavPugv(id, account: account)
      : FavHttp.delFavPugv(id, account: account);
  Future<String> uploadCover(Account account, String path) async =>
      (await MsgHttp.uploadImage(
            account: account,
            path: path,
            bucket: 'medialist',
            dir: 'cover',
          )).data['location']
          as String;
  int? get quickFolder => Pref.quickFavId;
  bool get quickEnabled => Pref.enableQuickFav;

  Future<void> setQuickFolder(int? id) =>
      GStorage.setting.put(SettingBoxKey.quickFavId, id);
}
