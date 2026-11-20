import 'package:pili_aurora_next/common/skeleton/video_reply.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_floating_header.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/common/fab_mixin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_interactions.dart';
import 'package:pili_aurora_next/features/community/application/comments/comment_preferences.dart';
import 'package:pili_aurora_next/pages/video/reply/vote/reply_vote_item.dart';
import 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_video_tools.dart';
import 'package:pili_aurora_next/pages/video/reply_reply/view.dart';
import 'package:pili_aurora_next/services/feedback/feed_back.dart';
import 'package:pili_aurora_next/core/async/rate_limiter.dart';
import 'package:material_ui/material_ui.dart';

class VideoReplyPanel extends ConsumerStatefulWidget {
  const VideoReplyPanel({
    super.key,
    this.replyLevel = 1,
    required this.videoTools,
    required this.isNested,
    required this.query,
    required this.sourceId,
    required this.writeTarget,
    required this.targetIsCurrent,
    required this.scrollController,
  });

  final int replyLevel;
  final CommentVideoTools videoTools;
  final bool isNested;
  final CommentsQuery query;
  final Object sourceId;
  final CommentTarget writeTarget;
  final bool Function() targetIsCurrent;
  final ScrollController scrollController;

  @override
  ConsumerState<VideoReplyPanel> createState() => _VideoReplyPanelState();
}

class _VideoReplyPanelState extends ConsumerState<VideoReplyPanel>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        FabMixin {
  late ColorScheme colorScheme;
  final _interactions = CommentInteractions();
  Comments get _comments => ref.read(commentsProvider(widget.query).notifier);
  CommentsState get _snapshot => ref.read(commentsProvider(widget.query));
  void _compose(CommentReply? item, {int? oid, int? replyType, int? index}) =>
      _interactions.compose(
        context,
        _comments,
        _snapshot,
        widget.sourceId,
        item,
        oid: oid,
        replyType: replyType,
        targetIsCurrent: widget.targetIsCurrent,
        videoTools: widget.videoTools,
      );

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = ColorScheme.of(context);
    bottom = MediaQuery.viewPaddingOf(context).bottom;
  }

  late double bottom;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(commentsProvider(widget.query));
    return fabAnimWrapper(
      child: refreshIndicator(
        onRefresh: _comments.refresh,
        isClampingScrollPhysics: widget.isNested,
        child: ScaffoldLayout(
          body: FeedPagination.notifications(
            dataSource: state.source,
            dataRevision: state,
            canLoadMore: () => state.canLoadMore,
            onLoadMore: _comments.loadMore,
            child: CustomScrollView(
              controller: widget.isNested ? null : widget.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              key: const PageStorageKey(_VideoReplyPanelState),
              slivers: [
                SliverFloatingHeaderWidget(
                  backgroundColor: colorScheme.surface,
                  child: Padding(
                    padding: const .fromLTRB(12, 2.5, 6, 2.5),
                    child: Row(
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Text(
                          state.sort.desc,
                          style: const TextStyle(fontSize: 13),
                        ),
                        TextButton.icon(
                          style: Style.buttonStyle,
                          onPressed: () =>
                              _interactions.toggleSort(_comments, state),
                          icon: Icon(
                            Icons.sort,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                          label: Text(
                            state.sort.descShort,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildBody(state),
              ],
            ),
          ),
          fab: SlideTransition(
            position: fabAnimation,
            child: Padding(
              padding: .only(
                right: kFloatingActionButtonMargin,
                bottom: kFloatingActionButtonMargin + bottom,
              ),
              child: FloatingActionButton(
                heroTag: null,
                onPressed: () {
                  feedBack();
                  _compose(
                    null,
                    oid: widget.writeTarget.oid,
                    replyType: widget.query.target.type,
                  );
                },
                tooltip: '发表评论',
                child: const Icon(Icons.reply),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(CommentsState state) {
    switch (state.loading) {
      case Loading():
        return const SliverPrototypeExtentList(
          prototypeItem: VideoReplySkeleton(),
          delegate: SliverSingleChildDelegate(
            count: 5,
            child: VideoReplySkeleton(),
          ),
        );
      case Success(:final response):
        if (response.isNotEmpty) {
          var count = response.length + 1;
          final voteCard = state.vote;
          final hasVote = voteCard != null;
          if (hasVote) {
            count++;
          }
          return SliverList.builder(
            itemBuilder: (context, index) {
              if (hasVote) {
                if (index == 0) {
                  return buildVoteCard(context, colorScheme, voteCard);
                } else {
                  index--;
                }
              }
              if (index == response.length) {
                if (state.pageError case final error?) {
                  return TextButton(
                    onPressed: () => _comments.loadMore(retry: true),
                    child: Text('$error'),
                  );
                }
                return Container(
                  height: 125,
                  alignment: .center,
                  margin: .only(bottom: bottom),
                  child: Text(
                    !state.hasMore ? '没有更多了' : '加载中...',
                    textAlign: .center,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                );
              } else {
                return ReplyItemGrpc(
                  replyItem: response[index],
                  replyLevel: widget.replyLevel,
                  replyReply: replyReply,
                  onReply: _compose,
                  onDelete: (item, subIndex) =>
                      _comments.remove(item, subIndex),
                  upMid: state.upMid,
                  videoTools: widget.videoTools,
                  onCheckReply: (item) =>
                      _interactions.check(_comments, widget.sourceId, item),
                  onToggleTop: (item) => _interactions.togglePinned(
                    context,
                    _comments,
                    item,
                    target: widget.writeTarget,
                  ),
                );
              }
            },
            itemCount: count,
          );
        }

        final child = HttpError(
          errMsg: CommentPreferences.minimumUserLevel > 0
              ? '暂无符合等级条件的评论'
              : '还没有评论',
          btnText: state.hasMore ? '继续加载' : null,
          onReload: state.hasMore
              ? () => _comments.loadMore(retry: true)
              : () => _comments.refresh(clear: true),
        );
        if (state.vote case final voteCard?) {
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: buildVoteCard(context, colorScheme, voteCard),
              ),
              child,
            ],
          );
        }
        return child;
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: () => _comments.refresh(clear: true),
        );
    }
  }

  // 展示二级回复
  void replyReply(CommentReply replyItem, int? id) {
    ActionThrottle.run('replyReply', const Duration(milliseconds: 500), () {
      final comments = _comments;
      final current = comments.capture();
      final targetIsCurrent = widget.targetIsCurrent;
      final state = _snapshot;
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      MiniScaffold.of(context).showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => VideoReplyReplyPanel(
          videoTools: widget.videoTools,
          id: id,
          oid: oid,
          rpid: rpid,
          firstFloor: replyItem.replyControl.isNote ? null : replyItem,
          replyType: widget.query.target.type,
          isVideoDetail: true,
          isNested: widget.isNested,
          upMid: state.upMid,
          onUpdate: () {
            if (mounted && targetIsCurrent() && current()) comments.touch();
          },
        ),
      );
    });
  }
}
