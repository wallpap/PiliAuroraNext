import 'package:pili_aurora_next/features/subscriptions/domain/subscription_cleanup.dart';
import 'package:pili_aurora_next/features/subscriptions/data/hidden_media.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_page.dart';
import 'package:pili_aurora_next/features/subscriptions/domain/subscription_detail.dart';
import 'package:pili_aurora_next/http/fav.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

/// HTTP 与本地隐藏记录只在此适配；所有请求显式绑定发起账号。
class SubscriptionRepository {
  static const pageSize = 20;
  bool get hideInvalid => Pref.hideInvalidSubscriptionVideos;
  HiddenSubscriptionMedia hidden(Account account) =>
      HiddenSubscriptionMedia(GStorage.localCache, account.mid);
  Future<LoadingState<SubData>> subscriptions(Account account, int page) =>
      UserHttp.userSubFolder(
        account: account,
        mid: account.mid,
        pn: page,
        ps: pageSize,
      );
  Future<LoadingState<SubDetailData>> detail(
    Account account,
    int id,
    int page,
  ) => FavHttp.favSeasonList(account: account, id: id, pn: page, ps: pageSize);
  Future<LoadingState<void>> cancel(Account account, SubItemModel item) =>
      FavHttp.cancelSub(account: account, id: item.id!, type: item.type!);
  Future<LoadingState<bool>> available(Account account, int aid) =>
      FavHttp.subscriptionVideoAvailable(aid, account: account);
  Future<LoadingState<SubscriptionContentPage>> contents(
    Account requestAccount,
    SubItemModel item,
    int page,
  ) async {
    if (item.type == 11) {
      final result = await FavHttp.userFavFolderDetail(
        account: requestAccount,
        mediaId: item.id!,
        pn: page,
        ps: pageSize,
      );
      if (result is Error) return result;
      if (result is! Success) return const Error('收藏夹尚未加载完成');
      final data = result.data;
      final medias = data.medias;
      if (medias == null && (data.info?.mediaCount ?? 0) > 0) {
        return const Error('收藏夹内容响应不完整');
      }
      if (data.hasMore == null) return const Error('收藏夹分页信息不完整');
      return Success(
        SubscriptionContentPage(
          items: [
            for (final media in medias ?? [])
              (
                id: media.id ?? 0,
                type: media.type ?? 2,
                valid: const [1, 9].contains(media.attr)
                    ? false
                    : media.attr != null ||
                          (media.type != null && media.type != 2)
                    ? true
                    : null,
              ),
          ],
          hasMore: data.hasMore!,
          total: data.info?.mediaCount,
        ),
      );
    }
    final result = await FavHttp.favSeasonList(
      account: requestAccount,
      id: item.id!,
      pn: page,
      ps: pageSize,
    );
    if (result is Error) return result;
    if (result is! Success) return const Error('合集尚未加载完成');
    final data = result.data;
    final medias = data.medias;
    if (medias == null && (data.info?.mediaCount ?? 0) > 0) {
      return const Error('合集内容响应不完整');
    }
    final count = data.info?.mediaCount;
    return Success(
      SubscriptionContentPage(
        items: [
          for (final media in medias ?? [])
            (id: media.id ?? 0, type: 2, valid: null),
        ],
        hasMore: count != null
            ? page * pageSize < count
            : (medias?.length ?? 0) >= pageSize,
        total: count,
      ),
    );
  }
}
