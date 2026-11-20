import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/services/desktop_playback_request.dart';

void main() {
  test('点播标识、分 P、番剧及当前位置经过 IPC 序列化保持不变', () {
    for (final type in VideoType.values) {
      final request = DesktopPlaybackRequest.video({
        'aid': 100,
        'bvid': 'video-id',
        'cid': 200,
        'videoType': type,
        'epId': 300,
        'seasonId': 400,
        'progress': 12345,
        'heroTag': 'desktop-200',
      });
      final decoded = DesktopPlaybackRequest.fromJson(
        jsonDecode(jsonEncode(request.toJson())),
      );
      expect(decoded.route, request.route);
      expect(decoded.arguments, request.arguments);
    }
  });
  test('直播请求及无效路由校验', () {
    const request = DesktopPlaybackRequest.live(123);
    expect(DesktopPlaybackRequest.fromJson(request.toJson()).arguments, 123);
    expect(
      () => DesktopPlaybackRequest.fromJson({'route': '/setting'}),
      throwsFormatException,
    );
    expect(
      () => DesktopPlaybackRequest.fromJson(
        const DesktopPlaybackRequest.live(0).toJson(),
      ),
      throwsFormatException,
    );
  });
  test('独立窗口请求不携带主窗口的离线列表快照', () {
    const request = DesktopPlaybackRequest.video({
      'aid': 100,
      'cid': 200,
      'videoType': VideoType.ugc,
      'offlineEntries': [Object()],
    });
    final decoded = DesktopPlaybackRequest.fromJson(
      jsonDecode(jsonEncode(request.toJson())),
    );
    expect((decoded.arguments as Map).containsKey('offlineEntries'), false);
    expect((request.arguments as Map).containsKey('offlineEntries'), true);
  });
}
