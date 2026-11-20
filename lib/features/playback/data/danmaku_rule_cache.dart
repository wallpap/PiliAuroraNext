import 'package:pili_aurora_next/features/playback/domain/danmaku_rule.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

abstract final class DanmakuRuleCache {
  static RuleFilter read() => GStorage.localCache.get(
    LocalCacheKey.danmakuFilterRules,
    defaultValue: RuleFilter.empty(),
  );

  static Future<void> save(RuleFilter filter) =>
      GStorage.localCache.put(LocalCacheKey.danmakuFilterRules, filter);
}
