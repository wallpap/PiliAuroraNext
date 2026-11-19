import 'package:pili_aurora_next/common/skeleton/video_reply.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_floating_header.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/common/fab_mixin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_interactions.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:pili_aurora_next/pages/video/reply_reply/view.dart';
import 'package:pili_aurora_next/utils/extension/widget_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/rate_limiter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MainReplyPage extends ConsumerStatefulWidget {
  const MainReplyPage({super.key});

  @override
  ConsumerState<MainReplyPage> createState() => _MainReplyPageState();

  static void toMainReplyPage({
    required int oid,
    required int replyType,
  }) {
    Get.toNamed(
      '/mainReply',
      arguments: {
        'oid': oid,
        'replyType': replyType,
      },
    );
  }
}

class _MainReplyPageState extends ConsumerState<MainReplyPage>
    with SingleTickerProviderStateMixin, BaseFabMixin, FabMixin {
  final _interactions = CommentInteractions();
  late final CommentsQuery _query;
  Comments get _comments => ref.read(commentsProvider(_query).notifier);
  CommentsState get _snapshot => ref.read(commentsProvider(_query));

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map;
    _query = (
      owner: Object(),
      thread: null,
      target: (oid: args['oid'] as int, type: args['replyType'] as int),
    );
  }

  void _compose(ReplyInfo? item, {int? oid, int? replyType, int? index}) =>
      _interactions.compose(
        context,
        _comments,
        _snapshot,
        _query.target.oid,
        item,
        oid: oid,
        replyType: replyType,
      );

  late EdgeInsets padding;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final state = ref.watch(commentsProvider(_query));
    return SimpleScaffold(
      appBar: AppBar(title: const Text('查看评论')),
      body: fabAnimWrapper(
        child: refreshIndicator(
          onRefresh: _comments.refresh,
          child: Padding(
            padding: EdgeInsets.only(
              left: padding.left,
              right: padding.right,
            ),
            child: FeedPagination.notifications(
              dataSource: state.source,
              dataRevision: state,
              canLoadMore: () => state.canLoadMore,
              onLoadMore: _comments.loadMore,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  buildReplyHeader(colorScheme, state),
                  _buildBody(colorScheme, state),
                ],
              ),
            ),
          ),
        ).constraintWidth(),
      ),
      fab: SlideTransition(
        position: fabAnimation,
        child: Padding(
          padding: .only(
            right: kFloatingActionButtonMargin + padding.right,
            bottom: kFloatingActionButtonMargin + padding.bottom,
          ),
          child: FloatingActionButton(
            heroTag: null,
            onPressed: () {
              try {
                feedBack();
                _compose(
                  null,
                  oid: _query.target.oid,
                  replyType: _query.target.type,
                );
              } catch (_) {}
            },
            tooltip: '评论',
            child: const Icon(Icons.reply),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    CommentsState state,
  ) {
    return switch (state.loading) {
      Loading() => const SliverPrototypeExtentList(
        prototypeItem: VideoReplySkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 10,
          child: VideoReplySkeleton(),
        ),
      ),
      Success(:final response) =>
        response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length + 1,
                itemBuilder: (context, index) {
                  if (index == response.length) {
                    if (state.pageError case final error?) {
                      return TextButton(
                        onPressed: () => _comments.loadMore(retry: true),
                        child: Text('$error'),
                      );
                    }
                    return Container(
                      alignment: Alignment.center,
                      margin: EdgeInsets.only(bottom: padding.bottom),
                      height: 125,
                      child: Text(
                        !state.hasMore ? '没有更多了' : '加载中...',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    );
                  } else {
                    return ReplyItemGrpc(
                      replyItem: response[index],
                      replyLevel: 1,
                      replyReply: (replyItem, id) =>
                          replyReply(context, replyItem, id, colorScheme),
                      onReply: _compose,
                      onDelete: (item, subIndex) =>
                          _comments.remove(item, subIndex),
                      upMid: state.upMid,
                      onCheckReply: (item) => _interactions.check(
                        _comments,
                        _query.target.oid,
                        item,
                      ),
                      onToggleTop: (item) =>
                          _interactions.togglePinned(context, _comments, item),
                    );
                  }
                },
              )
            : HttpError(
                errMsg: Pref.minimumReplyUserLevel > 0
                    ? '暂无符合等级条件的评论'
                    : '还没有评论',
                btnText: state.hasMore ? '继续加载' : null,
                onReload: state.hasMore
                    ? () => _comments.loadMore(retry: true)
                    : () => _comments.refresh(clear: true),
              ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: () => _comments.refresh(clear: true),
      ),
    };
  }

  Widget buildReplyHeader(ColorScheme colorScheme, CommentsState state) {
    final secondary = colorScheme.secondary;
    return SliverFloatingHeaderWidget(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(
              '${state.count == -1 ? 0 : NumUtils.numFormat(state.count)}条回复',
            ),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: () => _interactions.toggleSort(_comments, state),
              icon: Icon(Icons.sort, size: 16, color: secondary),
              label: Text(
                state.sort.descShort,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void replyReply(
    BuildContext context,
    ReplyInfo replyItem,
    int? id,
    ColorScheme colorScheme,
  ) {
    ActionThrottle.run('replyReply', const Duration(milliseconds: 500), () {
      final comments = _comments;
      final current = comments.capture();
      final state = _snapshot;
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      Get.to(
        SimpleScaffold(
          appBar: AppBar(
            title: const Text('评论详情'),
            shape: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.1),
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
              replyType: _query.target.type,
              firstFloor: replyItem,
              upMid: state.upMid,
              onUpdate: () {
                if (current()) comments.touch();
              },
            ),
          ).constraintWidth(),
        ),
        routeName: 'dynamicDetail-Copy',
      );
    });
  }
}
