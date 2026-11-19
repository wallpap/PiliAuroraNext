import 'package:pili_aurora_next/common/skeleton/video_reply.dart';
import 'package:pili_aurora_next/features/community/domain/comment_share_origin.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/colored_box_transition.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/simple_colored_box.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/common/slide/common_slide_page.dart';
import 'package:pili_aurora_next/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:pili_aurora_next/features/community/presentation/comment_interactions.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/utils/app_scheme.dart';
import 'package:pili_aurora_next/utils/extension/widget_ext.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/parse_string.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class VideoReplyReplyPanel extends CommonSlidePage {
  const VideoReplyReplyPanel({
    super.key,
    super.enableSlide,
    this.musicShare,
    this.id,
    required this.oid,
    required this.rpid,
    this.dialog,
    this.firstFloor,
    required this.isVideoDetail,
    required this.replyType,
    this.isNested = false,
    this.upMid,
    this.onUpdate,
  });
  final CommentShareOrigin? musicShare;
  final int? id;
  final int oid;
  final int rpid;
  final int? dialog;
  final CommentReply? firstFloor;
  final bool isVideoDetail;
  final int replyType;
  final bool isNested;
  final Int64? upMid;
  final VoidCallback? onUpdate;

  @override
  State<VideoReplyReplyPanel> createState() => _VideoReplyReplyPanelState();

  static Future<void>? toReply({
    required int oid,
    required int rootId,
    String? rpIdStr,
    required int type,
    Uri? uri,
  }) {
    final rpId = parseIntOrNull(rpIdStr);
    return Get.to(
      arguments: {
        'oid': oid,
        'rpid': rootId,
        'id': ?rpId,
        'type': type,
        'enterUri': ?uri?.toString(), // save panel
      },
      () => SimpleScaffold(
        appBar: AppBar(
          title: const Text('评论详情'),
          actions: [
            IconButton(
              tooltip: '前往',
              onPressed: uri == null
                  ? null
                  : () => PiliScheme.routePush(uri, businessId: type),
              icon: const Icon(Icons.open_in_browser),
            ),
          ],
        ),
        body: ViewSafeArea(
          child: VideoReplyReplyPanel(
            enableSlide: false,
            oid: oid,
            rpid: rootId,
            isVideoDetail: false,
            replyType: type,
            firstFloor: null,
            id: rpId,
          ),
        ).constraintWidth(),
      ),
    );
  }
}

