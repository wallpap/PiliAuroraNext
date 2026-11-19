import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/emote/data.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';
import 'package:pili_aurora_next/features/community/domain/emote/recent_emote.dart';
import 'package:pili_aurora_next/features/community/domain/emote/setting_panel.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
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
      Request().requestApi(
        Api.myEmote,
        kind: ApiCallKind.query,
        options: Options(extra: {'account': account}),
        decode: (body) => EmoteModelData.fromJson(body['data']).packages,
        queryParameters: {'business': 'reply', 'web_location': '333.1245'},
      );

  Future<LoadingState<EmoteSettingPanel>> settingPanel(Account account) =>
      Request().requestApi(
        Api.emoteSettingPanel,
        kind: ApiCallKind.query,
        decode: (body) => EmoteSettingPanel.fromJson(body['data']),
        queryParameters: {'business': 'reply'},
        options: Options(extra: {'account': account}),
      );

  Future<LoadingState<List<Package>>> categoryPackages(
    Account account,
    int type, {
    bool Function()? isCurrent,
  }) async {
    final packages = <Package>[];
    final ids = <int>{};
    for (var page = 1; page <= 100; page++) {
      final result = await Request().requestApi(
        Api.myEmotePackages,
        kind: ApiCallKind.query,
        decode: (body) {
          final data = body['data'] as Map<String, dynamic>;
          final total = data['total'] as int;
          if (total < 0) throw const FormatException('表情包总数无效');
          final items = (data['packages'] as List? ?? [])
              .map((item) => Package.fromJson(item as Map<String, dynamic>))
              .toList();
          if (items.any((item) => (item.id ?? 0) <= 0)) {
            throw const FormatException('表情包缺少有效 ID');
          }
          return (items: items, total: total);
        },
        queryParameters: {
          'business': 'reply',
          'type': type,
          'pn': page,
          'ps': 100,
        },
        options: Options(extra: {'account': account}),
      );
      if (isCurrent?.call() == false) return const Error('表情包列表加载已取消');
      if (result is Error) return result;
      final (:items, :total) = result.data;
      if (items.isEmpty && packages.length < total) {
        return const Error('表情包列表未能完整加载，请刷新重试');
      }
      final fresh = items.where((item) => ids.add(item.id!)).toList();
      if (items.isNotEmpty && fresh.isEmpty) {
        return const Error('表情包列表未能继续加载，请刷新重试');
      }
      packages.addAll(fresh);
      if (packages.length >= total) {
        return Success(List.unmodifiable(packages));
      }
    }
    return const Error('表情包列表超出加载上限，请稍后重试');
  }

  Future<LoadingState<Package>> packageDetail(Account account, int packageId) =>
      Request().requestApi(
        Api.emotePackageDetail,
        kind: ApiCallKind.query,
        decode: (body) {
          final package = Package.fromJson(body['data']['package']);
          if (package.id != packageId) {
            throw const FormatException('表情包 ID 不匹配');
          }
          return package;
        },
        queryParameters: {'id': packageId, 'business': 'reply'},
        options: Options(extra: {'account': account}),
      );

  Future<LoadingState<void>> changePackage(
    Account account,
    int packageId, {
    required bool add,
  }) => Request().requestApi<void>(
    add ? Api.addEmotePackage : Api.removeEmotePackage,
    kind: ApiCallKind.mutation,
    decode: (_) {},
    data: {
      'package_id': packageId,
      'business': 'reply',
      'csrf': account.csrf,
    },
    options: Options(
      extra: {'account': account},
      contentType: Headers.formUrlEncodedContentType,
    ),
  );

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
