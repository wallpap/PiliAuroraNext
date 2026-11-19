import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

typedef SearchOptions = ({
  bool trending,
  bool recommendations,
  bool suggestions,
});

class SearchLocalStore {
  const SearchLocalStore();

  List<String> readHistory() => List<String>.from(
    GStorage.historyWord.get('cacheList') ?? const <String>[],
  );

  Future<void> saveHistory(List<String> words) =>
      GStorage.historyWord.put('cacheList', words);

  Future<void> clearHistory() => GStorage.historyWord.delete('cacheList');

  bool get recordsHistory => Pref.recordSearchHistory;

  bool get showsDefaultWord => Pref.enableSearchWord;

  Stream<bool> watchDefaultWord() => GStorage.setting
      .watch(key: SettingBoxKey.enableSearchWord)
      .map((_) => showsDefaultWord);

  Stream<bool> watchRecordsHistory() => GStorage.setting
      .watch(key: SettingBoxKey.recordSearchHistory)
      .map((_) => recordsHistory);

  Future<void> setRecordsHistory(bool value) =>
      GStorage.setting.put(SettingBoxKey.recordSearchHistory, value);

  SearchOptions readOptions() => (
    trending: Pref.enableTrending,
    recommendations: Pref.enableSearchRcmd,
    suggestions: Pref.searchSuggestion,
  );
}
