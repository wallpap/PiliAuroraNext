import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/content_library/data/library_preferences.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

final libraryPreferencesProvider = Provider<LibraryPreferences>(
  (ref) => LibraryPreferences(),
);
final playAllProvider = NotifierProvider<PlayAllPreference, bool>(
  PlayAllPreference.new,
);

class PlayAllPreference extends Notifier<bool> {
  bool _saving = false;
  @override
  bool build() {
    final preferences = ref.watch(libraryPreferencesProvider);
    final subscription = preferences.changes.listen(
      (_) => state = preferences.playAll,
    );
    ref.onDispose(subscription.cancel);
    return preferences.playAll;
  }

  Future<LoadingState<void>> set(bool value) async {
    if (_saving) return const Error('设置保存中');
    _saving = true;
    final owner = ref;
    try {
      await owner.read(libraryPreferencesProvider).savePlayAll(value);
      if (owner.mounted) state = value;
      return const Success(null);
    } catch (error, stack) {
      return Error('连续播放设置保存失败', cause: error, stackTrace: stack);
    } finally {
      _saving = false;
    }
  }
}
