import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/skeleton/video_card_h.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart'
    show displacement;
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show platformAlwaysClampingPhysics;
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/image_preview_type.dart';
import 'package:pili_aurora_next/models/common/image_type.dart';
import 'package:pili_aurora_next/features/member_space/presentation/user_info_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/item.dart';
import 'package:pili_aurora_next/features/following/application/follow_relations.dart';
import 'package:pili_aurora_next/features/member_space/application/space_archive.dart';
import 'package:pili_aurora_next/features/member_space/application/video_author.dart';
import 'package:pili_aurora_next/features/member_space/domain/video_author.dart';
import 'package:pili_aurora_next/pages/follow_type/view.dart';
import 'package:pili_aurora_next/pages/follow/view.dart';
import 'package:pili_aurora_next/pages/member_video/widgets/video_card_h_member_video.dart';
import 'package:pili_aurora_next/utils/bili_utils.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/features/following/presentation/follow_actions_dialog.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HorizontalMemberPage extends ConsumerStatefulWidget {
  const HorizontalMemberPage({
    super.key,
    required this.query,
    required this.bvid,
    required this.onSelect,
  });

  final AnchoredSpaceArchiveQuery query;
  final String bvid;
  final ValueChanged<SpaceArchiveItem> onSelect;

  @override
  ConsumerState<HorizontalMemberPage> createState() =>
      _HorizontalMemberPageState();
}

