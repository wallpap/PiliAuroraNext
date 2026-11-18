import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/dialog/report_member.dart';
import 'package:pili_aurora_next/common/widgets/dynamic_sliver_app_bar/dynamic_sliver_app_bar.dart';
import 'package:pili_aurora_next/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_behavior.dart'
    show NoOverscrollIndicator;
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/models/remote/live/live_medal_wall/data.dart';
import 'package:pili_aurora_next/models/remote/space/space/reservation_card_list.dart';
import 'package:pili_aurora_next/pages/log_table/controller.dart';
import 'package:pili_aurora_next/pages/log_table/view.dart';
import 'package:pili_aurora_next/pages/login_devices/view.dart';
import 'package:pili_aurora_next/pages/member/controller.dart';
import 'package:pili_aurora_next/pages/member/shortcut_action.dart';
import 'package:pili_aurora_next/pages/member/widget/medal_wall.dart';
import 'package:pili_aurora_next/pages/member/widget/reserve_button.dart';
import 'package:pili_aurora_next/pages/member/widget/user_info_card.dart';
import 'package:pili_aurora_next/pages/member_cheese/view.dart';
import 'package:pili_aurora_next/pages/member_contribute/navigation.dart';
import 'package:pili_aurora_next/features/member_space/domain/space_tabs.dart';
import 'package:pili_aurora_next/models/remote/space/space/data.dart';
import 'package:pili_aurora_next/utils/extension/nested_scroll_ext.dart';
import 'package:pili_aurora_next/pages/member_contribute/view.dart';
import 'package:pili_aurora_next/pages/member_dynamics/view.dart';
import 'package:pili_aurora_next/pages/member_favorite/view.dart';
import 'package:pili_aurora_next/pages/member_home/view.dart';
import 'package:pili_aurora_next/pages/member_pgc/view.dart';
import 'package:pili_aurora_next/pages/member_shop/view.dart';
import 'package:pili_aurora_next/pages/member_video_web/archive/view.dart';
import 'package:pili_aurora_next/pages/member_video_web/season_series/view.dart';
import 'package:pili_aurora_next/utils/date_utils.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/num_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:pili_aurora_next/utils/utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MemberPage extends StatefulWidget {
  const MemberPage({super.key});

  @override
  State<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends State<MemberPage> with TickerProviderStateMixin {
  late final int _mid;
  late final String _heroTag;
  late final MemberController _userController;
  final _scrollKey = GlobalKey<ExtendedNestedScrollViewState>();
  TabController? _sections;
  TabController? _contributions;
  SpaceTabs? _renderedSections;
  bool _contributionOpened = false;
  PageController? _headerController;

  void _syncTabs(SpaceTabs? sections) {
    if (identical(sections, _renderedSections)) return;
    _renderedSections = sections;
    _sections?.dispose();
    _contributions?.dispose();
    _contributionOpened = false;
    _sections =
        sections == null || sections.tabs.isEmpty
              ? null
              : TabController(
                  vsync: this,
                  length: sections.tabs.length,
                  initialIndex: sections.initialIndex,
                );
    _sections?.addListener(_trackContribution);
    final items = sections?.contributions ?? const [];
    _contributions = items.length < 2
        ? null
        : TabController(vsync: this, length: items.length);
    _trackContribution();
  }

  void _trackContribution() {
    final sections = _renderedSections;
    if (sections != null &&
        _sections?.index == sections.indexOf('contribute')) {
      _contributionOpened = true;
    }
  }

  bool _openSection(String section, String? contribution) {
    final sections = _renderedSections;
    if (sections == null) return false;
    final index = sections.indexOf(section);
    if (index < 0) return false;
    if (section == 'contribute' && contribution != null) {
      final subIndex = sections.contributions.indexWhere(
        (item) => item.param == contribution,
      );
      if (subIndex >= 0) _contributions?.index = subIndex;
    }
    _sections?.animateTo(index);
    return true;
  }

  void _onTapTab(int _) {
    if (_sections?.indexIsChanging == false) {
      _scrollKey.currentState?.animToTop();
    }
  }

  PageController getHeaderController() =>
      _headerController ??= PageController();

  @override
  void initState() {
    super.initState();
    _mid = int.tryParse(Get.parameters['mid']!) ?? -1;
    _heroTag = Utils.makeHeroTag(_mid);
    _userController = Get.put(
      MemberController(mid: _mid),
      tag: _heroTag,
    );
  }

  @override
  void dispose() {
    _sections?.dispose();
    _contributions?.dispose();
    _headerController?.dispose();
    _headerController = null;
    _cacheFollowTime = null;
    _cacheMedalData = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);
    return Material(
      color: theme.surface,
      child: Obx(
        () {
          final loading = _userController.loadingState.value;
          _syncTabs(loading is Success ? _userController.sections : null);
          return switch (loading) {
            Loading() => m3eLoading,
            Success(:final response) => ExtendedNestedScrollView(
              onlyOneScrollInBody: true,
              key: _scrollKey,
              scrollBehavior: const NoOverscrollIndicator(),
              pinnedHeaderSliverHeightBuilder: () =>
                  kToolbarHeight + MediaQuery.viewPaddingOf(context).top,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                if (response != null) {
                  return [
                    DynamicSliverAppBar.medium(
                      actions: _actions(theme),
                      title: Text(_userController.username ?? ''),
                      flexibleSpace: Obx(
                        () => UserInfoCard(
                          isOwner:
                              _userController.mid ==
                              _userController.account.mid,
                          relation: _userController.relation.value,
                          card: response.card!,
                          images: response.images!,
                          onFollow: () => _userController.onFollow(context),
                          live: _userController.live,
                          silence: _userController.silence,
                          headerControllerBuilder: getHeaderController,
                          showLiveMedalWall: _showLiveMedalWall,
                          charges: _userController.charges,
                          chargeCount: _userController.chargeCount,
                          guards: _userController.guards,
                          guardCount: _userController.guardCount,
                        ),
                      ),
                    ),
                  ];
                }
                return [
                  SliverAppBar(
                    pinned: true,
                    actions: _actions(theme),
                    title: GestureDetector(
                      onTap: _userController.onReload,
                      behavior: HitTestBehavior.opaque,
                      child: Text(_userController.username ?? ''),
                    ),
                  ),
                ];
              },
              body: _sections != null
                  ? Padding(
                      padding: .only(left: padding.left, right: padding.right),
                      child: Column(
                        children: [
                          if ((_sections?.length ?? 0) > 1)
                            SizedBox(
                              height: 45,
                              child: TabBar(
                                labelPadding: .zero,
                                controller: _sections,
                                tabs: _userController.sections.tabs
                                    .map(
                                      (item) => Tab(
                                        child: Text(
                                          item.title ?? '',
                                          softWrap: false,
                                          overflow: .fade,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onTap: _onTapTab,
                                dividerColor: theme.outline.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                          Expanded(child: _buildBody(response)),
                        ],
                      ),
                    )
                  : scrollableError,
            ),
            Error(:final errMsg) => scrollErrorWidget(
              errMsg: errMsg,
              onReload: _userController.onReload,
            ),
          };
        },
      ),
    );
  }

  Widget _reserveBtn(List<ReservationCardItem> list, ColorScheme theme) {
    return IconButton(
      tooltip: '预约',
      onPressed: () => _showReserveList(list),
      icon: ReserveButton(
        count: list.length,
        color: theme.onSurfaceVariant,
        child: const Icon(Icons.notifications_none),
      ),
    );
  }

  void _showReserveList(List<ReservationCardItem> list) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(640, context.mediaQueryShortestSide),
      ),
      builder: (context) {
        final scheme = ColorScheme.of(context);
        return Padding(
          padding: .only(bottom: MediaQuery.viewPaddingOf(context).bottom + 30),
          child: Column(
            mainAxisSize: .min,
            children: [
              InkWell(
                onTap: Get.back,
                borderRadius: Style.bottomSheetRadius,
                child: SizedBox(
                  height: 35,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: scheme.outline,
                        borderRadius: const .all(.circular(1.5)),
                      ),
                    ),
                  ),
                ),
              ),
              ...list.map((e) {
                return Builder(
                  builder: (context) {
                    Widget trailing = FilledButton.tonal(
                      onPressed: () async {
                        final isFollow = e.isFollow;
                        final res = await UserHttp.spaceReserve(
                          sid: e.sid!,
                          isFollow: isFollow,
                        );
                        if (res.isSuccess) {
                          e
                            ..total += isFollow ? -1 : 1
                            ..isFollow = !isFollow;
                          if (!context.mounted) return;
                          (context as Element).markNeedsBuild();
                        } else {
                          res.toast();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: e.isFollow
                            ? scheme.onInverseSurface
                            : null,
                        foregroundColor: e.isFollow ? scheme.outline : null,
                        tapTargetSize: .shrinkWrap,
                        minimumSize: const Size(68, 40),
                        padding: const .symmetric(horizontal: 10),
                        visualDensity: const .new(horizontal: -2, vertical: -3),
                        shape: const RoundedRectangleBorder(
                          borderRadius: .all(.circular(6)),
                        ),
                      ),
                      child: Text(
                        '${e.isFollow ? '已' : ''}预约',
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                    if (e.dynamicId?.isNotEmpty ?? false) {
                      trailing = Row(
                        spacing: 8,
                        mainAxisSize: .min,
                        children: [
                          iconButton(
                            tooltip: '预约动态',
                            size: 32,
                            iconSize: 20,
                            iconColor: scheme.outline,
                            icon: const Icon(Icons.open_in_browser),
                            onPressed: () => PageUtils.pushDynFromId(
                              id: e.dynamicId,
                            ),
                          ),
                          trailing,
                        ],
                      );
                    }
                    return ListTile(
                      dense: true,
                      title: Text(
                        e.name!,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Padding(
                        padding: const .only(top: 2.0),
                        child: Text.rich(
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${e.descText1 == null ? '' : '${e.descText1}  '}'
                                    '${NumUtils.numFormat(e.total)}人预约',
                              ),
                              if (e.lotteryPrizeInfo case final lottery?) ...[
                                const TextSpan(text: '\n'),
                                WidgetSpan(
                                  alignment: .middle,
                                  child: Icon(
                                    size: 15,
                                    Icons.card_giftcard,
                                    color: scheme.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${lottery.text}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.primary,
                                  ),
                                  recognizer:
                                      lottery.jumpUrl?.isNotEmpty == true
                                      ? (NoDeadlineTapGestureRecognizer()
                                          ..onTap = () => Get.toNamed(
                                            '/webview',
                                            parameters: {
                                              'url': lottery.jumpUrl!,
                                            },
                                          ))
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      trailing: trailing,
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _actions(ColorScheme theme) => [
    if (_userController.reserves?.isNotEmpty ?? false)
      _reserveBtn(_userController.reserves!, theme),
    IconButton(
      tooltip: '搜索',
      onPressed: () => Get.toNamed(
        '/memberSearch?mid=$_mid&uname=${_userController.username}',
      ),
      icon: const Icon(Icons.search_outlined),
    ),
    PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => <PopupMenuEntry>[
        if (_userController.account.isLogin &&
            _userController.account.mid != _mid) ...[
          AppPopupMenuItem(
            onTap: _userController.scopedAction(
              () => _userController.blockUser(context),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 19),
                const SizedBox(width: 10),
                Text(
                  _userController.relation.value != 128 ? '加入黑名单' : '移除黑名单',
                ),
              ],
            ),
          ),
          if (_userController.isFollowed == 1)
            AppPopupMenuItem(
              onTap: _userController.scopedAction(_userController.onRemoveFan),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.remove_circle_outline_outlined, size: 19),
                  SizedBox(width: 10),
                  Text('移除粉丝'),
                ],
              ),
            ),
        ],
        AppPopupMenuItem(
          onTap: _userController.shareUser,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.share_outlined, size: 19),
              const SizedBox(width: 10),
              Text(
                _userController.account.mid != _mid ? '分享UP主' : '分享我的主页',
              ),
            ],
          ),
        ),
        if (PlatformUtils.isMobile)
          AppPopupMenuItem(
            onTap: _createShortcut,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_box_outlined, size: 19),
                SizedBox(width: 10),
                Text('添加至桌面'),
              ],
            ),
          ),
        if (_contributionOpened)
          AppPopupMenuItem(
            onTap: _toWebArchive,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.extension_outlined, size: 19),
                SizedBox(width: 10),
                Text('网页投稿'),
              ],
            ),
          ),
        if (_userController.account.isLogin)
          if (_userController.mid == _userController.account.mid) ...[
            if ((_userController
                        .loadingState
                        .value
                        .dataOrNull
                        ?.card
                        ?.vip
                        ?.status ??
                    0) >
                0)
              AppPopupMenuItem(
                onTap: _userController.scopedAction(_userController.vipExpAdd),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upcoming_outlined, size: 19),
                    SizedBox(width: 10),
                    Text('大会员经验'),
                  ],
                ),
              ),
            AppPopupMenuItem(
              onTap: () => Get.to(const LoginDevicesPage()),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices, size: 18),
                  SizedBox(width: 10),
                  Text('登录设备'),
                ],
              ),
            ),
            AppPopupMenuItem(
              onTap: () => Get.to(const LogPage(type: LogType.login)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.login, size: 18),
                  SizedBox(width: 10),
                  Text('登录记录'),
                ],
              ),
            ),
            AppPopupMenuItem(
              onTap: () => Get.to(const LogPage(type: LogType.coin)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FontAwesomeIcons.b.data, size: 16),
                  const SizedBox(width: 10),
                  const Text('硬币记录'),
                ],
              ),
            ),
            AppPopupMenuItem(
              onTap: () => Get.to(const LogPage(type: LogType.exp)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.linear_scale, size: 18),
                  SizedBox(width: 10),
                  Text('经验记录'),
                ],
              ),
            ),
            AppPopupMenuItem(
              onTap: () => Get.toNamed('/spaceSetting'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_outlined, size: 19),
                  SizedBox(width: 10),
                  Text('空间设置'),
                ],
              ),
            ),
          ] else ...[
            if (_userController.isFollow)
              AppPopupMenuItem(
                onTap: _showFollowTime,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.more_time_outlined, size: 19),
                    SizedBox(width: 10),
                    Text('关注时间'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            AppPopupMenuItem(
              onTap: () => showMemberReportDialog(
                context,
                name: _userController.username,
                mid: _mid,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 19,
                    color: theme.error,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '举报',
                    style: TextStyle(color: theme.error),
                  ),
                ],
              ),
            ),
          ],
      ],
    ),
    const SizedBox(width: 4),
  ];

  Widget _buildBody(SpaceData? data) => tabBarView(
    hitTestBehavior: .translucent,
    controller: _sections,
    children: _userController.sections.tabs.map((item) {
      return switch (item.param!) {
        'home' => MemberHome(
          data: data,
          mid: _mid,
          name: _userController.username,
          setting: _userController.spaceSetting,
          openSection: _openSection,
        ),
        'dynamic' => MemberDynamicsPage(mid: _mid),
        'contribute' => MemberContribute(
          heroTag: _heroTag,
          items: _userController.sections.contributions,
          controller: _contributions,
          mid: _mid,
          navigation: (
            username: _userController.username,
            fromViewAid: _userController.fromViewAid,
            scrollState: () => _scrollKey.currentState,
          ),
        ),
        'bangumi' => MemberBangumi(
          heroTag: _heroTag,
          mid: _mid,
        ),
        'favorite' => MemberFavorite(
          heroTag: _heroTag,
          mid: _mid,
        ),
        'cheese' => MemberCheese(
          heroTag: _heroTag,
          mid: _mid,
        ),
        'shop' => MemberShop(
          heroTag: _heroTag,
          mid: _mid,
        ),
        _ => Center(child: Text(item.title ?? '')),
      };
    }).toList(),
  );

  String? _cacheFollowTime;
  Future<void> _showFollowTime() async {
    void onShow() {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_userController.username ?? ''),
          content: Text(_cacheFollowTime!),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '关闭',
                style: TextStyle(color: ColorScheme.of(context).outline),
              ),
            ),
          ],
        ),
      );
    }

    if (_cacheFollowTime != null) {
      onShow();
      return;
    }
    final res = await UserHttp.userRelation(_mid);
    if (res case Success(:final response)) {
      if (response.mtime == null) return;
      _cacheFollowTime =
          '关注时间: ${DateFormatUtils.longFormatDs.format(
            DateTime.fromMillisecondsSinceEpoch(response.mtime! * 1000),
          )}';
      onShow();
    } else {
      res.toast();
    }
  }

  MedalWallData? _cacheMedalData;
  Future<void> _showLiveMedalWall() async {
    void onShow() {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => MedalWall(response: _cacheMedalData!),
      );
    }

    if (_cacheMedalData != null) {
      onShow();
      return;
    }
    SmartDialog.showLoading();
    final res = await LiveHttp.liveMedalWall(mid: _mid);
    SmartDialog.dismiss();
    if (res case Success(:final response)) {
      _cacheMedalData = response;
      onShow();
    } else {
      res.toast();
    }
  }

  void _toWebArchive() {
    final items = _renderedSections?.contributions;
    final index = _contributions?.index ?? 0;
    if (items != null && index < items.length) {
      final archive = spaceWebArchive(items[index]);
      if (archive != null) {
        MemberSSWeb.toMemberSSWeb(
          type: archive.isSeason ? .season : .series,
          id: archive.id,
          mid: _mid,
          name: _userController.username ?? '',
        );
        return;
      }
    }
    MemberVideoWeb.toMemberVideoWeb(
      mid: _mid,
      name: _userController.username ?? '',
    );
  }

  void _createShortcut() {
    if (Platform.isAndroid) {
      _createShortcutAndroid();
    }
  }

  late final _shortcutAction = MemberShortcutAction();

  Future<void> _createShortcutAndroid() {
    final route = ModalRoute.of(context);
    final source = _userController.loadingState.value;
    final account = _userController.account;
    final mid = _userController.mid;
    final name = _userController.username;
    final avatar = _userController.userAvatar;
    return _shortcutAction.run(
      mid: mid,
      username: name,
      avatar: avatar,
      isCurrent: () =>
          mounted &&
          (route?.isCurrent ?? true) &&
          !_userController.isClosed &&
          identical(source, _userController.loadingState.value) &&
          identical(account, _userController.account) &&
          _userController.mid == mid &&
          _userController.username == name &&
          _userController.userAvatar == avatar,
    );
  }
}
