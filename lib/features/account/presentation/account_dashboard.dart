import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/account/application/account_preferences.dart';
import 'package:pili_aurora_next/features/account/presentation/incognito_action.dart';
import 'package:pili_aurora_next/features/account/presentation/folder_item.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/services/settings/theme/theme_type.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:pili_aurora_next/common/assets.dart';
import 'package:pili_aurora_next/common/widgets/horizontal_wheel_scroll.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/flutter/list_tile.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/player_bar.dart';
import 'package:pili_aurora_next/common/widgets/svg/level_icon.dart';
import 'package:pili_aurora_next/common/layout/num_ext.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/core/random/random_text.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/route_manager.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class AccountDashboard extends ConsumerStatefulWidget {
  const AccountDashboard({
    super.key,
    required this.showBackBtn,
    required this.showReply,
    required this.wrapScroll,
    required this.onSwitchAccount,
    this.shellActions,
  });
  final bool showBackBtn, showReply;
  final Widget Function(Widget) wrapScroll;
  final VoidCallback onSwitchAccount;
  final Widget? shellActions;
  @override
  ConsumerState<AccountDashboard> createState() => _AccountDashboardState();
}

class _AccountDashboardState extends ConsumerState<AccountDashboard> {
  final _owner = Object();
  late final _query = FavoriteQuery(owner: _owner, kind: FavoriteKind.folders);
  final _folderScroll = ScrollController();
  ThemeType get _theme => ref.watch(accountThemeProvider);
  int? get _folderCount {
    final folders = ref.watch(favoriteFeedProvider(_query));
    return folders.isLoading || folders.hasError
        ? null
        : folders.value?.metadata.total;
  }

  List<({IconData icon, String title, VoidCallback onTap})> get _actions => [
    (
      icon: CustomIcons.folderDownloadOutline,
      title: '离线缓存',
      onTap: () => Get.toNamed('/download'),
    ),
    (icon: CustomIcons.history, title: '观看记录', onTap: () => _open('/history')),
    (
      icon: CustomIcons.subscriptions_outlined,
      title: '我的订阅',
      onTap: () => _open('/subscription'),
    ),
    (
      icon: CustomIcons.watch_later_outlined,
      title: '稍后再看',
      onTap: () => _open('/later'),
    ),
  ];
  void _open(String path) {
    if (ref.read(mainAccountProvider).isLogin) Get.toNamed(path);
  }

  void _push(String path) {
    final account = ref.read(mainAccountProvider);
    if (account.isLogin) Get.toNamed('/$path?mid=${account.mid}');
  }

  void _onLogin([bool longPress = false]) {
    final account = ref.read(mainAccountProvider);
    Get.toNamed(
      longPress || !account.isLogin
          ? '/loginPage'
          : '/member?mid=${account.mid}',
    );
  }

  Future<void> _refresh() async {
    if (!ref.read(mainAccountProvider).isLogin) return;
    try {
      await Future.wait([
        ref.read(accountProfileProvider.notifier).refresh(),
        ref.refresh(accountStatsProvider.future).then<void>((_) {}),
        ref.read(favoriteFeedProvider(_query).notifier).refresh(),
      ]);
    } catch (_) {
      if (mounted) SmartDialog.showToast('部分资料刷新失败，请重试');
    }
  }

  Future<void> _changeTheme() async {
    try {
      final next = await ref.read(accountThemeProvider.notifier).next();
      Get.changeThemeMode(ThemeUtils.themeMode = next.toThemeMode);
    } catch (_) {
      if (mounted) SmartDialog.showToast('主题保存失败，请重试');
    }
  }

