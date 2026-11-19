import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/pair.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_draft.dart';
import 'package:pili_aurora_next/http/dynamics.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/reply.dart';
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

  Future<LoadingState<String?>> publish(
    Account account,
    DynamicDraft draft,
    List? pictures,
  ) async {
    final topic = draft.topic;
    final apiTopic = topic == null
        ? null
        : Pair(first: topic.$1, second: topic.$2);
    final privatePub = draft.isPrivate ? 1 : null;
    if (draft.editId case final id?) {
      final result = await DynamicsHttp.editDyn(
        account: account,
        dynId: id,
        repostDynId: draft.repostId,
        rawText: draft.rawText,
        pics: pictures,
        replyOption: draft.replyOption,
        privatePub: privatePub,
        title: draft.title,
        topic: apiTopic,
        extraContent: draft.richText,
      );
      return switch (result) {
        Success() => const Success(null),
        Error() => result,
        Loading() => result,
      };
    }
    final publishTime = draft.publishTime;
    final reserveId = draft.reserveId;
    return DynamicsHttp.createDynamic(
      account: account,
      mid: account.mid,
      dynIdStr: draft.repostId,
      rid: draft.videoId,
      dynType: draft.videoType,
      rawText: draft.rawText,
      pics: pictures,
      publishTime: publishTime == null
          ? null
          : publishTime.millisecondsSinceEpoch ~/ 1000,
      replyOption: draft.replyOption,
      privatePub: privatePub,
      title: draft.title,
      topic: apiTopic,
      extraContent: draft.richText,
      attachCard: reserveId == null
          ? null
          : {
              'common_card': {
                'type': 14,
                'biz_id': reserveId,
                'reserve_source': 0,
                'reserve_lottery': 0,
              },
            },
    );
  }

  Future<LoadingState<void>> like(Account account, String id, bool liked) =>
      DynamicsHttp.thumbDynamic(
        account: account,
        dynamicId: id,
        up: liked ? 1 : 2,
      );

  Future<LoadingState<DynamicItemModel>> detail(Account account, Object? id) =>
      DynamicsHttp.dynamicDetail(account: account, id: id);

  Future<LoadingState<void>> setVisibility(
    Account account,
    Object id,
    bool makePublic,
  ) => DynamicsHttp.dynPrivatePubSetting(
    account: account,
    dynId: id,
    action: makePublic ? 'public_pub' : 'private_pub',
  );

  Future<LoadingState<String?>> setReplySubject(
    Account account,
    int oid,
    int type,
    int action,
  ) => ReplyHttp.replySubjectModify(
    account: account,
    oid: oid,
    type: type,
    action: action,
  );

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
