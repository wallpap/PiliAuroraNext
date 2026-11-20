import 'dart:async';
import 'dart:math';

import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/flutter/dyn_tab_bar.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/flutter/text_field/controller.dart';
import 'package:pili_aurora_next/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:pili_aurora_next/common/widgets/pair.dart';
import 'package:pili_aurora_next/common/widgets/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_behavior.dart'
    show NoOverscrollIndicator;
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show ReloadMixin, ReloadScrollPhysics, platformAlwaysClampingPhysics;
import 'package:pili_aurora_next/common/widgets/sliver/sliver_floating_header.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_to_box_adapter.dart';
import 'package:pili_aurora_next/common/widgets/tap_region_surface.dart';
import 'package:pili_aurora_next/common/service_urls.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/reply/reply_option_type.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart';
import 'package:pili_aurora_next/pages/common/dyn/common_dyn_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_activity.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_details.dart';
import 'package:pili_aurora_next/features/community/presentation/dynamic_like_action.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/pages/common/dyn/like_list/view.dart';
import 'package:pili_aurora_next/pages/common/dyn/repost_list/view.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/author_panel.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:pili_aurora_next/pages/dynamics_create/view.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_page_detail.dart';
import 'package:pili_aurora_next/pages/dynamics_repost/view.dart';
import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/application/comments/comment_preferences.dart';

const Set<TargetPlatform> _kDesktopPlatforms = <TargetPlatform>{
  TargetPlatform.windows,
};

class DynamicDetailPage extends ConsumerStatefulWidget {
  const DynamicDetailPage({super.key});

  @override
  ConsumerState<DynamicDetailPage> createState() => _DynamicDetailPageState();
}

