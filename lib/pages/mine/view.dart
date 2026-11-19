import 'package:pili_aurora_next/features/account/presentation/account_dashboard.dart';
import 'package:pili_aurora_next/models/common/nav_bar_config.dart';
import 'package:pili_aurora_next/pages/common/common_page.dart';
import 'package:pili_aurora_next/pages/home/view.dart';
import 'package:pili_aurora_next/features/account/presentation/account_switch_dialog.dart';
import 'package:pili_aurora_next/pages/main/controller.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key, this.showBackBtn = false});

  final bool showBackBtn;

  @override
  State<MinePage> createState() => _MediaPageState();
}

class _MediaPageState extends CommonPageState<MinePage>
    with AutomaticKeepAliveClientMixin {
  late final MainController _mainController = Get.find<MainController>();

  @override
  bool get wantKeepAlive => true;

  bool get checkPage =>
      _mainController.navigationBars[0] != NavigationBarType.mine &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AccountDashboard(
      showBackBtn: widget.showBackBtn,
      showReply: GStorage.reply != null,
      wrapScroll: onBuild,
      onSwitchAccount: () => showAccountSwitchDialog(context),
      shellActions: !_mainController.hasHome
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: () => Get.toNamed('/search'),
                ),
                msgBadge(_mainController),
              ],
            )
          : null,
    );
  }
}
