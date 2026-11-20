import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/common/skeleton/video_reply.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/dialog/dialog.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/selection_text.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_floating_header.dart';
import 'package:pili_aurora_next/features/community/application/pgc_reviews.dart';
import 'package:pili_aurora_next/features/community/domain/pgc_review.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/widgets/image/image_type.dart';
import 'package:pili_aurora_next/pages/pgc_review/post/view.dart';
import 'package:pili_aurora_next/common/widgets/svg/level_icon.dart';
import 'package:pili_aurora_next/common/widgets/extensions/scroll_controller_ext.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/core/text/number_format.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PgcReviewChildPage extends ConsumerStatefulWidget {
  const PgcReviewChildPage({
    super.key,
    required this.type,
    required this.name,
    required this.mediaId,
    this.owner,
    this.scrollController,
  });

  final PgcReviewType type;
  final String name;
  final Object? mediaId;
  final Object? owner;
  final ScrollController? scrollController;

  @override
  ConsumerState<PgcReviewChildPage> createState() => _PgcReviewChildPageState();
}

class _PgcReviewChildPageState extends ConsumerState<PgcReviewChildPage>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  late final _scroll = widget.scrollController ?? ScrollController();
  PgcReviewsQuery get _query => (
    owner: widget.owner ?? _owner,
    mediaId: widget.mediaId,
    type: widget.type,
  );
  bool get isLongReview => widget.type == .long;

  @override
  void dispose() {
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final provider = pgcReviewsProvider(_query);
    final snapshot = ref.watch(provider);
    final reviews = ref.read(provider.notifier);
    final pending = ref.watch(pgcReviewWritesProvider);
    return FeedPagination(
      controller: _scroll,
      dataSource: snapshot.source,
      dataRevision: snapshot,
      canLoadMore: () => snapshot.canLoadMore,
      onLoadMore: reviews.more,
      child: refreshIndicator(
        onRefresh: reviews.refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildHeader(theme, snapshot, reviews),
            _buildBody(theme, reviews, snapshot, pending),
            if (snapshot.pageError case final error?)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () => reviews.more(retry: true),
                  child: Text('$error，点击重试'),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    PgcReviews reviews,
    PgcReviewsState snapshot,
    List<PgcReviewWrite> pending,
  ) {
    switch (snapshot.loading) {
      case Loading():
        return const SliverPrototypeExtentList(
          prototypeItem: VideoReplySkeleton(),
          delegate: SliverSingleChildDelegate(
            count: 8,
            child: VideoReplySkeleton(),
          ),
        );
      case Success(:final response):
        if (response.isNotEmpty || snapshot.pageError != null) {
          final divider = Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          );
          return SliverList.separated(
            itemBuilder: (context, index) => _itemWidget(
              theme,
              reviews,
              snapshot,
              response[index],
              pending,
            ),
            itemCount: response.length,
            separatorBuilder: (context, index) => divider,
          );
        }
        return HttpError(onReload: reviews.refresh);
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: reviews.refresh,
        );
    }
  }

  Widget _itemWidget(
    ThemeData theme,
    PgcReviews reviews,
    PgcReviewsState snapshot,
    PgcReviewItem item,
    List<PgcReviewWrite> writes,
  ) {
    final author = item.author;
    final account = snapshot.account;
    bool isCurrent() =>
        mounted && _query == reviews.query && reviews.contains(snapshot, item);
    Future<void> act(PgcReviewAction action) async {
      if (!isCurrent()) return;
      final result = await reviews.act(snapshot, item, action);
      if (!mounted || _query != reviews.query || result == null) return;
      if (result case Error error) {
        error.toast();
      } else if (result.isSuccess && action == .delete) {
        SmartDialog.showToast('删除成功');
      }
    }

    void showMore() => showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (account.isLogin &&
              author?.mid == account.mid &&
              item.reviewId != null) ...[
            DialogOption(
              child: const Text('编辑', style: TextStyle(fontSize: 14)),
              onPressed: () {
                Get.back();
                if (!isCurrent()) return;
                showModalBottomSheet(
                  context: this.context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (context) {
                    return PgcReviewPostPanel(
                      name: widget.name,
                      mediaId: widget.mediaId,
                      reviewId: item.reviewId,
                      content: item.content,
                      score: item.score,
                      onSubmitted: () {
                        if (isCurrent()) reviews.refresh();
                      },
                    );
                  },
                );
              },
            ),
            DialogOption(
              child: const Text('删除', style: TextStyle(fontSize: 14)),
              onPressed: () async {
                Get.back();
                if (!isCurrent()) return;
                final confirmed = await showConfirmDialog(
                  context: this.context,
                  title: const Text('删除短评，同时删除评分？'),
                );
                if (confirmed) await act(.delete);
              },
            ),
          ],
          if (item.reviewId != null)
            DialogOption(
              child: const Text('举报', style: TextStyle(fontSize: 14)),
              onPressed: () => Get
                ..back()
                ..toNamed(
                  '/webview',
                  parameters: {
                    'url':
                        'https://www.bilibili.com/appeal/?reviewId=${item.reviewId}&type=shortComment&mediaId=${widget.mediaId}',
                  },
                ),
            ),
        ],
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isLongReview && item.articleId != null
            ? () => Get.toNamed(
                '/articlePage',
                parameters: {
                  'id': item.articleId!.toString(),
                  'type': 'read',
                },
              )
            : null,
        onLongPress: !isLongReview ? showMore : null,
        onSecondaryTap: !isLongReview && !PlatformUtils.isMobile
            ? showMore
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: author?.mid == null
                    ? null
                    : () => Get.toNamed('/member?mid=${author!.mid}'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NetworkImgLayer(
                      height: 34,
                      width: 34,
                      src: author?.avatar,
                      type: ImageType.avatar,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      spacing: 2,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          spacing: 6,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              author?.uname ?? '匿名用户',
                              style: TextStyle(
                                color: author?.annualVip == true
                                    ? theme.colorScheme.vipColor
                                    : theme.colorScheme.outline,
                                fontSize: 13,
                              ),
                            ),
                            memberLevelPicture(
                              author?.level ?? 0,
                              height: 11,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (item.pushTimeStr != null) ...[
                              Text(
                                item.pushTimeStr!,
                                style: TextStyle(
                                  color: theme.colorScheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            ...List.generate(
                              5,
                              (index) {
                                if (index <= item.score - 1) {
                                  return const Icon(
                                    CustomIcons.star_favorite_solid,
                                    size: 13,
                                    color: Color(0xFFFFAD35),
                                  );
                                }
                                return const Icon(
                                  CustomIcons.star_favorite_line,
                                  size: 14,
                                  color: Colors.grey,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              if (item.title != null)
                Text(
                  item.title!,
                  style: const TextStyle(
                    height: 1.75,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (isLongReview)
                Text(
                  item.content ?? '',
                  style: const TextStyle(height: 1.75),
                )
              else
                SelectionText(
                  item.content ?? '',
                  style: const TextStyle(height: 1.75),
                ),
              Builder(
                builder: (_) {
                  final pending =
                      item.reviewId == null ||
                      writes.any(
                        (write) =>
                            identical(write.account, account) &&
                            write.media == '${widget.mediaId}' &&
                            write.review == '${item.reviewId}',
                      );
                  final Color color = theme.colorScheme.outline;
                  final Color primary = theme.colorScheme.primary;
                  final ButtonStyle style = TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                  final isLike = item.stat.liked;
                  final isDislike = item.stat.disliked;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!isLongReview)
                        SizedBox(
                          height: 32,
                          child: TextButton(
                            style: const ButtonStyle(
                              visualDensity: .compact,
                              tapTargetSize: .shrinkWrap,
                              padding: WidgetStatePropertyAll(.zero),
                              minimumSize: WidgetStatePropertyAll(.square(40)),
                            ),
                            onPressed: pending ? null : () => act(.dislike),
                            child: Icon(
                              isDislike
                                  ? FontAwesomeIcons.solidThumbsDown.data
                                  : FontAwesomeIcons.thumbsDown.data,
                              size: 16,
                              color: isDislike ? primary : color,
                            ),
                          ),
                        ),
                      SizedBox(
                        height: 32,
                        child: TextButton(
                          style: style,
                          onPressed: isLongReview || pending
                              ? null
                              : () => act(.like),
                          child: Row(
                            spacing: 4,
                            children: [
                              Icon(
                                isLike
                                    ? FontAwesomeIcons.solidThumbsUp.data
                                    : FontAwesomeIcons.thumbsUp.data,
                                size: 16,
                                color: isLike ? primary : color,
                              ),
                              Text(
                                item.stat.likes == null
                                    ? '赞'
                                    : NumUtils.numFormat(item.stat.likes),
                                style: TextStyle(
                                  color: isLike ? primary : color,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    PgcReviewsState snapshot,
    PgcReviews reviews,
  ) => SliverFloatingHeaderWidget(
    backgroundColor: theme.colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 2.5, 6, 2.5),
      child: Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          if (snapshot.count case final count?)
            Text(
              '${NumUtils.numFormat(count)}条点评',
              style: const TextStyle(fontSize: 13),
            )
          else
            const SizedBox.shrink(),
          TextButton.icon(
            style: Style.buttonStyle,
            onPressed: snapshot.busy
                ? null
                : () {
                    reviews.toggleSort();
                    _scroll.jumpToTop();
                  },
            icon: Icon(
              Icons.sort,
              size: 16,
              color: theme.colorScheme.secondary,
            ),
            label: Text(
              snapshot.sort.label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  bool get wantKeepAlive => true;
}