class _HorizontalMemberPageState extends ConsumerState<HorizontalMemberPage> {
  static const _itemExtent = 112.0;
  final _scroll = ScrollController();
  late ColorScheme colorScheme;
  bool _positionedOnOpen = false;
  bool _loadingPrevious = false;
  int get _mid => widget.query.mid;
  late final _authorProvider = videoAuthorProvider((
    owner: widget.query.owner,
    mid: _mid,
  ));
  late final _archiveProvider = anchoredSpaceArchiveProvider(widget.query);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = ColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final author = ref.watch(_authorProvider);
    final archive = ref.watch(_archiveProvider);
    return Material(
      child: _buildUserPage(author, archive),
    );
  }

  void _jumpAfterLayout(Object source, double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          !identical(source, ref.read(_archiveProvider).source)) {
        return;
      }
      final position = _scroll.position;
      final target = offset.clamp(0.0, position.maxScrollExtent).toDouble();
      if (target != position.pixels) _scroll.jumpTo(target);
    });
  }

  Future<void> _loadPrevAndKeepPos(SpaceArchiveState archive) async {
    setState(() => _loadingPrevious = true);
    final result = await ref.read(_archiveProvider.notifier).previous();
    if (!mounted) return;
    setState(() => _loadingPrevious = false);
    if (!identical(archive.source, ref.read(_archiveProvider).source)) return;
    if (result case Error error) {
      error.toast();
    } else if (result.data > 0) {
      _jumpAfterLayout(archive.source, result.data * _itemExtent);
    }
  }

  bool onNotification(ScrollEndNotification notification) {
    final archive = ref.read(_archiveProvider);
    if (notification.depth == 0 &&
        notification.metrics.pixels == 0 &&
        archive.hasPrevious &&
        !archive.busy &&
        !_loadingPrevious) {
      _loadPrevAndKeepPos(archive);
    }
    return false;
  }

  Widget _buildUserPage(VideoAuthorState author, SpaceArchiveState archive) {
    return switch (author.profile) {
      Loading() => m3eLoading,
      Success(:final response) => Column(
        children: [
          _buildUserInfo(author, response),
          Expanded(
            child: Stack(
              clipBehavior: .none,
              children: [
                NotificationListener<ScrollEndNotification>(
                  onNotification: onNotification,
                  child: _buildArchive(archive),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: displacement + 35,
                  child: RefreshIndicator_(isRefreshing: _loadingPrevious),
                ),
              ],
            ),
          ),
        ],
      ),
      Error(:final errMsg) => scrollErrorWidget(
        controller: _scroll,
        errMsg: errMsg,
        onReload: ref.read(_authorProvider.notifier).refresh,
      ),
    };
  }

  Widget _buildArchive(SpaceArchiveState archive) {
    final archives = ref.read(_archiveProvider.notifier);
    final rows = archive.loading.dataOrNull;
    if (!_positionedOnOpen && rows != null && rows.isNotEmpty) {
      _positionedOnOpen = true;
      final index = rows.indexWhere((item) => item.bvid == widget.bvid);
      if (index > 0) _jumpAfterLayout(archive.source, index * _itemExtent);
    }
    return FeedPagination(
      controller: _scroll,
      dataSource: archive.source,
      dataRevision: archive,
      canLoadMore: () => archive.canLoadMore && !_loadingPrevious,
      onLoadMore: archives.more,
      child: CustomScrollView(
        physics: platformAlwaysClampingPhysics,
        controller: _scroll,
        slivers: [
          _buildVideoList(archive, archives),
          if (archive.pageError case final error?)
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: () => archives.more(retry: true),
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
    );
  }

  Widget _buildHeader(SpaceArchiveState archive, SpaceArchive archives) {
    return SliverPinnedHeader(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ?_buildCount(archive.count),
            _buildSortBtn(archive, archives),
          ],
        ),
      ),
    );
  }

  Widget? _buildCount(int? count) {
    if (count != null) {
      return Text(
        '共$count视频',
        style: const TextStyle(fontSize: 13),
      );
    }
    return null;
  }

  Widget _buildSortBtn(SpaceArchiveState archive, SpaceArchive archives) {
    return TextButton.icon(
      style: Style.buttonStyle,
      onPressed: archive.busy
          ? null
          : () {
              archives.toggleSort();
              if (_scroll.hasClients) _scroll.jumpTo(0);
            },
      icon: Icon(
        Icons.sort,
        size: 16,
        color: colorScheme.secondary,
      ),
      label: Text(
        archive.order.label,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.secondary,
        ),
      ),
    );
  }

  Widget _buildVideoList(
    SpaceArchiveState archive,
    SpaceArchive archives,
  ) {
    return switch (archive.loading) {
      Loading() => const SliverFixedExtentList(
        delegate: SliverSingleChildDelegate(
          count: 10,
          child: VideoCardHSkeleton(),
        ),
        itemExtent: _itemExtent,
      ),
      Success(:final response) =>
        response.isNotEmpty
            ? SliverMainAxisGroup(
                slivers: [
                  _buildHeader(archive, archives),
                  SliverFixedExtentList.builder(
                    itemBuilder: (context, index) {
                      final videoItem = response[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: VideoCardHMemberVideo(
                          videoItem: videoItem,
                          bvid: widget.bvid,
                          onTap: () => widget.onSelect(videoItem),
                        ),
                      );
                    },
                    itemCount: response.length,
                    itemExtent: _itemExtent,
                  ),
                ],
              )
            : HttpError(onReload: archives.refresh),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: archives.refresh,
      ),
    };
  }

  Widget _buildUserInfo(VideoAuthorState author, VideoAuthorInfo profile) {
    return Padding(
      padding: const .only(left: 16, top: 10, right: 16, bottom: 3),
      child: Row(
        spacing: 10,
        children: [
          _buildAvatar(profile.avatar),
          Expanded(child: _buildInfo(author, profile)),
        ],
      ),
    );
  }

  Column _buildInfo(VideoAuthorState author, VideoAuthorInfo profile) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          GestureDetector(
            onTap: () => Utils.copyText(profile.name ?? ''),
            child: Text(
              profile.name ?? '',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: profile.annualVip ? colorScheme.vipColor : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (profile.level case final level?)
            BiliUtils.levelPicture(
              level,
              isSeniorMember: profile.senior,
              height: 11,
            ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          for (final type in UserInfoType.values) ...[
            if (type != UserInfoType.values.first)
              SizedBox(
                height: 10,
                width: 20,
                child: VerticalDivider(width: 1, color: colorScheme.outline),
              ),
            _buildChildInfo(type, author, profile.name),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Row(
        spacing: 8,
        children: [
          Expanded(
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: author.followed
                    ? colorScheme.onInverseSurface
                    : null,
                foregroundColor: author.followed ? colorScheme.outline : null,
                padding: EdgeInsets.zero,
                tapTargetSize: .shrinkWrap,
                visualDensity: const VisualDensity(vertical: -2),
              ),
              onPressed: () {
                if (_mid == author.account.mid) {
                  Get.toNamed('/editProfile');
                  return;
                }
                if (!author.account.isLogin) {
                  SmartDialog.showToast('账号未登录');
                  return;
                }
                final profile = ref.read(_authorProvider.notifier);
                showFollowActions(
                  context: context,
                  account: author.account,
                  mid: _mid,
                  isFollow: author.followed,
                  isCurrent: () => mounted && profile.owns(author),
                  afterMod: (attribute) =>
                      profile.setFollowed(author, attribute != 0),
                );
              },
              child: Text(
                _mid == author.account.mid
                    ? '编辑资料'
                    : author.followed
                    ? '已关注'
                    : '关注',
                maxLines: 1,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: .shrinkWrap,
                visualDensity: const VisualDensity(vertical: -2),
              ),
              onPressed: () => Get.toNamed('/member?mid=$_mid'),
              child: const Text(
                '查看主页',
                maxLines: 1,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildChildInfo(
    UserInfoType type,
    VideoAuthorState author,
    String? name,
  ) {
    String count;
    VoidCallback? onTap;
    switch (type) {
      case UserInfoType.fan:
        count = author.followers != null
            ? NumUtils.numFormat(author.followers)
            : '';
        onTap = () => FollowTypePage.open(
          kind: FollowKind.fans,
          mid: _mid,
          name: name,
        );
      case UserInfoType.follow:
        count = author.following?.toString() ?? '';
        onTap = () => FollowPage.toFollowPage(
          mid: _mid,
          name: name,
        );
      case UserInfoType.like:
        count = author.likes != null ? NumUtils.numFormat(author.likes) : '';
    }
    return GestureDetector(
      onTap: onTap,
      child: Text(
        '$count${type.title}',
        style: TextStyle(
          fontSize: 14,
          color: colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildAvatar(String? face) => GestureDetector(
    onTap: face == null
        ? null
        : () => PageUtils.imageView(imgList: [SourceModel(url: face)]),
    child: NetworkImgLayer(
      src: face,
      type: ImageType.avatar,
      width: 70,
      height: 70,
    ),
  );
}
