import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_interactions.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/common/skeleton/video_reply.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/enum_with_label.dart';
import 'package:pili_aurora_next/pages/article/widgets/sliver_list.dart';
import 'package:pili_aurora_next/pages/common/dyn/common_dyn_controller.dart';
import 'package:pili_aurora_next/pages/common/fab_mixin.dart';
import 'package:pili_aurora_next/pages/video/reply/vote/reply_vote_item.dart';
import 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:pili_aurora_next/pages/video/reply_reply/view.dart';
import 'package:pili_aurora_next/utils/extension/num_ext.dart';
import 'package:pili_aurora_next/utils/extension/size_ext.dart';
import 'package:pili_aurora_next/utils/feed_back.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/rate_limiter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum DynType implements EnumWithLabel {
  repost('转发'),
  reply('评论'),
  like('赞');

  @override
  final String label;
  const DynType(this.label);
}

abstract class CommonDynPageState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T>
    with
        SingleTickerProviderStateMixin<T>,
        BaseFabMixin,
        FabMixin,
        CommonDynPageMixin<T> {}

abstract class CommonDynPageMultiState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T>
    with
        TickerProviderStateMixin<T>,
        BaseFabMixin,
        FabMixin,
        CommonDynPageMixin<T> {
  late final TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(
      length: DynType.values.length,
      initialIndex: DynType.reply.index,
      vsync: this,
    );
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }
}

