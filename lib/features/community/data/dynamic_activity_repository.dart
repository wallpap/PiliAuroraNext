import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/grpc/bilibili/app/dynamic/v2.pb.dart'
    show ModuleAuthor, DynamicItem;
import 'package:pili_aurora_next/grpc/dyn.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final dynamicActivityRepositoryProvider = Provider(
  (ref) => const DynamicActivityRepository(),
);

class DynamicActivityRepository {
  const DynamicActivityRepository();
  Future<LoadingState<DiscoveryPage<ModuleAuthor, DynamicActivityCursor>>>
  likes(
    Account account,
    String id,
    int page,
    DynamicActivityCursor? cursor,
  ) async {
    final result = await DynGrpc.likeList(
      account: account,
      dynamicId: id,
      page: page,
      uidOffset: cursor?.offset == null
          ? null
          : Int64.parseInt(cursor!.offset!),
    );
    if (result case Success(:final response)) {
      return Success(
        _page(
          response.list,
          response.list.lastOrNull?.mid.toString(),
          response.hasMore,
          response.totalCount.toInt(),
          cursor,
        ),
      );
    }
    return result as Error;
  }

  Future<LoadingState<DiscoveryPage<DynamicItem, DynamicActivityCursor>>>
  reposts(
    Account account,
    String id,
    DynamicActivityCursor? cursor,
  ) async {
    final result = await DynGrpc.repostList(
      account: account,
      dynamicId: id,
      offset: cursor?.offset,
    );
    if (result case Success(:final response)) {
      return Success(
        _page(
          response.list,
          response.offset,
          response.hasMore,
          response.totalCount.toInt(),
          cursor,
        ),
      );
    }
    return result as Error;
  }

  DiscoveryPage<T, DynamicActivityCursor> _page<T>(
    List<T> items,
    String? offset,
    bool more,
    int total,
    DynamicActivityCursor? cursor,
  ) {
    final seen = {...?cursor?.seen};
    final hasMore =
        more && offset != null && offset.isNotEmpty && seen.add(offset);
    return DiscoveryPage(
      items,
      metadata: DynamicActivityCursor(offset, Set.unmodifiable(seen), total),
      hasMore: hasMore,
    );
  }
}