  @override
  void dispose() {
    _folderScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.secondary;
    return Column(
      children: [
        Padding(
          padding: const .symmetric(vertical: 10),
          child: _buildHeaderActions,
        ),
        Expanded(
          child: Material(
            type: .transparency,
            child: refreshIndicator(
              onRefresh: _refresh,
              child: widget.wrapScroll(
                ListView(
                  padding: const .only(bottom: 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildUserInfo(theme, secondary),
                    if (ref.watch(accountProfileProvider).error
                        case final error?)
                      TextButton(
                        onPressed: _refresh,
                        child: Text('$error，点击重试'),
                      ),
                    if (ref.watch(accountProfileProvider).cacheError != null)
                      const Text('资料已更新，本地缓存保存失败'),
                    if (ref.watch(accountStatsProvider).hasError)
                      TextButton(
                        onPressed: () => ref.invalidate(accountStatsProvider),
                        child: const Text('关注与粉丝数读取失败，点击重试'),
                      ),
                    _buildActions(secondary),
                    if (ref.watch(mainAccountProvider).isLogin)
                      _buildFav(theme, secondary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(Color primary) {
    return Row(
      mainAxisAlignment: .spaceEvenly,
      children: _actions
          .map(
            (e) => Flexible(
              child: InkWell(
                onTap: e.onTap,
                borderRadius: Style.mdRadius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Column(
                      spacing: 6,
                      mainAxisSize: .min,
                      mainAxisAlignment: .center,
                      children: [
                        Icon(e.icon, color: primary),
                        Text(
                          e.title,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget get _buildHeaderActions {
    const iconSize = 22.0;
    const padding = EdgeInsets.all(8);
    const style = ButtonStyle(tapTargetSize: .shrinkWrap);
    return PlayerBar(
      children: [
        if (widget.showBackBtn)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: BackButton(),
          )
        else
          const SizedBox.shrink(),
        Row(
          spacing: 5,
          mainAxisSize: .min,
          children: [
            ?widget.shellActions,
            if (widget.showReply)
              IconButton(
                iconSize: iconSize,
                padding: padding,
                style: style,
                tooltip: '评论记录',
                onPressed: () => Get.toNamed('/myReply'),
                icon: const Icon(Icons.message_outlined),
              ),
            Builder(
              builder: (context) {
                final anonymity = ref.watch(incognitoProvider);
                return IconButton(
                  iconSize: iconSize,
                  padding: padding,
                  style: style,
                  tooltip: "${anonymity ? '退出' : '进入'}无痕模式",
                  onPressed: toggleIncognito,
                  icon: anonymity
                      ? const Icon(MdiIcons.incognito)
                      : const Icon(MdiIcons.incognitoOff),
                );
              },
            ),
            IconButton(
              iconSize: iconSize,
              padding: padding,
              style: style,
              tooltip: '切换账号',
              onPressed: widget.onSwitchAccount,
              icon: const Icon(Icons.switch_account_outlined),
            ),
            Builder(
              builder: (context) => IconButton(
                iconSize: iconSize,
                padding: padding,
                style: style,
                tooltip:
                    '切换至${ThemeType.values[(_theme.index + 1) % ThemeType.values.length].label}主题',
                onPressed: _changeTheme,
                icon: _theme.icon,
              ),
            ),
            IconButton(
              iconSize: iconSize,
              padding: padding,
              style: style,
              tooltip: '设置',
              onPressed: () =>
                  Get.toNamed('/setting', preventDuplicates: false),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ],
    );
  }

  Widget _buildUserInfo(ThemeData theme, Color secondary) {
    final style = TextStyle(
      fontSize: theme.textTheme.titleMedium!.fontSize,
      fontWeight: FontWeight.bold,
    );
    final labelStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    final coinLabelStyle = TextStyle(
      fontSize: theme.textTheme.labelMedium!.fontSize,
      color: theme.colorScheme.outline,
    );
    final coinValStyle = TextStyle(
      fontSize: theme.textTheme.labelMedium!.fontSize,
      fontWeight: FontWeight.bold,
      color: secondary,
    );
    return Builder(
      builder: (context) {
        final userInfo =
            ref.watch(accountProfileProvider).info ?? UserInfoData();
        final levelInfo = userInfo.levelInfo;
        final hasLevel = levelInfo != null;
        final isVip = userInfo.vipStatus != null && userInfo.vipStatus! > 0;
        final stats = ref.watch(accountStatsProvider);
        final userStat = stats.isLoading || stats.hasError
            ? const UserStat()
            : stats.value ?? const UserStat();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: .opaque,
              onTap: _onLogin,
              onLongPress: () {
                Feedback.forLongPress(context);
                _onLogin(true);
              },
              onSecondaryTap: PlatformUtils.isMobile
                  ? null
                  : () => _onLogin(true),
              child: Row(
                mainAxisSize: .min,
                children: [
                  const SizedBox(width: 20),
                  userInfo.face != null
                      ? Stack(
                          clipBehavior: .none,
                          children: [
                            NetworkImgLayer(
                              src: userInfo.face,
                              type: .avatar,
                              width: 55,
                              height: 55,
                            ),
                            if (isVip)
                              Positioned(
                                right: -1,
                                bottom: -2,
                                child: SvgPicture.asset(
                                  Assets.themed(
                                    Assets.vipIcon,
                                    Theme.of(context).brightness,
                                  ),
                                  height: 19,
                                  semanticsLabel: "大会员",
                                ),
                              ),
                          ],
                        )
                      : ClipOval(
                          child: Image.asset(
                            width: 55,
                            height: 55,
                            cacheHeight: 55.cacheSize(context),
                            Assets.themed(
                              Assets.avatarPlaceHolder,
                              Theme.of(context).brightness,
                            ),
                            semanticLabel: "默认头像",
                          ),
                        ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: .min,
                      mainAxisAlignment: .center,
                      crossAxisAlignment: .start,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            Flexible(
                              child: Text(
                                userInfo.uname ?? '点击登录',
                                style: theme.textTheme.titleMedium!.copyWith(
                                  height: 1,
                                  color: isVip && userInfo.vipType == 2
                                      ? theme.colorScheme.vipColor
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: .ellipsis,
                              ),
                            ),
                            memberLevelPicture(
                              levelInfo?.currentLevel ?? 0,
                              isSeniorMember: userInfo.isSeniorMember == 1,
                              height: 10,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '硬币 ',
                                style: coinLabelStyle,
                              ),
                              TextSpan(
                                text: userInfo.money?.toString() ?? '-',
                                style: coinValStyle,
                              ),
                              TextSpan(
                                text: "      经验 ",
                                style: coinLabelStyle,
                              ),
                              TextSpan(
                                text: levelInfo?.currentExp?.toString() ?? '-',
                                style: coinValStyle,
                              ),
                              TextSpan(
                                text: "/${levelInfo?.nextExp ?? '-'}",
                                style: coinLabelStyle,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 225),
                          child: LinearProgressIndicator(
                            minHeight: 2.25,
                            value: hasLevel && (levelInfo.nextExp ?? 0) > 0
                                ? ((levelInfo.currentExp ?? 0) /
                                          levelInfo.nextExp!)
                                      .clamp(0.0, 1.0)
                                : 0,
                            backgroundColor: theme.colorScheme.outline
                                .withValues(
                                  alpha: 0.4,
                                ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              secondary,
                            ),
                            stopIndicatorColor: Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: .spaceEvenly,
              children: [
                _btn(
                  count: userStat.dynamicCount,
                  countStyle: style,
                  name: '动态',
                  labelStyle: labelStyle,
                  onTap: () => _push('memberDynamics'),
                ),
                _btn(
                  count: userStat.following,
                  countStyle: style,
                  name: '关注',
                  labelStyle: labelStyle,
                  onTap: () => _push('follow'),
                ),
                _btn(
                  count: userStat.follower,
                  countStyle: style,
                  name: '粉丝',
                  labelStyle: labelStyle,
                  onTap: () => _push('fan'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _btn({
    required int? count,
    required TextStyle countStyle,
    required String name,
    required TextStyle? labelStyle,
    required VoidCallback onTap,
  }) {
    return Flexible(
      child: InkWell(
        onTap: onTap,
        borderRadius: Style.mdRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 80),
          child: AspectRatio(
            aspectRatio: 1,
            child: Column(
              spacing: 4,
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              children: [
                Text(
                  count?.toString() ?? '-',
                  style: countStyle,
                ),
                Text(
                  name,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _autoRefresh() {
    if (mounted) ref.invalidate(favoriteFeedProvider(_query));
  }

  Widget _buildFav(ThemeData theme, Color secondary) {
    return Column(
      children: [
        Divider(
          height: 20,
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
        ListTile(
          onTap: () => Get.toNamed('/fav')?.whenComplete(_autoRefresh),
          dense: true,
          title: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '我的收藏  ',
                    style: TextStyle(
                      fontSize: theme.textTheme.titleMedium!.fontSize,
                      fontWeight: .bold,
                    ),
                  ),
                  if (_folderCount != null)
                    TextSpan(
                      text: "$_folderCount  ",
                      style: TextStyle(
                        fontSize: theme.textTheme.titleSmall!.fontSize,
                        color: secondary,
                      ),
                    ),
                  WidgetSpan(
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          trailing: IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ),
        _buildFavBody(theme, secondary),
      ],
    );
  }

  Widget _buildFavBody(
    ThemeData theme,
    Color secondary,
  ) {
    return ref
        .watch(favoriteFeedProvider(_query))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) =>
              SizedBox(height: 160, child: Center(child: Text('$error'))),
          data: (state) {
            final favFolderList = state.items.cast<FavFolderInfo>();
            if (favFolderList.isEmpty) {
              return const SizedBox.shrink();
            }
            final hasMoreFolders = (_folderCount ?? 0) > favFolderList.length;
            final itemCount = favFolderList.length + (hasMoreFolders ? 1 : 0);
            final rowCount = itemCount > 1 ? 2 : 1;
            const rowHeight = 190.0;
            const padding = EdgeInsets.only(left: 20, top: 10, right: 20);
            return SizedBox(
              height: padding.vertical + rowCount * rowHeight,
              child: HorizontalWheelScroll(
                child: GridView.builder(
                  controller: _folderScroll,
                  padding: padding,
                  scrollDirection: .horizontal,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: rowCount,
                    mainAxisExtent: FavFolderItem.coverWidth,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index == favFolderList.length) {
                      return Padding(
                        padding: const .only(bottom: 35),
                        child: Center(
                          child: IconButton(
                            tooltip: '查看更多',
                            style: ButtonStyle(
                              padding: const WidgetStatePropertyAll(.zero),
                              backgroundColor: WidgetStatePropertyAll(
                                theme.colorScheme.secondaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            onPressed: () =>
                                Get.toNamed('/fav')?.whenComplete(_autoRefresh),
                            icon: Icon(
                              Icons.arrow_forward_ios,
                              size: 18,
                              color: secondary,
                            ),
                          ),
                        ),
                      );
                    } else {
                      return FavFolderItem(
                        heroTag: generateRandomString(8),
                        item: favFolderList[index],
                        onPop: _autoRefresh,
                      );
                    }
                  },
                ),
              ),
            );
          },
        );
  }
}
