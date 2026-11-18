import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/custom_toast.dart' as toast;
import 'package:pili_aurora_next/common/widgets/dialog/report_member.dart';
import 'package:pili_aurora_next/common/widgets/dynamic_sliver_app_bar/dynamic_sliver_app_bar.dart';
import 'package:pili_aurora_next/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_behavior.dart'
    show NoOverscrollIndicator;
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/remote/live/live_medal_wall/data.dart';
import 'package:pili_aurora_next/models/remote/space/space/reservation_card_list.dart';
import 'package:pili_aurora_next/pages/log_table/controller.dart';
import 'package:pili_aurora_next/pages/log_table/view.dart';
import 'package:pili_aurora_next/pages/login_devices/view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/member_space/application/member_space.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/utils/request_utils.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';
import 'package:pili_aurora_next/pages/member/shortcut_action.dart';
import 'package:pili_aurora_next/pages/member/widget/medal_wall.dart';
import 'package:pili_aurora_next/pages/member/widget/reserve_button.dart';
import 'package:pili_aurora_next/pages/member/widget/user_info_card.dart';
import 'package:pili_aurora_next/pages/member_cheese/view.dart';
import 'package:pili_aurora_next/features/member_space/domain/space_tabs.dart';
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

class MemberPage extends ConsumerStatefulWidget {
  const MemberPage({super.key});

