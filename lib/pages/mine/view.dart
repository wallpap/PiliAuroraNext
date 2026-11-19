import 'package:pili_aurora_next/features/account/presentation/account_dashboard.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/scroll_bars.dart';
import 'package:pili_aurora_next/pages/common/common_page.dart';
import 'package:pili_aurora_next/features/app_shell/presentation/shell_actions.dart';
import 'package:pili_aurora_next/features/account/presentation/account_switch_dialog.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void openMinePage({bool showShellActions = false}) {
  Get.to(
    Material(
      child: ViewSafeArea(
        top: true,
        child: MinePage(showBackBtn: true, showShellActions: showShellActions),
      ),
    ),
  );
}

class MinePage extends StatefulWidget {
  const MinePage({
    super.key,
    this.showBackBtn = false,
    this.bars,
    this.isSelected,
    this.showShellActions = false,
  });

  final bool showBackBtn;
  final ShellScrollBars? bars;
  final bool Function()? isSelected;
  final bool showShellActions;

  @override
  State<MinePage> createState() => _MediaPageState();
}

class _MediaPageState extends CommonPageState<MinePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  ShellScrollBars? get scrollBars => widget.bars;

  @override
  bool get respondsToScroll => widget.isSelected?.call() ?? true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AccountDashboard(
      showBackBtn: widget.showBackBtn,
      showReply: GStorage.reply != null,
      wrapScroll: onBuild,
      onSwitchAccount: () => showAccountSwitchDialog(context),
      shellActions: widget.showShellActions
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: () => Get.toNamed('/search'),
                ),
                const MessageBadge(),
              ],
            )
          : null,
    );
  }
}
