import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/assets.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/dynamic_sliver_app_bar/dynamic_sliver_app_bar.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/pair.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/image_type.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/fold_card_item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/top_details.dart';
import 'package:pili_aurora_next/pages/common/fab_mixin.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:pili_aurora_next/pages/dynamics_create/view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/topic_queries.dart';
import 'package:pili_aurora_next/features/community/application/topic_header.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/extension/scroll_controller_ext.dart';
import 'package:pili_aurora_next/utils/extension/num_ext.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:pili_aurora_next/features/content_discovery/application/discovery_preferences.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/route_manager.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class DynTopicPage extends ConsumerStatefulWidget {
  const DynTopicPage({super.key, required this.topicId, this.name = ''});
  final String topicId;
  final String name;

  @override
  ConsumerState<DynTopicPage> createState() => _DynTopicPageState();
}

class _DynTopicPageState extends ConsumerState<DynTopicPage>
    with DynMixin, SingleTickerProviderStateMixin, BaseFabMixin, FabMixin {
  late EdgeInsets padding;
  late ColorScheme colorScheme;
  final _owner = Object();
  final _scroll = ScrollController();
  int _sort = 0;
  double? _appbarOffset;
  TopicQuery get _query => (owner: _owner, id: widget.topicId, sort: _sort);
  TopicFeed get _actions => ref.read(topicFeedProvider(_query).notifier);
  TopicHeader get _header =>
      ref.read(topicHeaderProvider(widget.topicId).notifier);
  TopicHeaderState get _top => ref.read(topicHeaderProvider(widget.topicId));
  String get _topicName =>
      _top.loading.dataOrNull?.topicItem?.name ?? widget.name;
  bool get _isLogin => ref.read(mainAccountProvider).isLogin;
  bool get _isLike => _top.loading.dataOrNull?.topicItem?.isLike ?? false;
  bool get _isFav => _top.loading.dataOrNull?.topicItem?.isFav ?? false;
  @override
  void didUpdateWidget(covariant DynTopicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _sort = 0;
      _appbarOffset = null;
      _scroll.jumpToTop();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([_header.refresh(), _actions.onRefresh()]);
  }

  Future<void> _reload() {
    _scrollToFeed();
    return _actions.onReload();
  }

  void _scrollToFeed() {
    if (_appbarOffset == null) {
      _scroll.jumpToTop();
    } else if (_scroll.hasClients && _scroll.offset > _appbarOffset!) {
      _scroll.jumpTo(_appbarOffset!);
    }
  }

  void _onSort(int sort) {
    _scrollToFeed();
    if (_sort == sort) {
      _actions.onReload();
      return;
    }
    setState(() => _sort = sort);
  }

  Future<void> _write(bool favorite) async {
    final id = widget.topicId;
    final account = ref.read(mainAccountProvider);
    final result = await _header.toggle(favorite: favorite);
    if (!mounted ||
        id != widget.topicId ||
        !identical(account, ref.read(mainAccountProvider))) {
      return;
    }
    if (!result.isSuccess) result.toast();
  }

  Future<void> _unfold() async {
    final query = _query;
    final source = ref.read(topicFeedProvider(query)).source;
    final result = await _actions.unfold();
    if (!mounted ||
        query != _query ||
        !identical(source, ref.read(topicFeedProvider(query)).source)) {
      return;
    }
    if (!result.isSuccess) result.toast();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = ColorScheme.of(context);
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = topicFeedProvider(_query);
    final snapshot = ref.watch(provider);
    final top = ref.watch(topicHeaderProvider(widget.topicId));
    final allSortBy = snapshot.metadata?.sort?.allSortBy;
    return SimpleScaffold(
      body: refreshIndicator(
        onRefresh: _refresh,
        child: fabAnimWrapper(
          child: FeedPagination(
            controller: _scroll,
            dataSource: snapshot.source,
            dataRevision: snapshot,
            canLoadMore: () => ref.read(provider).canLoadMore,
            onLoadMore: _actions.onLoadMore,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildAppBar(colorScheme, padding, top.loading),
                DiscoveryFooter(error: top.error, retry: _header.refresh),
                if (allSortBy != null && allSortBy.isNotEmpty)
                  SliverPinnedHeader(
                    backgroundColor: colorScheme.surface,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 12 + padding.left,
                        top: 6,
                        bottom: 6,
                      ),
                      child: Builder(
                        builder: (context) {
                          return ToggleButtons(
                            fillColor: colorScheme.secondaryContainer,
                            selectedColor: colorScheme.onSecondaryContainer,
                            constraints: const BoxConstraints(
                              minWidth: 54,
                              minHeight: 24,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            borderRadius: const .all(.circular(25)),
                            onPressed: (index) {
                              _onSort(allSortBy[index].sortBy!);
                            },
                            isSelected: allSortBy
                                .map(
                                  (e) =>
                                      e.sortBy ==
                                      (snapshot.metadata?.sort?.showSortBy ??
                                          _sort),
                                )
                                .toList(),
                            children: allSortBy.map((e) {
                              return Text(
                                e.sortName!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1,
                                ),
                                strutStyle: const StrutStyle(
                                  height: 1,
                                  leading: 0,
                                  fontSize: 13,
                                ),
                                textScaler: TextScaler.noScaling,
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.only(
                    left: padding.left,
                    right: padding.right,
                    bottom: padding.bottom + 100,
                  ),
                  sliver: buildPage(
                    _buildBody(snapshot.loading),
                  ),
                ),
                DiscoveryFooter(error: snapshot.error, retry: _actions.retry),
              ],
            ),
          ),
        ),
      ),
      fab: SlideTransition(
        position: fabAnimation,
        child: Padding(
          padding: .only(
            right: kFloatingActionButtonMargin + padding.right,
            bottom: kFloatingActionButtonMargin + padding.bottom,
          ),
          child: FloatingActionButton.extended(
            onPressed: () {
              if (_isLogin) {
                CreateDynPanel.onCreateDyn(
                  context,
                  topic: Pair(
                    first: int.parse(widget.topicId),
                    second: _topicName,
                  ),
                );
              } else {
                SmartDialog.showToast('账号未登录');
              }
            },
            icon: const Icon(CustomIcons.topic_tag, size: 20),
            label: const Text('参与话题'),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    ColorScheme colorScheme,
    EdgeInsets padding,
    LoadingState<TopDetails?> topState,
  ) {
    final id = widget.topicId;
    final name = _topicName;
    final account = ref.read(mainAccountProvider);
    bool current() =>
        mounted &&
        id == widget.topicId &&
        identical(account, ref.read(mainAccountProvider));
    return switch (topState) {
      Loading() => const SliverAppBar(),
      Success(:final response) when response != null => DynamicSliverAppBar.medium(
        onPerformLayout: (value) =>
            _appbarOffset = value.height - kToolbarHeight - padding.top,
        title: IgnorePointer(child: Text(response.topicItem!.name)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: ResizeImage(
                width: MediaQuery.widthOf(context).cacheSize(context),
                AssetImage(
                  Assets.themed(Assets.topicHeader, colorScheme.brightness),
                ),
              ),
              filterQuality: FilterQuality.low,
              fit: BoxFit.cover,
            ),
          ),
          padding: EdgeInsets.only(
            top: padding.top,
            left: 12 + padding.left,
            right: 12 + padding.right,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (response.topicCreator != null)
                Container(
                  height: kToolbarHeight,
                  alignment: Alignment.centerLeft,
                  margin: const EdgeInsets.only(left: 45, right: 78),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Get.toNamed(
                      '/member?mid=${response.topicCreator!.uid}',
                    ),
                    child: Row(
                      spacing: 10,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NetworkImgLayer(
                          width: 28,
                          height: 28,
                          src: response.topicCreator!.face!,
                          type: ImageType.avatar,
                        ),
                        Flexible(
                          child: Text(
                            response.topicCreator!.name!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          ' 发起',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(
                response.topicItem!.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              SelectionText(
                response.topicItem!.description ?? '',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${NumUtils.numFormat(response.topicItem!.view)}浏览 · ${NumUtils.numFormat(response.topicItem!.discuss)}讨论',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        width: 1,
                        color: colorScheme.outline.withValues(alpha: 0.2),
                      ),
                      foregroundColor: _isLike
                          ? null
                          : colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _top.savingLike ? null : () => _write(false),
                    icon: _isLike
                        ? Icon(FontAwesomeIcons.solidThumbsUp.data, size: 13)
                        : Icon(FontAwesomeIcons.thumbsUp.data, size: 13),
                    label: Text(
                      NumUtils.numFormat(response.topicItem!.like),
                      style: const TextStyle(fontSize: 13),
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        width: 1,
                        color: colorScheme.outline.withValues(alpha: 0.2),
                      ),
                      foregroundColor: _isFav
                          ? null
                          : colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: const .new(horizontal: -4, vertical: -4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _top.savingFav ? null : () => _write(true),
                    icon: _isFav
                        ? Icon(FontAwesomeIcons.solidStar.data, size: 13)
                        : Icon(FontAwesomeIcons.star.data, size: 13),
                    label: Text(
                      NumUtils.numFormat(response.topicItem!.fav),
                      style: const TextStyle(fontSize: 13),
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => ShareUtils.shareText(
              '$name https://m.bilibili.com/topic-detail?topic_id=$id',
            ),
            // https://www.bilibili.com/v/topic/detail?topic_id=${widget.topicId}
            icon: const Icon(MdiIcons.share),
          ),
          PopupMenuButton(
            itemBuilder: (context) {
              return [
                AppPopupMenuItem(
                  onTap: () {
                    if (current()) _write(true);
                  },
                  child: Text(
                    '${_isFav ? '取消' : ''}收藏',
                  ),
                ),
                AppPopupMenuItem(
                  child: const Text('举报'),
                  onTap: () {
                    if (!current()) return;
                    if (!_isLogin) {
                      SmartDialog.showToast('账号未登录');
                      return;
                    }
                    PageUtils.inAppWebview(
                      'https://www.bilibili.com/h5/topic-active/topic-report?topic_id=$id&topic_name=$name&${ThemeUtils.themeUrl(colorScheme.isDark)}',
                    );
                  },
                ),
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      _ => SliverAppBar(
        pinned: true,
        title: Text(_topicName),
        actions: [
          IconButton(
            tooltip: '重试话题信息',
            onPressed: _header.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    };
  }

  Widget _buildBody(LoadingState<List<TopicCardItem>?> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? FeedLayoutPreferences.waterfall
                  ? SliverWaterfallFlow(
                      gridDelegate: dynGridDelegate,
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _itemBuilder(response, index),
                        childCount: response.length,
                      ),
                    )
                  : SliverList.builder(
                      itemBuilder: (context, index) =>
                          _itemBuilder(response, index),
                      itemCount: response.length,
                    )
            : HttpError(onReload: _reload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _reload,
      ),
    };
  }

  Widget _itemBuilder(List<TopicCardItem> list, int index) {
    final item = list[index];

    if (item.dynamicCardItem case final dynamicCardItem?) {
      return DynamicPanel(item: dynamicCardItem);
    }

    if (item.foldCardItem case final foldCardItem?) {
      return _buildFoldItem(foldCardItem);
    }

    return Text(item.topicType ?? 'err');
  }

  Widget _buildFoldItem(FoldCardItem item) {
    return Padding(
      padding: const .only(top: 12),
      child: Material(
        color: colorScheme.outline.withValues(alpha: .05),
        child: InkWell(
          onTap: _unfold,
          child: Padding(
            padding: const .symmetric(vertical: 10),
            child: Row(
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              children: [
                Text(item.foldDesc!),
                const Icon(Icons.keyboard_arrow_right, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