  @override
  ConsumerState<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends ConsumerState<MemberPage>
    with TickerProviderStateMixin {
  late final int _mid;
  late final String _heroTag;
  late final SpaceQuery _query;
  MemberSpace get _space => ref.read(spaceProvider(_query).notifier);
  Future<void> _reload() => _space.refresh();
  final _scrollKey = GlobalKey<ExtendedNestedScrollViewState>();
  TabController? _sections;
  TabController? _contributions;
  SpaceTabs? _renderedSections;
  bool _contributionOpened = false;
  PageController? _headerController;

  void _syncTabs(SpaceTabs? sections) {
    if (identical(sections, _renderedSections)) return;
    _renderedSections = sections;
    _cacheFollowTime = null;
    _cacheMedalData = null;
    _sections?.dispose();
    _contributions?.dispose();
    _contributionOpened = false;
    _sections = sections == null || sections.tabs.isEmpty
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
    _query = (
      owner: Object(),
      mid: _mid,
      fromViewAid: Get.parameters['from_view_aid'],
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
    final state = ref.watch(spaceProvider(_query));
    final space = state.isLoading || state.hasError ? null : state.value;
    final response = space?.data;
    _syncTabs(space?.tabs);
    return Material(
      color: theme.surface,
      child: space == null
          ? state.hasError
                ? scrollErrorWidget(
                    errMsg: state.error.toString(),
                    onReload: _reload,
                  )
                : m3eLoading
          : ExtendedNestedScrollView(
              onlyOneScrollInBody: true,
              key: _scrollKey,
              scrollBehavior: const NoOverscrollIndicator(),
              pinnedHeaderSliverHeightBuilder: () =>
                  kToolbarHeight + MediaQuery.viewPaddingOf(context).top,
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                if (response?.card != null && response?.images != null) {
                  return [
                    DynamicSliverAppBar.medium(
                      actions: _actions(theme, space),
                      title: Text(space.username ?? ''),
                      flexibleSpace: UserInfoCard(
                        isOwner: _mid == space.account.mid,
                        relation: space.relation,
                        card: response!.card!,
                        images: response.images!,
                        onFollow: _scoped(_onFollow),
                        live: response.live,
                        silence: response.card?.silence,
                        headerControllerBuilder: getHeaderController,
                        showLiveMedalWall: _scoped(_showLiveMedalWall),
                        charges: response.elec?.list,
                        chargeCount: response.elec?.total,
                        guards: response.guard?.item,
                        guardCount: response.guard?.count,
                      ),
                    ),
                  ];
                }
                return [
                  SliverAppBar(
                    pinned: true,
                    actions: _actions(theme, space),
                    title: GestureDetector(
                      onTap: _reload,
                      behavior: HitTestBehavior.opaque,
                      child: Text(space.username ?? ''),
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
                                tabs: space.tabs.tabs
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
                          Expanded(child: _buildBody(space)),
                        ],
                      ),
                    )
                  : scrollableError,
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
    final current = _capture();
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
                        final sid = e.sid;
                        if (sid == null || !current()) return;
                        final isFollow = e.isFollow;
                        final res = await _space.reserve(sid, isFollow);
                        if (res == null || !current()) return;
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

  List<Widget> _actions(ColorScheme theme, SpaceSnapshot space) => [
    if (space.data?.reservationCardList?.isNotEmpty ?? false)
      _reserveBtn(space.data!.reservationCardList!, theme),
    IconButton(
      tooltip: '搜索',
      onPressed: () => Get.toNamed(
        '/memberSearch?mid=$_mid&uname=${space.username}',
      ),
      icon: const Icon(Icons.search_outlined),
    ),
    PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => <PopupMenuEntry>[
        if (space.account.isLogin && space.account.mid != _mid) ...[
          AppPopupMenuItem(
            onTap: _scoped(_blockUser),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 19),
                const SizedBox(width: 10),
                Text(
                  space.relation != 128 ? '加入黑名单' : '移除黑名单',
                ),
              ],
            ),
          ),
          if (space.isFollowed == 1)
            AppPopupMenuItem(
              onTap: _scoped(_removeFan),
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
          onTap: () => ShareUtils.shareText('https://space.bilibili.com/$_mid'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.share_outlined, size: 19),
              const SizedBox(width: 10),
              Text(
                space.account.mid != _mid ? '分享UP主' : '分享我的主页',
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
        if (space.account.isLogin)
          if (_mid == space.account.mid) ...[
            if ((space.data?.card?.vip?.status ?? 0) > 0)
              AppPopupMenuItem(
                onTap: _scoped(_claimExperience),
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
            if (space.isFollow)
              AppPopupMenuItem(
                onTap: _scoped(_showFollowTime),
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
                name: space.username,
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

  Widget _buildBody(SpaceSnapshot space) => tabBarView(
    hitTestBehavior: .translucent,
    controller: _sections,
    children: space.tabs.tabs.map((item) {
      return switch (item.param!) {
        'home' => MemberHome(
          data: space.data,
          mid: _mid,
          name: space.username,
          setting: space.spaceSetting,
          openSection: _openSection,
        ),
        'dynamic' => MemberDynamicsPage(mid: _mid),
        'contribute' => MemberContribute(
          heroTag: _heroTag,
          items: space.tabs.contributions,
          controller: _contributions,
          mid: _mid,
          navigation: (
            username: space.username,
            fromViewAid: _query.fromViewAid,
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

  bool Function() _capture() {
    final current = _space.capture();
    return () => mounted && current();
  }

  Future<void> Function() _scoped(Future<void> Function() action) {
    final current = _capture();
    return () async {
      if (current()) await action();
    };
  }

  Future<void> _runRelation(
    Future<void> Function(MemberSpace, SpaceSnapshot, bool Function()) action,
  ) async {
    final notifier = _space;
    await notifier.runRelation((space, ownsQuery) async {
      bool current() => mounted && ownsQuery();
      if (!current()) return;
      if (!space.account.isLogin) {
        SmartDialog.showToast('账号未登录');
      } else if (space.data == null) {
        SmartDialog.showToast('请先刷新空间信息');
      } else {
        await action(notifier, space, current);
      }
    });
  }

  Future<void> _blockUser() => _runRelation((notifier, space, current) async {
    if (_mid == space.account.mid) return;
    final wasBlocked = space.relation == 128;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提示'),
        content: Text(wasBlocked ? '从黑名单移除UP主' : '确定拉黑UP主?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('点错了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true && current()) {
      await _writeRelation(notifier, space, current, wasBlocked ? 6 : 5);
    }
  });

  Future<void> _onFollow() => _runRelation((notifier, space, current) async {
    if (_mid == space.account.mid) {
      Get.toNamed('/editProfile');
    } else if (space.relation == 128) {
      await _writeRelation(notifier, space, current, 6);
    } else {
      await RequestUtils.actionRelationMod(
        context: context,
        account: space.account,
        mid: _mid,
        isFollow: space.isFollow,
        isCurrent: current,
        afterMod: notifier.updateRelation,
      );
    }
  });

  Future<void> _removeFan() => _runRelation((notifier, space, current) async {
    if (_mid != space.account.mid && space.isFollowed == 1) {
      await _writeRelation(notifier, space, current, 7);
    }
  });

  Future<void> _writeRelation(
    MemberSpace notifier,
    SpaceSnapshot space,
    bool Function() current,
    int action,
  ) async {
    final result = await notifier.writeRelation(space.account, action);
    if (!current()) return;
    if (result.isSuccess) {
      switch (action) {
        case 5:
          notifier.updateRelation(128);
        case 6:
          notifier.updateRelation(0);
        case 7:
          notifier.updateRelation(
            space.relation == 4 ? 2 : space.relation,
            removedFan: true,
          );
          SmartDialog.showToast('移除成功');
      }
    } else {
      result.toast();
      if (result is UnknownResult) await notifier.refresh();
    }
  }

  Future<void> _claimExperience() async {
    final current = _capture();
    final result = await _space.claimExperience();
    if (!current() || result == null) return;
    if (result.isSuccess) {
      SmartDialog.showToast('领取成功');
    } else {
      result.toast();
    }
  }

  String? _cacheFollowTime;
  Future<void> _showFollowTime() async {
    final space = _space.snapshot;
    final current = _capture();
    if (space == null || !current()) return;
    void onShow() {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(space.username ?? ''),
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
    final res = await ref
        .read(spaceRepositoryProvider)
        .followTime(space.account, _mid);
    if (!current()) return;
    if (res case Success(:final response)) {
      if (response == null) return;
      _cacheFollowTime =
          '关注时间: ${DateFormatUtils.longFormatDs.format(
            DateTime.fromMillisecondsSinceEpoch(response * 1000),
          )}';
      onShow();
    } else {
      res.toast();
    }
  }

  MedalWallData? _cacheMedalData;
  bool _loadingMedals = false;
  Future<void> _showLiveMedalWall() async {
    final current = _capture();
    if (!current()) return;
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
    if (_loadingMedals) return;
    _loadingMedals = true;
    final tag = 'space-medals-${UniqueKey()}';
    final repository = ref.read(spaceRepositoryProvider);
    SmartDialog.show<void>(
      tag: tag,
      clickMaskDismiss: false,
      builder: (_) => const toast.LoadingWidget('加载中…'),
    );
    late final LoadingState<MedalWallData> res;
    try {
      res = await repository.medals(_mid);
    } finally {
      _loadingMedals = false;
      await SmartDialog.dismiss(tag: tag);
    }
    if (!current()) return;
    if (res case Success(:final response)) {
      _cacheMedalData = response;
      onShow();
    } else {
      res.toast();
    }
  }

  void _toWebArchive() {
    final space = _space.snapshot;
    if (space == null) return;
    final items = _renderedSections?.contributions;
    final index = _contributions?.index ?? 0;
    if (items != null && index < items.length) {
      final archive = spaceWebArchive(items[index]);
      if (archive != null) {
        MemberSSWeb.toMemberSSWeb(
          type: archive.isSeason ? .season : .series,
          id: archive.id,
          mid: _mid,
          name: space.username ?? '',
        );
        return;
      }
    }
    MemberVideoWeb.toMemberVideoWeb(
      mid: _mid,
      name: space.username ?? '',
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
    final source = _space.snapshot;
    final current = _capture();
    return _shortcutAction.run(
      mid: _mid,
      username: source?.username,
      avatar: source?.userAvatar,
      isCurrent: () => current() && (route?.isCurrent ?? true),
    );
  }
}
