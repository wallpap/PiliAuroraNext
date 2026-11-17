import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/dynamics/up.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/http/msg.dart';
import 'package:pili_aurora_next/http/member.dart';
import 'package:pili_aurora_next/models/common/dynamic/dynamics_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_cursor.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';

final dynamicsRepositoryProvider = Provider(
  (ref) => const DynamicsRepository(),
);

class DynamicsRepository {
  const DynamicsRepository();
  Future<LoadingState<void>> remove(Account account, String id) =>
      MsgHttp.removeDynamic(account: account, dynIdStr: id);
  Future<LoadingState<void>> pin(Account account, String id, bool pinned) =>
      pinned
      ? DynamicsHttp.setTop(account: account, dynamicId: id)
      : DynamicsHttp.rmTop(account: account, dynamicId: id);

  Future<LoadingState<DiscoveryPage<DynamicItemModel, DynamicCursor>>> member(
    Account account,
    int mid,
    DynamicCursor? cursor,
  ) async {
    final result = await MemberHttp.memberDynamic(
      account: account,
      mid: mid,
      offset: cursor?.offset,
      refillFiltered: false,
    );
    if (result case Success(:final response)) {
      final offset = response.offset;
      final seen = {...?cursor?.seen};
      return Success(
        DiscoveryPage(
          response.items ?? [],
          metadata: DynamicCursor(
            offset,
            Set.unmodifiable({...seen, ?offset}),
          ),
          hasMore:
              response.hasMore != false &&
              offset != null &&
              offset.isNotEmpty &&
              offset != '-1' &&
              seen.add(offset),
        ),
      );
    }
    return result as Error;
  }

  Future<LoadingState<DiscoveryPage<DynamicItemModel, DynamicCursor>>> feed(
    Account account,
    DynamicsTabType type,
    int hostMid,
    Set<int> banned,
    DynamicCursor? cursor,
  ) async {
    final result = await DynamicsHttp.followDynamic(
      account: account,
      type: type,
      hostMid: hostMid,
      tempBannedList: banned,
      offset: cursor?.offset,
      refillFiltered: false,
    );
    if (result case Success(:final response)) {
      final offset = response.offset;
      final seen = {...?cursor?.seen};
      final more =
          response.hasMore == true &&
          offset != null &&
          offset.isNotEmpty &&
          seen.add(offset);
      return Success(
        DiscoveryPage(
          response.items ?? [],
          metadata: DynamicCursor(offset, Set.unmodifiable(seen)),
          hasMore: more,
        ),
      );
    }
    return result as Error;
  }

  Future<LoadingState<FollowUpModel>> authors(
    Account account, {
    String? offset,
    int? followingPage,
  }) => followingPage != null
      ? DynamicsHttp.followings(
          account: account,
          vmid: account.mid,
          pn: followingPage,
          orderType: 'attention',
          ps: 50,
        )
      : offset == null
      ? DynamicsHttp.followUp(account: account)
      : DynamicsHttp.dynUpList(offset, account: account);
}