mixin CommonDynPageMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, TickerProvider, BaseFabMixin<T>, FabMixin<T> {
  CommonDynController get controller;
  bool get isArticle => false;

  bool get horizontalPreview => !isPortrait && controller.horizontalPreview;

  dynamic get arguments;

  late ThemeData theme;
  late EdgeInsets padding;
  late bool isPortrait;
  late double maxWidth;
  late double maxHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    theme = Theme.of(context);
    maxWidth = size.width;
    maxHeight = size.height;
    isPortrait = size.isPortrait;
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  bool onNotification(UserScrollNotification notification) {
    if (notification.metrics.axisDirection == .down) {
      return super.onNotification(notification);
    }
    return false;
  }

  final _commentOwner = Object();
  final _interactions = CommentInteractions();
  CommentsQuery? get _commentQuery {
    final target = controller.commentSource.value.dataOrNull;
    return target == null
        ? null
        : (owner: _commentOwner, target: target, thread: null);
  }

  Widget commentBuilder(Widget Function(Comments?, CommentsState?) builder) =>
      Obx(() {
        final query = _commentQuery;
        return Consumer(
          builder: (context, ref, _) {
            final provider = query == null ? null : commentsProvider(query);
            return builder(
              provider == null ? null : ref.read(provider.notifier),
              provider == null ? null : ref.watch(provider),
            );
          },
        );
      });

  CommentsState? get commentSnapshot {
    final query = _commentQuery;
    return query == null ? null : ref.read(commentsProvider(query));
  }

  Future<void> refreshComments({bool clear = false}) async {
    final query = _commentQuery;
    if (query != null) {
      await ref.read(commentsProvider(query).notifier).refresh(clear: clear);
    }
  }

  Future<void> refreshDetailsAndComments({bool parallel = true}) async {
    final query = _commentQuery;
    final details = controller.onReload();
    if (parallel) {
      await Future.wait([details, if (query != null) refreshComments()]);
    } else {
      await details;
      if (mounted && query != null && query == _commentQuery) {
        await refreshComments();
      }
    }
  }

  Widget commentPagination(Widget child) => commentBuilder(
    (comments, snapshot) => FeedPagination.notifications(
      dataSource: snapshot?.source,
      dataRevision: snapshot,
      canLoadMore: () => snapshot?.canLoadMore ?? false,
      onLoadMore: () async {
        await comments?.loadMore();
      },
      child: child,
    ),
  );

  Widget buildReplyHeader() {
    final secondary = theme.colorScheme.secondary;
    return SliverPinnedHeader(
      backgroundColor: theme.colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: commentBuilder((comments, snapshot) {
          final count = snapshot?.count ?? -1;
          return Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              Text(
                '${NumUtils.numFormat(count >= 0 ? count : (controller.count < 0 ? 0 : controller.count))}条回复',
              ),
              TextButton.icon(
                style: Style.buttonStyle,
                onPressed: snapshot == null || comments == null
                    ? null
                    : () => toggleCommentSort(comments, snapshot),
                icon: Icon(Icons.sort, size: 16, color: secondary),
                label: Text(
                  (snapshot?.sort ?? Pref.replySortType).descShort,
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  void toggleCommentSort(Comments comments, CommentsState state) =>
      _interactions.toggleSort(comments, state);

  Widget replyList() => Obx(() {
    final source = controller.commentSource.value;
    return commentBuilder(
      (comments, snapshot) => _replyList(source, comments, snapshot),
    );
  });

  Widget _replyList(
    LoadingState<CommentTarget?> source,
    Comments? comments,
    CommentsState? snapshot,
  ) {
    final LoadingState<List<ReplyInfo>> loading =
        snapshot?.loading ??
        switch (source) {
          Error error => error,
          Success() => const Success(<ReplyInfo>[]),
          _ => LoadingState<List<ReplyInfo>>.loading(),
        };
    switch (loading) {
      case Loading():
        return const SliverPrototypeExtentList(
          prototypeItem: VideoReplySkeleton(),
          delegate: SliverSingleChildDelegate(
            count: 12,
            child: VideoReplySkeleton(),
          ),
        );
      case Success(:final response):
        if (response.isNotEmpty) {
          var count = response.length + 1;
          final voteCard = snapshot?.vote;
          final hasVote = voteCard != null;
          if (hasVote) {
            count++;
          }
          return ArticleSliverList.builder(
            itemCount: count,
            isArticle: isArticle,
            itemBuilder: (context, index) {
              if (hasVote) {
                if (index == 0) {
                  return buildVoteCard(context, theme.colorScheme, voteCard);
                } else {
                  index--;
                }
              }
              if (index == response.length) {
                if (snapshot?.pageError case final error?) {
                  return TextButton(
                    onPressed: () => comments?.loadMore(retry: true),
                    child: Text(error.errMsg ?? '加载失败，点击重试'),
                  );
                }
                return Container(
                  alignment: Alignment.center,
                  margin: EdgeInsets.only(bottom: padding.bottom),
                  height: 125,
                  child: Text(
                    snapshot?.hasMore != true ? '没有更多了' : '加载中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                );
              } else {
                return ReplyItemGrpc(
                  replyItem: response[index],
                  replyLevel: 1,
                  replyReply: (item, id) => replyReply(context, item, id),
                  onReply: (item, {oid, replyType, index}) => _compose(
                    this.context,
                    item,
                    oid: oid,
                    replyType: replyType,
                  ),
                  onDelete: (item, subIndex) =>
                      comments?.remove(item, subIndex),
                  upMid: snapshot?.upMid,
                  onViewImage: hideFab,
                  onCheckReply: (item) {
                    if (comments != null) {
                      _interactions.check(comments, controller.sourceId, item);
                    }
                  },
                  onToggleTop: (item) async {
                    if (comments != null) {
                      await _interactions.togglePinned(context, comments, item);
                    }
                  },
                );
              }
            },
          );
        }

        final child = httpError(
          errMsg:
              snapshot?.pageError?.errMsg ??
              (snapshot == null
                  ? '该音乐暂不支持评论'
                  : Pref.minimumReplyUserLevel > 0
                  ? '暂无符合等级条件的评论'
                  : '还没有评论'),
          btnText: snapshot?.hasMore == true ? '继续加载' : null,
          onReload: snapshot == null
              ? controller.onReload
              : snapshot.hasMore
              ? () => comments?.loadMore(retry: true)
              : () => refreshComments(clear: true),
        );
        if (snapshot?.vote case final voteCard?) {
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: buildVoteCard(context, theme.colorScheme, voteCard),
              ),
              child,
            ],
          );
        }
        return child;
      case Error(:final errMsg):
        return httpError(
          errMsg: errMsg,
          onReload: snapshot == null
              ? controller.onReload
              : () => refreshComments(clear: true),
        );
    }
  }

  Widget httpError({String? errMsg, String? btnText, VoidCallback? onReload}) =>
      HttpError(
        errMsg: errMsg,
        btnText: btnText,
        onReload: onReload,
      );

  void replyReply(BuildContext context, ReplyInfo replyItem, int? id) {
    ActionThrottle.run('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      Widget replyReplyPage({bool showBackBtn = true}) {
        final child = ViewSafeArea(
          left: showBackBtn,
          right: showBackBtn,
          child: VideoReplyReplyPanel(
            enableSlide: false,
            id: id,
            oid: oid,
            rpid: rpid,
            isVideoDetail: !showBackBtn,
            replyType: controller.replyType,
            firstFloor: replyItem,
            upMid: commentSnapshot?.upMid,
            onUpdate: commentUpdate(),
          ),
        );
        if (showBackBtn) {
          return SimpleScaffold(
            appBar: AppBar(
              title: const Text('评论详情'),
              shape: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
            body: child,
          );
        }
        return child;
      }

      if (isPortrait) {
        Get.to(
          replyReplyPage,
          routeName: 'dynamicDetail-Copy',
          arguments: arguments,
        );
      } else {
        final scaffoldState = MiniScaffold.maybeOf(context);
        if (scaffoldState != null) {
          hideFab();
          scaffoldState.showBottomSheet(
            constraints: const BoxConstraints(),
            (context) => replyReplyPage(showBackBtn: false),
          );
        } else {
          Get.to(
            replyReplyPage,
            routeName: 'dynamicDetail-Copy',
            arguments: arguments,
          );
        }
      }
    });
  }

  VoidCallback? commentUpdate() {
    final query = _commentQuery;
    if (query == null) return null;
    final comments = ref.read(commentsProvider(query).notifier);
    final current = comments.capture();
    return () {
      if (mounted && query == _commentQuery && current()) comments.touch();
    };
  }

  void _compose(
    BuildContext context,
    ReplyInfo? item, {
    int? oid,
    int? replyType,
  }) {
    final query = _commentQuery;
    if (query == null) return;
    final provider = commentsProvider(query);
    _interactions.compose(
      context,
      ref.read(provider.notifier),
      ref.read(provider),
      controller.sourceId,
      item,
      oid: oid,
      replyType: replyType,
      targetIsCurrent: () => mounted && query == _commentQuery,
    );
  }

  Widget ratioWidget(double maxWidth) => IconButton(
    tooltip: '页面比例调节',
    onPressed: () => showDialog(
      context: context,
      builder: (context) => Align(
        alignment: Alignment.topRight,
        child: Container(
          margin: const EdgeInsets.only(top: 56, right: 16),
          width: maxWidth / 4,
          height: 32,
          child: Builder(
            builder: (context) => Slider(
              min: 1,
              max: 100,
              value: controller.ratio.first,
              onChanged: (value) {
                if (value >= 10 && value <= 90) {
                  value = value.toPrecision(2);
                  controller.ratio
                    ..[0] = value
                    ..[1] = 100 - value;

                  (context as Element).markNeedsBuild();
                  setState(() {});
                }
              },
              onChangeEnd: (_) => GStorage.setting.put(
                SettingBoxKey.dynamicDetailRatio,
                controller.ratio,
              ),
            ),
          ),
        ),
      ),
    ),
    icon: const Icon(CustomIcons.splitscreen_rotate_90, size: 19),
  );

  Widget get fabButton => Padding(
    padding: .only(
      right: kFloatingActionButtonMargin + padding.right,
      bottom: kFloatingActionButtonMargin + padding.bottom,
    ),
    child: replyButton,
  );

  Widget get replyButton => FloatingActionButton(
    heroTag: null,
    onPressed: () {
      feedBack();
      _compose(context, null);
    },
    tooltip: '评论',
    child: const Icon(Icons.reply),
  );
}
