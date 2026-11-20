import 'package:pili_aurora_next/features/playback/data/video_metadata_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/member.dart';
import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/models/remote/member_card_info/data.dart';
import 'package:pili_aurora_next/models/remote/pagelist/page_item.dart';
import 'package:pili_aurora_next/models/remote/relation/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_ai_conclusion/model_result.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/data.dart';
import 'package:pili_aurora_next/models/remote/video/video_detail/staff.dart';
import 'package:pili_aurora_next/models/remote/video/video_tag/data.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';

enum _Read { introduction, author, relation, online, tags }

class VideoDetails {
  VideoDetails({required this.video, required this.part, required this.author});

  final String? Function() video;
  final int Function() part;
  final int? Function() author;
  final _queries = <_Read, Object>{};
  bool _unblocking = false;

  Future<LoadingState<VideoDetailData>?> introduction() => _read(
    _Read.introduction,
    (bvid, account) => VideoHttp.videoIntro(bvid: bvid, account: account),
    heartbeat: true,
  );

  static void retainEpisodeOrder(
    VideoDetailData previous,
    VideoDetailData incoming,
  ) {
    if (incoming.ugcSeason?.id != null &&
        incoming.ugcSeason?.id == previous.ugcSeason?.id) {
      incoming.ugcSeason = previous.ugcSeason;
    }
    if (previous.isPageReversed &&
        previous.bvid == incoming.bvid &&
        previous.cid == incoming.cid) {
      incoming.pages = incoming.pages?.reversed.toList() ?? previous.pages;
      incoming.isPageReversed = true;
    }
  }

  Future<String?> online() async {
    final cid = part();
    return (await _read(
      _Read.online,
      (bvid, account) => VideoHttp.onlineTotal(
        aid: IdUtils.bv2av(bvid),
        bvid: bvid,
        cid: cid,
        account: account,
      ),
      heartbeat: true,
      matches: () => part() == cid,
    ))?.dataOrNull;
  }

  Future<LoadingState<List<VideoTagItem>?>?> tags() {
    final cid = part();
    return _read(
      _Read.tags,
      (bvid, account) =>
          UserHttp.videoTags(bvid: bvid, cid: cid, account: account),
      matches: () => part() == cid,
    );
  }

  Future<({Map<String, dynamic>? staff, MemberCardInfoData? profile})?>
  authorStats(List<Staff>? staff) async {
    final mid = author();
    final result =
        await _read<
          ({Map<String, dynamic>? staff, MemberCardInfoData? profile})
        >(
          _Read.author,
          (bvid, account) async {
            if (staff != null && staff.isNotEmpty) {
              final result = await VideoMetadataRepository.staffRelations(
                account,
                staff.map((item) => item.mid),
              );
              return Success((staff: result.dataOrNull, profile: null));
            }
            if (mid == null) return const Success((staff: null, profile: null));
            final result = await MemberHttp.memberCardInfo(
              mid: mid,
              account: account,
            );
            return Success((staff: null, profile: result.dataOrNull));
          },
          matches: () => author() == mid,
        );
    return result?.dataOrNull;
  }

  Future<RelationData?> followStatus(int mid) async {
    if (_unblocking || author() != mid) return null;
    final result = await _read(
      _Read.relation,
      (bvid, account) => UserHttp.userRelation(mid, account: account),
      matches: () => author() == mid && !_unblocking,
    );
    final relation = result?.dataOrNull;
    if (relation?.special == 1) relation!.attribute = -10;
    return relation;
  }

  bool Function() captureAuthor(int mid) {
    final bvid = video();
    final account = Accounts.main;
    return () =>
        bvid != null &&
        bvid == video() &&
        author() == mid &&
        identical(account, Accounts.main);
  }

  void invalidateRelation() => _queries.remove(_Read.relation);

  Future<bool> unblock(int mid) async {
    final account = Accounts.main;
    final current = captureAuthor(mid);
    if (_unblocking || !current() || !account.isLogin) return false;
    _unblocking = true;
    invalidateRelation();
    try {
      final result = await VideoHttp.relationMod(
        mid: mid,
        act: 6,
        reSrc: 11,
        account: account,
      );
      return result.isSuccess && current();
    } finally {
      _unblocking = false;
    }
  }

  static Future<LoadingState<PageItem?>> resolvePart(
    Account account,
    String bvid,
    int aid,
  ) => SearchHttp.pageWithDimension(account: account, aid: aid, bvid: bvid);

  static Future<LoadingState<AiConclusionResult?>?> summary(
    String bvid,
    int cid,
    int? mid,
  ) async {
    final account = Accounts.heartbeat;
    if (!account.isLogin) return const Error('账号未登录');
    final result = await VideoHttp.aiConclusion(
      bvid: bvid,
      cid: cid,
      upMid: mid,
      account: account,
    );
    if (!identical(account, Accounts.heartbeat)) return null;
    return switch (result) {
      Success(:final response) => Success(response.modelResult),
      Error() => result,
      Loading() => null,
    };
  }

  Future<LoadingState<T>?> _read<T>(
    _Read kind,
    Future<LoadingState<T>> Function(String bvid, Account account) request, {
    bool heartbeat = false,
    bool Function()? matches,
  }) async {
    final bvid = video();
    if (bvid == null) return null;
    Account currentAccount() => heartbeat ? Accounts.heartbeat : Accounts.main;
    final account = currentAccount();
    final token = _queries[kind] = Object();
    final result = await request(bvid, account);
    if (token != _queries[kind] ||
        bvid != video() ||
        !identical(account, currentAccount()) ||
        matches?.call() == false) {
      return null;
    }
    return result;
  }
}
