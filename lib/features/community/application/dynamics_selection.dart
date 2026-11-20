import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

final dynamicsPreferencesProvider = Provider(
  (ref) => (
    position: Pref.upPanelPosition,
    showLive: Pref.expandDynLivePanel,
    initialTab: Pref.defaultDynamicTypeIndex,
    allFollowed: Pref.dynamicsShowAllFollowedUp,
  ),
);

class DynamicsSelection {
  const DynamicsSelection({
    this.mid = -1,
    this.hostMid = -1,
    this.banned = const {},
  });
  final int mid, hostMid;
  final Set<int> banned;
}

// 临时屏蔽属于当前主账号的应用会话；面板卸载不撤销用户选择。
final dynamicsSelectionProvider =
    NotifierProvider<DynamicsSelectionNotifier, DynamicsSelection>(
      DynamicsSelectionNotifier.new,
    );

class DynamicsSelectionNotifier extends Notifier<DynamicsSelection> {
  @override
  DynamicsSelection build() {
    ref.watch(mainAccountProvider);
    return const DynamicsSelection();
  }

  void select(int mid) => state = DynamicsSelection(
    mid: mid,
    hostMid: mid == -1 ? state.hostMid : mid,
    banned: state.banned,
  );
  void block(int mid) => state = DynamicsSelection(
    mid: state.mid,
    hostMid: state.hostMid,
    banned: Set.unmodifiable({...state.banned, mid}),
  );
}