class _DynamicDetailPageState extends CommonDynPageMultiState<DynamicDetailPage>
    with ReloadMixin {
  @override
  late final DynamicDetailController controller;
  final _activityOwner = Object();
  final _openingOwner = AccountScope.capture();
  DynamicActivityQuery get _activityQuery =>
      (owner: _activityOwner, id: controller.dynItem.idStr.toString());

  final _isRefreshing = ValueNotifier(false);

  void _stopRefresh() {
    if (!mounted) return;
    _isRefreshing.value = false;
  }

  void _onRefresh(Future<void> future) {
    _isRefreshing.value = true;
    future.whenComplete(_stopRefresh);
  }

  @override
  dynamic get arguments => {'item': controller.dynItem};

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final item = args['item'] as DynamicItemModel;
    if (args['viewComment'] ?? false) {
      WidgetsBinding.instance.addPostFrameCallback(_jumpToComment);
    }
    final stat = item.modules.moduleStat;
    controller = DynamicDetailController(
      ref.read(dynamicDetailsProvider),
      count: stat?.comment?.count ?? -1,
      onFeedback: SmartDialog.showToast,
      onScrollReset: () => reload = true,
    )..dynItem = item;
    controller.open();
  }

  ScrollableState? _scrollable;
  Timer? _editRefresh;

  @override
  void dispose() {
    controller.refreshComments = null;
    controller.close();
    _isRefreshing.dispose();
    _editRefresh?.cancel();
    _scrollable = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    controller.refreshComments = () => refreshComments(clear: true);
    return SelectionTapRegionSurface(
      /// apply `lib/scripts/scrollable.patch`
      isScrolling: () => _scrollable?.shouldIgnorePointer ?? false,
      child: SimpleScaffold(
        appBar: _buildAppBar(),
        body: Padding(
          padding: EdgeInsets.only(left: padding.left, right: padding.right),
          child: _buildBody(),
        ),
        fab: SlideTransition(
          position: fabAnimation,
          child: _buildBottom(),
        ),
      ),
    );
  }

  void _onEdit() {
    final item = controller.dynItem;
    List<RichTextItem>? items;
    final moduleDynamic = item.modules.moduleDynamic;
    final desc = moduleDynamic?.desc;
    final opus = moduleDynamic?.major?.opus;

    Pair<int, String>? topic;
    if (moduleDynamic?.topic case final t?) {
      try {
        topic = Pair(first: t.id!, second: t.name!);
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }

    final richTextNodes = desc?.richTextNodes ?? opus?.summary?.richTextNodes;
    if (richTextNodes != null && richTextNodes.isNotEmpty) {
      items = <RichTextItem>[];
      final buffer = StringBuffer();
      try {
        for (final e in richTextNodes) {
          if (e.type == 'RICH_TEXT_NODE_TYPE_EMOJI') {
            items.add(
              RichTextItem(
                text: Style.placeHolder,
                rawText: e.origText,
                type: .emoji,
                range: TextRange(
                  start: buffer.length,
                  end: buffer.length + Style.placeHolder.length,
                ),
                emote: Emote(
                  url: e.emoji!.url!,
                  width: 22,
                ),
              ),
            );
            buffer.write(Style.placeHolder);
            continue;
          }
          final range = TextRange(
            start: buffer.length,
            end: buffer.length + e.origText!.length,
          );
          final item = switch (e.type) {
            'RICH_TEXT_NODE_TYPE_AT' => RichTextItem(
              text: e.origText!,
              type: .at,
              range: range,
              id: e.rid,
            ),
            'RICH_TEXT_NODE_TYPE_BV' ||
            'RICH_TEXT_NODE_TYPE_TOPIC' ||
            'RICH_TEXT_NODE_TYPE_LOTTERY' ||
            'RICH_TEXT_NODE_TYPE_VIEW_PICTURE' => RichTextItem(
              text: e.origText!,
              type: .common,
              range: range,
              id: e.rid,
            ),
            'RICH_TEXT_NODE_TYPE_VOTE' => RichTextItem(
              text: e.origText!,
              type: .vote,
              range: range,
              id: e.rid,
            ),
            _ => RichTextItem(
              text: e.origText!,
              range: range,
            ),
          };
          items.add(item);
          buffer.write(e.origText!);
        }

        bool isValid = true;
        int cursor = 0;
        for (final e in items) {
          final range = e.range;
          if (range.start == cursor) {
            cursor = range.end;
          } else {
            isValid = false;
            break;
          }
        }
        assert(isValid);
      } catch (e) {
        if (kDebugMode) rethrow;
      }
    } else {
      final text = desc?.text ?? opus?.summary?.text;
      if (text != null && text.isNotEmpty) {
        items = [
          RichTextItem.fromStart(text),
        ];
      }
    }
    ReplyOptionType? replyOption;
    if (commentSnapshot?.loading case Error(:final code)) {
      if (code == 12061 || code == 12002) {
        replyOption = .close;
      }
    }
    final owner = AccountScope.capture();
    bool isCurrent() =>
        mounted &&
        !controller.isClosed &&
        owner.isCurrent &&
        identical(item, controller.dynItem);
    CreateDynPanel.onCreateDyn(
      context,
      title: opus?.title,
      items: items,
      pics: opus?.pics,
      topic: topic,
      replyOption: replyOption ?? .allow,
      isPrivate: item.modules.moduleAuthor?.badgeText != null,
      editConfig: (
        dynId: item.idStr,
        repostDynId: item.orig?.idStr,
      ),
      onSuccess: () {
        if (!isCurrent()) return;
        _editRefresh?.cancel();
        _editRefresh = Timer(
          const Duration(milliseconds: 500),
          () async {
            if (!isCurrent()) return;
            final res = await ref
                .read(dynamicDetailsProvider)
                .load(owner.account, item.idStr);
            if (res case Success(:final response)) {
              if (isCurrent()) {
                controller.dynItem = response;
                setState(() {});
              }
            }
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    title: Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ListenableBuilder(
        listenable: controller.showTitle,
        builder: (context, _) {
          final showTitle = controller.showTitle.value;
          return AnimatedOpacity(
            opacity: showTitle ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !showTitle,
              child: AuthorPanel(
                item: controller.dynItem,
                isDetail: true,
                onSetPubSetting: controller.onSetPubSetting,
                onEdit: _onEdit,
                onSetReplySubject: controller.onSetReplySubject,
              ),
            ),
          );
        },
      ),
    ),
    actions: isPortrait
        ? null
        : [ratioWidget(maxWidth), const SizedBox(width: 16)],
  );

  Widget _buildTabBar() {
    return Consumer(
      builder: (context, ref, _) {
        final query = _activityQuery;
        ref.watch(mainAccountProvider);
        final sameAccount = _openingOwner.isCurrent;
        final stat = controller.dynItem.modules.moduleStat;
        final repostCount =
            ref.watch(dynamicRepostsProvider(query)).metadata?.total ??
            (sameAccount ? stat?.forward?.count ?? -1 : -1);
        final likeCount =
            ref.watch(dynamicLikesProvider(query)).metadata?.total ??
            (sameAccount ? stat?.like?.count ?? -1 : -1);
        Widget label(DynType type, int count) => Text(
          '${type.label}${count < 0 ? '' : ' ${NumUtils.numFormat(count)}'}',
        );
        return SizedBox(
          height: 40,
          child: DynTabBar(
            padding: .zero,
            // isScrollable: true,
            indicatorSize: .tab,
            tabAlignment: .start,
            controller: tabController,
            labelPadding: const .symmetric(horizontal: 12),
            dividerColor: theme.colorScheme.outline.withValues(alpha: 0.1),
            onTap: (value) {
              if (!tabController.indexIsChanging) {
                final positions = PrimaryScrollController.of(context).positions;
                if (positions.length == 1) {
                  final postion = positions.single;
                  if (postion.pixels >= postion.maxScrollExtent) {
                    postion.jumpTo(postion.pixels);
                  }
                  switch (value) {
                    case 0:
                      _onRefresh(
                        ref
                            .read(dynamicRepostsProvider(query).notifier)
                            .onRefresh(),
                      );
                    case 1:
                      _onRefresh(refreshDynamicComments());
                    case 2:
                      _onRefresh(
                        ref
                            .read(dynamicLikesProvider(query).notifier)
                            .onRefresh(),
                      );
                  }
                } else if (positions.length > 1) {
                  positions.elementAt(1).jumpTo(0);
                }
              }
            },
            tabs: DynType.values
                .map(
                  (e) => Tab(
                    child: e == DynType.reply
                        ? commentBuilder(
                            (_, snapshot) => label(
                              e,
                              (snapshot?.count ?? -1) >= 0
                                  ? snapshot!.count
                                  : controller.count,
                            ),
                          )
                        : label(
                            e,
                            e == DynType.repost ? repostCount : likeCount,
                          ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> refreshDynamicComments() =>
      controller.commentSource.value.dataOrNull == null
      ? controller.onReload()
      : refreshComments();

  Widget _buildTabBody([bool isPortrait = true]) {
    Widget reply = commentPagination(
      CustomScrollView(
        key: const PageStorageKey(DynType.reply),
        physics: ReloadScrollPhysics(
          controller: this,
          parent: isPortrait ? platformAlwaysClampingPhysics : null,
        ),
        slivers: [
          buildReplyHeader(isPortrait),
          replyList(),
        ],
      ),
    );
    if (!isPortrait) {
      reply = refreshIndicator(onRefresh: refreshDynamicComments, child: reply);
    }

    final child = TabBarView(
      controller: tabController,
      hitTestBehavior: .translucent,
      physics: const NeverScrollableScrollPhysics(),
      horizontalDragGestureRecognizer:
          CustomHorizontalDragGestureRecognizer.new,
      children: DynType.values
          .map(
            (e) => switch (e) {
              .repost => DynRepostPage(
                isPortrait: isPortrait,
                query: _activityQuery,
              ),
              .reply => reply,
              .like => DynLikePage(
                isPortrait: isPortrait,
                query: _activityQuery,
              ),
            },
          )
          .toList(),
    );
    if (isPortrait) {
      return Stack(
        clipBehavior: .none,
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            top: displacement,
            child: ValueListenableBuilder(
              valueListenable: _isRefreshing,
              builder: (_, refreshing, _) =>
                  RefreshIndicator_(isRefreshing: refreshing),
            ),
          ),
        ],
      );
    }
    return child;
  }

  Widget _buildDynPanel() {
    return SliverToBoxWithOffsetAdapter(
      offset: 55,
      onVisibilityChanged: controller.setShowTitle,
      child: Builder(
        builder: (context) {
          _scrollable = Scrollable.maybeOf(context);
          return DynamicPanel(
            item: controller.dynItem,
            isDetail: true,
            isDetailPortraitW: isPortrait,
            onSetPubSetting: controller.onSetPubSetting,
            onEdit: _onEdit,
            onSetReplySubject: controller.onSetReplySubject,
          );
        },
      ),
    );
  }

  Widget _buildPortrait(double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: NestedScrollView(
        scrollBehavior: const NoOverscrollIndicator(),
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [_buildDynPanel()];
        },
        body: Column(
          children: [
            _buildTabBar(),
            Expanded(child: _buildTabBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontal(double padding) {
    padding = padding / 4;
    final flex = controller.ratio[0].toInt();
    final flex1 = controller.ratio[1].toInt();
    final child = Row(
      children: [
        Expanded(
          flex: flex,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: .only(
                  left: padding,
                  bottom: this.padding.bottom + 100,
                ),
                sliver: _buildDynPanel(),
              ),
            ],
          ),
        ),
        Expanded(
          flex: flex1,
          child: Padding(
            padding: EdgeInsets.only(right: padding),
            child: MiniScaffold(
              body: Column(
                children: [
                  _buildTabBar(),
                  Expanded(child: _buildTabBody(false)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (PlatformUtils.isDesktop) {
      return PrimaryScrollController(
        controller: PrimaryScrollController.of(context),
        automaticallyInheritForPlatforms: _kDesktopPlatforms,
        child: child,
      );
    }
    return child;
  }

  Widget _buildBody() {
    double padding = max(maxWidth / 2 - Grid.smallCardWidth, 0);
    Widget child;
    if (isPortrait) {
      child = _buildPortrait(padding);
    } else {
      child = _buildHorizontal(padding);
    }
    return fabAnimWrapper(child: child);
  }

  Widget _buildBottom() {
    if (!controller.showDynActionBar) {
      return fabButton;
    }

    final primary = theme.colorScheme.primary;
    final outline = theme.colorScheme.outline;
    final btnStyle = TextButton.styleFrom(
      tapTargetSize: .padded,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      foregroundColor: outline,
    );

    Widget textIconButton({
      required IconData icon,
      required String text,
      required DynamicStat? stat,
      required ValueChanged<Color> onPressed,
      IconData? activatedIcon,
    }) {
      final bool status;
      final String count;
      if (stat != null) {
        status = stat.status ?? false;
        count = stat.count != null ? NumUtils.numFormat(stat.count) : text;
      } else {
        status = false;
        count = text;
      }
      final color = status ? primary : outline;
      final child = Icon(status ? activatedIcon : icon, size: 16, color: color);
      return TextButton.icon(
        icon: child,
        style: btnStyle,
        onPressed: () => onPressed(child.color!),
        label: Text(count, style: TextStyle(color: color)),
      );
    }

    final moduleStat = controller.dynItem.modules.moduleStat;
    return Padding(
      padding: .only(left: padding.left, right: padding.right),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              right: kFloatingActionButtonMargin,
              bottom: kFloatingActionButtonMargin,
            ),
            child: replyButton,
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.08),
                ),
              ),
            ),
            padding: EdgeInsets.only(bottom: padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (btnContext) {
                      final forward = moduleStat?.forward;
                      return textIconButton(
                        icon: FontAwesomeIcons.shareFromSquare.data,
                        text: '转发',
                        stat: forward,
                        onPressed: (_) => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (context) => RepostPanel(
                            item: controller.dynItem,
                            onSuccess: () {
                              if (forward != null) {
                                int count = forward.count ?? 0;
                                forward.count = count + 1;
                                if (btnContext.mounted) {
                                  (btnContext as Element).markNeedsBuild();
                                }
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: textIconButton(
                    icon: CustomIcons.share_node,
                    text: '分享',
                    stat: null,
                    onPressed: (_) => ShareUtils.shareText(
                      '${HttpString.opusBaseUrl}/${controller.dynItem.idStr}',
                    ),
                  ),
                ),
                Expanded(
                  child: textIconButton(
                    icon: FontAwesomeIcons.comment.data,
                    text: '评论',
                    stat: moduleStat?.comment,
                    onPressed: _jumpToComment,
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final displayedStatus = moduleStat?.like?.status ?? false;
                      return textIconButton(
                        icon: FontAwesomeIcons.thumbsUp.data,
                        activatedIcon: FontAwesomeIcons.solidThumbsUp.data,
                        text: '点赞',
                        stat: moduleStat?.like,
                        onPressed: (_) => onLikeDynamic(
                          context,
                          controller.dynItem,
                          displayedStatus,
                          () {
                            if (context.mounted) {
                              (context as Element).markNeedsBuild();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildReplyHeader([bool isPortrait = true]) {
    final secondary = theme.colorScheme.secondary;
    final child = Padding(
      padding: const .fromLTRB(12, 2.5, 6, 2.5),
      child: commentBuilder((comments, snapshot) {
        final sortType = snapshot?.sort ?? CommentPreferences.defaultSort;
        return Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(sortType.desc),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: comments == null || snapshot == null
                  ? null
                  : () => toggleCommentSort(comments, snapshot),
              icon: Icon(Icons.sort, size: 16, color: secondary),
              label: Text(
                sortType.descShort,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ),
          ],
        );
      }),
    );
    return SliverFloatingHeaderWidget(
      backgroundColor: theme.colorScheme.surface,
      child: child,
    );
  }

  void _jumpToComment([_]) {
    if (!mounted || !isPortrait) return;
    final positions = PrimaryScrollController.maybeOf(context)?.positions;
    if (positions == null || positions.length != 1) return;
    final position = positions.single;
    if (position.hasContentDimensions) {
      position.jumpTo(position.maxScrollExtent);
    }
  }
}
