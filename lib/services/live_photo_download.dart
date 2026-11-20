import 'package:pili_aurora_next/core/text/string_ext.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

abstract final class LivePhotoDownload {
  static Future<void> saveMotionClip(String url, String destination) async {
    final response = await Request().downloadFile(url.http2https, destination);
    if (response.statusCode == 200) return;
    final data = response.data;
    throw Error(
      data is Map && data['message'] is String ? data['message'] : '视频下载失败，请重试',
      code: response.statusCode,
    );
  }
}
