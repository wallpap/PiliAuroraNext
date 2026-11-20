import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

typedef RecommendationPreferences = ({
  bool app,
  bool keepPrevious,
  bool showHistory,
});

final recommendationPreferencesProvider =
    NotifierProvider.autoDispose<
      RecommendationPreferencesNotifier,
      RecommendationPreferences
    >(RecommendationPreferencesNotifier.new);

class RecommendationPreferencesNotifier
    extends Notifier<RecommendationPreferences> {
  RecommendationPreferences _read() => (
    app: Pref.appRcmd,
    keepPrevious: Pref.enableSaveLastData,
    showHistory: Pref.savedRcmdTip,
  );
  @override
  RecommendationPreferences build() {
    final sub = GStorage.setting.watch().listen((event) {
      if (const {
        SettingBoxKey.appRcmd,
        SettingBoxKey.enableSaveLastData,
        SettingBoxKey.savedRcmdTip,
      }.contains(event.key)) {
        state = _read();
      }
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    return _read();
  }
}

final recommendationCardWidthProvider = Provider<double>(
  (ref) => Pref.recommendCardWidth,
);