class _VideoReplyReplyPanelState extends State<VideoReplyReplyPanel>
    with TickerProviderStateMixin, CommonSlideMixin {
  final _owner = Object();
  final _scrollController = ScrollController();
  final _listController = ListController();
  final _interactions = CommentInteractions();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  Animation<Color?>? _colorAnimation;
  ExtendedNestedScrollController? _nestedController;
  Int64? _highlight;
  late int? _pendingReply = widget.id;
  late Object _seedAccount;
  bool _showSeed = true;

  bool get isDialogue => widget.dialog != null;
  CommentsQuery get _query => (
    owner: _owner,
    target: (oid: widget.oid, type: widget.replyType),
    thread: (root: widget.rpid, reply: widget.id, dialog: widget.dialog),
  );
  Object get _source =>
      widget.replyType == 1 ? IdUtils.av2bv(widget.oid) : widget.oid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorAnimation = null;
    final controller = PrimaryScrollController.maybeOf(context);
    _nestedController = controller is ExtendedNestedScrollController
        ? controller
        : null;
  }

  @override
  void initState() {
    super.initState();
    _seedAccount = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(mainAccountProvider);
  }

  @override
  void didUpdateWidget(covariant VideoReplyReplyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.oid == widget.oid &&
        oldWidget.rpid == widget.rpid &&
        oldWidget.id == widget.id &&
        oldWidget.dialog == widget.dialog &&
        oldWidget.replyType == widget.replyType) {
      return;
    }
    _highlight = null;
    _pendingReply = widget.id;
    _seedAccount = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(mainAccountProvider);
    _showSeed = true;
  }

  @override
  void dispose() {
    _animation.dispose();
    _scrollController.dispose();
    _listController.dispose();
    super.dispose();
  }

  bool _jump(Int64 id, List<CommentReply> rows) {
    final index = rows.indexWhere((row) => row.id == id);
    if (index < 0) return false;
    _highlight = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _highlight != id) return;
      _animation.forward(from: 0);
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        final offset = _listController.getOffsetToReveal(index, 0.25);
        if (!offset.isFinite) return;
        if (_nestedController case final nested?) {
          nested.nestedPositions.last.localJumpTo(offset);
        } else if (_scrollController.hasClients) {
          _scrollController.jumpTo(offset);
        }
      } on StateError {
        // 关闭面板时滚动位置可能已脱离。
      } on FlutterError {
        // 首次快照尚未布局时没有可用位置。
      }
    });
    return true;
  }

  @override
  Widget buildPage(ThemeData theme) {
    Widget child() => enableSlide ? slideList(theme) : buildList(theme);
    return SimpleColoredBox(
      color: theme.canvasColor,
      child: MiniScaffold(
        body: widget.isVideoDetail
            ? Column(
                children: [
                  Container(
                    height: 45,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 1,
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 12, right: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(isDialogue ? '对话列表' : '评论详情'),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: Get.back,
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child()),
                ],
              )
            : child(),
      ),
    );
  }

  @override
  Widget buildList(ThemeData theme) => Consumer(
    builder: (context, ref, _) {
      final provider = commentsProvider(_query);
      final snapshot = ref.watch(provider);
      final comments = ref.read(provider.notifier);
      final account = ref.watch(mainAccountProvider);
      if (!identical(_seedAccount, account)) {
        _showSeed = false;
        _highlight = null;
        _pendingReply = null;
      }
      final root = snapshot.root ?? (_showSeed ? widget.firstFloor : null);
      final controller = _nestedController ?? _scrollController;
      final rows = snapshot.loading.dataOrNull;
      if (rows != null) {
        if (_pendingReply case final id?) {
          _pendingReply = null;
          _jump(Int64(id), rows);
        }
      }
      Future<void> reload({bool clear = false}) {
        _highlight = null;
        return comments.refresh(clear: clear);
      }

      return refreshIndicator(
        onRefresh: reload,
        isClampingScrollPhysics: widget.isNested,
        child: FeedPagination.notifications(
          dataSource: snapshot.source,
          dataRevision: snapshot,
          canLoadMore: () => snapshot.canLoadMore,
          onLoadMore: comments.loadMore,
          child: CustomScrollView(
            key: ObjectKey(controller),
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (!isDialogue) ...[
                if (root != null) _header(theme, root, comments, snapshot),
                _sortWidget(theme.colorScheme, comments, snapshot),
              ],
              _buildBody(theme.colorScheme, comments, snapshot, reload),
            ],
          ),
        ),
      );
    },
  );

  Widget _header(
    ThemeData theme,
    CommentReply firstFloor,
    Comments comments,
    CommentsState snapshot,
  ) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ReplyItemGrpc(
            replyItem: firstFloor,
            musicShare: widget.musicShare,
            replyLevel: 2,
            needDivider: false,
            onReply: (replyItem) => _interactions.compose(
              context,
              comments,
              snapshot,
              _source,
              replyItem,
            ),
            upMid: (_showSeed ? widget.upMid : null) ?? snapshot.upMid,
            onCheckReply: (item) =>
                _interactions.check(comments, _source, item),
            onUpdate: widget.onUpdate,
          ),
        ),
        SliverToBoxAdapter(
          child: Divider(
            height: 20,
            color: theme.dividerColor.withValues(alpha: 0.1),
            thickness: 6,
          ),
        ),
      ],
    );
  }

  Widget _sortWidget(
    ColorScheme colorScheme,
    Comments comments,
    CommentsState snapshot,
  ) {
    return SliverPinnedHeader(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            if (snapshot.count >= 0)
              Text(
                '相关回复共${NumUtils.numFormat(snapshot.count)}条',
                style: const TextStyle(fontSize: 13),
              )
            else
              const SizedBox.shrink(),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: () {
                if (snapshot.busy) return;
                _highlight = null;
                _interactions.toggleSort(comments, snapshot);
              },
              icon: Icon(Icons.sort, size: 16, color: colorScheme.secondary),
              label: Text(
                snapshot.sort.label,
                style: TextStyle(fontSize: 13, color: colorScheme.secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    Comments comments,
    CommentsState snapshot,
    Future<void> Function({bool clear}) reload,
  ) {
    return switch (snapshot.loading) {
      Loading() => const SliverPrototypeExtentList(
        prototypeItem: VideoReplySkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 8,
          child: VideoReplySkeleton(),
        ),
      ),
      Success(:final response) when response.isEmpty => HttpError(
        errMsg:
            snapshot.pageError?.errMsg ??
            (Pref.minimumReplyUserLevel > 0 ? '暂无符合等级条件的评论' : '还没有评论'),
        btnText: snapshot.hasMore ? '继续加载' : null,
        onReload: snapshot.hasMore
            ? () => comments.loadMore(retry: true)
            : () => reload(clear: true),
      ),
      Success(:final response) => SuperSliverList.builder(
        listController: _listController,
        itemBuilder: (context, index) {
          if (index == response.length) {
            if (snapshot.pageError case final error?) {
              return TextButton(
                onPressed: () => comments.loadMore(retry: true),
                child: Text(error.errMsg ?? '加载失败，点击重试'),
              );
            }
            return Container(
              height: 125,
              alignment: Alignment.center,
              margin: .only(bottom: MediaQuery.viewPaddingOf(context).bottom),
              child: Text(
                !snapshot.hasMore ? '没有更多了' : '加载中...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
            );
          }
          final child = _replyItem(
            context,
            response[index],
            comments,
            snapshot,
          );
          if (_highlight == response[index].id) {
            return ColoredBoxTransition(
              color: _colorAnimation ??= _animation.drive(
                ColorTween(
                  begin: colorScheme.onInverseSurface,
                  end: colorScheme.surface,
                  // 前0.8s不变, 后0.2s开始动画
                ).chain(CurveTween(curve: const Interval(0.8, 1.0))),
              ),
              child: child,
            );
          }
          return child;
        },
        itemCount: response.length + 1,
      ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: () => reload(clear: true),
      ),
    };
  }

  Widget _replyItem(
    BuildContext context,
    CommentReply replyItem,
    Comments comments,
    CommentsState snapshot,
  ) {
    return ReplyItemGrpc(
      replyItem: replyItem,
      musicShare: widget.musicShare,
      replyLevel: isDialogue ? 3 : 2,
      onReply: (item) =>
          _interactions.compose(context, comments, snapshot, _source, item),
      onDelete: (item, _) => comments.remove(item, null),
      upMid: snapshot.upMid,
      showDialogue: () => MiniScaffold.of(context).showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => VideoReplyReplyPanel(
          oid: replyItem.oid.toInt(),
          rpid: replyItem.root.toInt(),
          dialog: replyItem.dialog.toInt(),
          replyType: widget.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
        ),
      ),
      jumpToDialogue: () {
        if (_jump(replyItem.parent, snapshot.loading.dataOrNull ?? const [])) {
          setState(() {});
        } else {
          SmartDialog.showToast('评论可能已被删除');
        }
      },
      onCheckReply: (item) => _interactions.check(comments, _source, item),
    );
  }
}
