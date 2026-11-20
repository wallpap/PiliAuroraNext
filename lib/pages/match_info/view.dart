import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/widgets/image/image_type.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/match/match_info/contest.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/match/match_info/team.dart';
import 'package:pili_aurora_next/pages/common/dyn/common_dyn_page.dart';
import 'package:pili_aurora_next/features/content_discovery/application/match_detail.dart';
import 'package:pili_aurora_next/pages/video/reply_reply/view.dart';
import 'package:pili_aurora_next/core/time/date_format.dart';
import 'package:pili_aurora_next/common/widgets/extensions/widget_ext.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/core/async/rate_limiter.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

class MatchInfoPage extends ConsumerStatefulWidget {
  const MatchInfoPage({super.key});

  @override
  ConsumerState<MatchInfoPage> createState() => _MatchInfoPageState();
}

class _MatchInfoPageState extends CommonDynPageState<MatchInfoPage> {
  @override
  late final MatchInfoController controller;

  @override
  void initState() {
    super.initState();
    controller = MatchInfoController(
      oid: int.tryParse(Get.parameters['cid'] ?? '') ?? 0,
    )..open();
  }

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  @override
  dynamic get arguments => null;

  @override
  Widget get replyButton =>
      controller.oid > 0 ? super.replyButton : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return fabAnimWrapper(
      child: SimpleScaffold(
        appBar: AppBar(title: const Text('比赛详情')),
        body: ViewSafeArea(
          child: refreshIndicator(
            onRefresh: refreshDetailsAndComments,
            child: commentPagination(
              CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  ValueListenableBuilder(
                    valueListenable: controller.infoState,
                    builder: (context, value, _) => _buildInfo(value),
                  ),
                  buildReplyHeader(),
                  replyList(),
                ],
              ),
            ),
          ),
        ).constraintWidth(),
        fab: SlideTransition(
          position: fabAnimation,
          child: fabButton,
        ),
      ),
    );
  }

  Widget _buildInfo(LoadingState<MatchContest?> infoState) {
    if (infoState is Error) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(infoState.toString()),
              TextButton(
                onPressed: controller.getMatchInfo,
                child: const Text('重试赛事详情'),
              ),
            ],
          ),
        ),
      );
    }
    if (infoState is Loading) {
      return const SliverToBoxAdapter(child: LinearProgressIndicator());
    }
    if (infoState case Success(:final response?)) {
      try {
        Widget teamInfo(MatchTeam team) {
          return Column(
            spacing: 5,
            mainAxisSize: MainAxisSize.min,
            children: [
              NetworkImgLayer(
                width: 50,
                height: 50,
                src: 'https://i1.hdslb.com${team.logo}',
                type: ImageType.emote,
              ),
              Text(team.title!),
            ],
          );
        }

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              spacing: 12,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Text(
                    '${response.season?.title ?? ''}  ${response.gameStage ?? ''}',
                  ),
                ),
                Row(
                  spacing: 20,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (response.homeId != 0)
                      Expanded(
                        child: Align(
                          alignment: const Alignment(0.8, 1),
                          child: teamInfo(response.homeTeam!),
                        ),
                      ),
                    Column(
                      spacing: 10,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (response.homeId != 0)
                          Text(
                            response.contestStatus == 1
                                ? 'VS'
                                : '${response.homeScore} : ${response.awayScore}',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: .bold,
                              letterSpacing: 1.5,
                            ),
                          )
                        else if (response.season?.logo != null)
                          NetworkImgLayer(
                            width: 50,
                            height: 50,
                            src: 'https://i1.hdslb.com${response.season!.logo}',
                            type: ImageType.emote,
                          ),
                        if (response.contestStatus == 2)
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(6),
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () =>
                                PageUtils.toLiveRoom(response.liveRoom),
                            child: const Text('看直播'),
                          )
                        else if (response.contestStatus == 3)
                          Text(
                            '${DateFormatUtils.dateFormat(response.stime)}${response.contestStatus == 3 ? ' 已结束' : ''}',
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                            ),
                          )
                        else if (response.contestStatus == 1)
                          Text(
                            DateFormatUtils.format(
                              response.stime,
                              format: DateFormat('yy-MM-dd HH:mm'),
                            ),
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                    if (response.awayId != 0)
                      Expanded(
                        child: Align(
                          alignment: const Alignment(-0.8, -1),
                          child: teamInfo(response.awayTeam!),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      } catch (_) {
        return const SliverToBoxAdapter();
      }
    }
    return const SliverToBoxAdapter();
  }

  @override
  void replyReply(BuildContext context, CommentReply replyItem, int? id) {
    ActionThrottle.run('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      Get.to(
        SimpleScaffold(
          appBar: AppBar(
            title: const Text('评论详情'),
            shape: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
          ),
          body: ViewSafeArea(
            child: VideoReplyReplyPanel(
              enableSlide: false,
              id: id,
              oid: oid,
              rpid: rpid,
              isVideoDetail: false,
              replyType: controller.replyType,
              firstFloor: replyItem,
              onUpdate: commentUpdate(),
            ),
          ).constraintWidth(),
        ),
      );
    });
  }
}
