import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';
import 'package:pili_aurora_next/features/community/domain/emote/recent_emote.dart';
import 'package:pili_aurora_next/http/reply.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/http/live.dart';
import 'package:pili_aurora_next/features/community/domain/live_emote/datum.dart';

final emoteRepositoryProvider = Provider((ref) => const EmoteRepository());

class EmoteRepository {
  const EmoteRepository();
  Future<LoadingState<List<LiveEmoteDatum>?>> livePackages(
    Account account,
    int roomId,
  ) => LiveHttp.getLiveEmoticons(account: account, roomId: roomId);
  Future<LoadingState<List<Package>?>> packages(Account account) =>
      ReplyHttp.getEmoteList(account: account, business: 'reply');
  List<RecentEmote> history() {
    final items = <RecentEmote>[];
    try {
      final raw = GStorage.localCache.get(LocalCacheKey.recentEmotes);
      if (raw is List) {
        for (final item in raw) {
          try {
            final recent = RecentEmote.fromJson(item as Map);
            if (recent.width != null &&
                (!recent.width!.isFinite || recent.width! <= 0)) {
              continue;
            }
            items.add(recent);
            if (items.length == 40) break;
          } catch (error, stack) {
            logger.w('跳过损坏的历史表情', error: error.runtimeType, stackTrace: stack);
          }
        }
      }
    } catch (error, stack) {
      logger.w('读取历史表情失败', error: error.runtimeType, stackTrace: stack);
    }
    return List.unmodifiable(items);
  }

  Future<void> saveHistory(List<RecentEmote> entries) async {
    try {
      await GStorage.localCache.put(
        LocalCacheKey.recentEmotes,
        entries.map((item) => item.toJson()).toList(),
      );
    } catch (error, stack) {
      logger.w('保存历史表情失败', error: error.runtimeType, stackTrace: stack);
    }
  }
}
