import 'dart:convert';

import 'package:pili_aurora_next/build_config.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/features/sponsor_block/data/sponsor_block_preferences.dart';
import 'package:pili_aurora_next/features/sponsor_block/data/sponsor_block_transport.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/sponsor_block_api.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/post_segment_model.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_response/segment_item.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_response/user_info.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

typedef SponsorBlockIdentity = ({String server, String userId});

abstract final class SponsorBlock {
  static String get server => SponsorBlockPreferences.server;
  static bool get showSkipToast => SponsorBlockPreferences.toast;
  static bool get trackSkips => SponsorBlockPreferences.track;
  static SponsorBlockIdentity get identity =>
      (server: server, userId: SponsorBlockPreferences.userId);

  static List<SegmentItemModel> _segments(dynamic body) =>
      (body as List).map((item) => SegmentItemModel.fromJson(item)).toList();

  static String _requiredString(dynamic body, String field) {
    if (body is Map<String, dynamic>) {
      if (body[field] case final String value when value.trim().isNotEmpty) {
        return value;
      }
    }
    throw FormatException('空降助手响应缺少有效 $field');
  }

  static Future<LoadingState<List<SegmentItemModel>>> getSkipSegments({
    required String bvid,
    required int cid,
    String? server,
  }) => SponsorBlockTransport.request(
    server ?? SponsorBlock.server,
    SponsorBlockApi.skipSegments,
    kind: ApiCallKind.query,
    decode: _segments,
    queryParameters: {'videoID': bvid, 'cid': cid},
  );

  static Future<LoadingState<void>> voteOnSponsorTime({
    required String uuid,
    int? type,
    SegmentType? category,
    SponsorBlockIdentity? identity,
  }) async {
    if (uuid.trim().isEmpty || (type == null) == (category == null)) {
      return const Error('请选择有效片段及一种投票方式');
    }
    final source = identity ?? SponsorBlock.identity;
    return SponsorBlockTransport.request<void>(
      source.server,
      SponsorBlockApi.voteOnSponsorTime,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      queryParameters: {
        'UUID': uuid,
        'type': ?type,
        'category': ?category?.name,
        'userID': source.userId,
      },
    );
  }

  static Future<LoadingState<void>> viewedVideoSponsorTime(String uuid) async {
    if (uuid.trim().isEmpty) return const Error('片段标识无效');
    return SponsorBlockTransport.request<void>(
      server,
      SponsorBlockApi.viewedVideoSponsorTime,
      kind: ApiCallKind.mutation,
      decode: (_) {},
      data: {'UUID': uuid},
    );
  }

  static Future<LoadingState<void>> uptimeStatus({String? server}) =>
      SponsorBlockTransport.request<void>(
        server ?? SponsorBlock.server,
        SponsorBlockApi.uptimeStatus,
        kind: ApiCallKind.query,
        decode: (body) {
          final value = body is String ? double.tryParse(body) : null;
          if (value == null || !value.isFinite || value < 0) {
            throw const FormatException('空降助手运行状态无效');
          }
        },
      );

  static Future<LoadingState<UserInfo>> userInfo(
    List<String> query, {
    String? userId,
    String? server,
  }) => SponsorBlockTransport.request(
    server ?? SponsorBlock.server,
    SponsorBlockApi.userInfo,
    kind: ApiCallKind.query,
    decode: (body) => UserInfo.fromJson(body),
    queryParameters: {
      'userID': userId ?? SponsorBlockPreferences.userId,
      'values': jsonEncode(query),
    },
  );

  static Future<LoadingState<List<SegmentItemModel>>> postSkipSegments({
    required String bvid,
    required int cid,
    required double videoDuration,
    required List<PostSegmentModel> segments,
    SponsorBlockIdentity? identity,
  }) async {
    if (bvid.trim().isEmpty ||
        cid <= 0 ||
        !videoDuration.isFinite ||
        videoDuration <= 0) {
      return const Error('视频信息尚未就绪，请稍后再提交');
    }
    if (segments.isEmpty ||
        segments.any((item) {
          final start = item.segment.first;
          final end = item.segment.second;
          return !start.isFinite ||
              !end.isFinite ||
              start < 0 ||
              end < start ||
              end > videoDuration;
        })) {
      return const Error('请检查片段的开始和结束时间');
    }
    final source = identity ?? SponsorBlock.identity;
    return SponsorBlockTransport.request(
      source.server,
      SponsorBlockApi.skipSegments,
      kind: ApiCallKind.mutation,
      decode: _segments,
      data: {
        'videoID': bvid,
        'cid': cid.toString(),
        'userID': source.userId,
        'userAgent': kDebugMode
            ? Constants.userAgent
            : '${Constants.appName}/${BuildConfig.versionName}',
        'videoDuration': videoDuration,
        'segments': segments
            .map(
              (item) => {
                'segment': [item.segment.first, item.segment.second],
                'category': item.category.name,
                'actionType': item.actionType.name,
              },
            )
            .toList(),
      },
    );
  }

  static Future<LoadingState<String>> getPortVideo({
    required String bvid,
    required int cid,
    String? server,
  }) => SponsorBlockTransport.request(
    server ?? SponsorBlock.server,
    SponsorBlockApi.portVideo,
    kind: ApiCallKind.query,
    decode: (body) => _requiredString(body, 'ytbID'),
    queryParameters: {'videoID': bvid, 'cid': cid.toString()},
  );

  static Future<LoadingState<String>> postPortVideo({
    required String bvid,
    required int cid,
    required String ytbId,
    required int videoDuration,
    SponsorBlockIdentity? identity,
  }) async {
    if (bvid.trim().isEmpty ||
        cid <= 0 ||
        ytbId.trim().isEmpty ||
        videoDuration <= 0) {
      return const Error('视频绑定信息不完整，请重新打开视频');
    }
    final source = identity ?? SponsorBlock.identity;
    return SponsorBlockTransport.request(
      source.server,
      SponsorBlockApi.portVideo,
      kind: ApiCallKind.mutation,
      decode: (body) => _requiredString(body, 'UUID'),
      data: {
        'bvID': bvid,
        'cid': cid.toString(),
        'ytbID': ytbId,
        'userID': source.userId,
        'biliDuration': videoDuration,
      },
    );
  }
}
