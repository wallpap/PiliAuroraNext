import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

final playAllProvider = NotifierProvider<PlayAllPreference, bool>(
  PlayAllPreference.new,
);

class PlayAllPreference extends Notifier<bool> {
  bool _saving = false;
  @override
  bool build() {
    final subscription = GStorage.setting
        .watch(key: SettingBoxKey.enablePlayAll)
        .listen((_) => state = Pref.enablePlayAll);
    ref.onDispose(subscription.cancel);
    return Pref.enablePlayAll;
  }

  Future<LoadingState<void>> set(bool value) async {
    if (_saving) return const Error('设置保存中');
    _saving = true;
    final owner = ref;
    try {
      await GStorage.setting.put(SettingBoxKey.enablePlayAll, value);
      if (owner.mounted) state = value;
      return const Success(null);
    } catch (error, stack) {
      return Error('连续播放设置保存失败', cause: error, stackTrace: stack);
    } finally {
      _saving = false;
    }
  }
}
