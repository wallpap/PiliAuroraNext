import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/features/subscriptions/application/subscription_library.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/feed_view.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/video_card.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/core/text/number_format.dart';

class SubDetailPage extends ConsumerStatefulWidget {
  const SubDetailPage({super.key, this.id, this.subInfo, this.heroTag});
  final int? id;
  final SubItemModel? subInfo;
  final String? heroTag;
  @override
  ConsumerState<SubDetailPage> createState() => _SubDetailPageState();
  static void toSubDetailPage(
    int id, {
    String? heroTag,
    SubItemModel? subInfo,
  }) {
    Get.toNamed(
      '/subDetail',
      arguments: {'id': id, 'subInfo': subInfo, 'heroTag': heroTag},
    );
  }
}

class _SubDetailPageState extends ConsumerState<SubDetailPage> {
  late final _initialAccount = ref.read(mainAccountProvider);
  late final Map _arguments = widget.id == null && Get.arguments is Map
      ? Get.arguments as Map
      : const {};
  late final _query = SubscriptionQuery(
    owner: Object(),
    id: widget.id ?? int.tryParse('${_arguments['id']}') ?? 0,
  );
  late final SubItemModel? _initialInfo =
      widget.subInfo ?? _arguments['subInfo'] as SubItemModel?;
  late final String? _heroTag =
      widget.heroTag ?? _arguments['heroTag'] as String?;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final account = ref.watch(mainAccountProvider);
    final value = ref.watch(subscriptionFeedProvider(_query));
    final feed = ref.read(subscriptionFeedProvider(_query).notifier);
    final data = feed.displayState;
    final info =
        data?.metadata ??
        (identical(account, _initialAccount) &&
                value.isLoading &&
                !value.hasValue
            ? _initialInfo
            : null);
    return Material(
      color: theme.colorScheme.surface,
      child: SubscriptionFeedView(
        value: value,
        feed: feed,
        header: info == null
            ? const SliverAppBar()
            : _buildAppBar(theme, padding, info),
        itemBuilder: (item) =>
            SubVideoCardH(videoItem: item as SubDetailItemModel),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme, EdgeInsets padding, SubItemModel info) {
    final style = TextStyle(
      height: 1,
      fontSize: 12.5,
      color: theme.colorScheme.outline,
    );
    Widget cover = NetworkImgLayer(
      width: 176,
      height: 110,
      src: info.cover,
    );
    if (_heroTag != null) {
      cover = Hero(
        tag: _heroTag,
        child: cover,
      );
    }
    return SliverAppBar.medium(
      expandedHeight: kToolbarHeight + 132,
      pinned: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.title ?? '合集',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          Text(
            '共${info.mediaCount}条视频',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.2),
              ),
            ),
          ),
          padding: EdgeInsets.only(
            top: kToolbarHeight + padding.top + 10,
            left: 12 + padding.left,
            right: 12,
            bottom: 12,
          ),
          child: Row(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        info.title ?? '合集',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => info.upper?.mid == null
                          ? null
                          : Get.toNamed('/member?mid=${info.upper!.mid}'),
                      child: Text(
                        info.upper?.name ?? '',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('共${info.mediaCount}条视频', style: style),
                    const SizedBox(height: 4),
                    Text(
                      '${NumUtils.numFormat(info.viewCount ?? info.cntInfo?.play)}次播放',
                      style: style,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
