import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/dynamic_activity_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_listing.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/generated/bilibili/app/dynamic/v2.pb.dart'
    show ModuleAuthor, DynamicItem;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef DynamicActivityQuery = ({Object owner, String id});
final dynamicLikesProvider = NotifierProvider.autoDispose
    .family<
      DynamicLikes,
      DiscoveryListingState<ModuleAuthor, DynamicActivityCursor>,
      DynamicActivityQuery
    >(DynamicLikes.new);
final dynamicRepostsProvider = NotifierProvider.autoDispose
    .family<
      DynamicReposts,
      DiscoveryListingState<DynamicItem, DynamicActivityCursor>,
      DynamicActivityQuery
    >(DynamicReposts.new);

/// 标题可以订阅计数，名单在首次进入 Tab 时才激活。
abstract class DynamicActivity<T>
    extends DiscoveryListing<T, DynamicActivityCursor> {
  bool _activated = false;
  @override
  bool get usesMainAccount => true;
  @override
  bool get filterAuthors => false;
  @override
  bool get loadOnBuild => _activated;
  Future<void> activate() => _activated ? Future.value() : onRefresh();
  @override
  Future<void> onRefresh() {
    _activated = true;
    return super.onRefresh();
  }
}

class DynamicLikes extends DynamicActivity<ModuleAuthor> {
  DynamicLikes(this.query);
  final DynamicActivityQuery query;
  @override
  Object itemKey(ModuleAuthor item) => item.mid.toString();
  @override
  Future<LoadingState<DiscoveryPage<ModuleAuthor, DynamicActivityCursor>>>
  fetch(Account account, int page) => ref
      .read(dynamicActivityRepositoryProvider)
      .likes(account, query.id, page, queryMetadata);
}

class DynamicReposts extends DynamicActivity<DynamicItem> {
  DynamicReposts(this.query);
  final DynamicActivityQuery query;
  @override
  Object itemKey(DynamicItem item) =>
      item.extend.dynIdStr.isEmpty ? item : item.extend.dynIdStr;
  @override
  Future<LoadingState<DiscoveryPage<DynamicItem, DynamicActivityCursor>>> fetch(
    Account account,
    int page,
  ) => ref
      .read(dynamicActivityRepositoryProvider)
      .reposts(account, query.id, queryMetadata);
}
