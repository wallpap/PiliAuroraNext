import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/msg.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final class DynamicPictureUpload {
  final _token = CancelToken();
  bool get isCancelled => _token.isCancelled;
  void cancel() => _token.cancel();

  Future<Map<String, dynamic>> upload(String path, Account account) async {
    final result = await MsgHttp.uploadBfs(
      account: account,
      path: path,
      category: 'daily',
      biz: 'new_dyn',
      cancelToken: _token,
    );
    final picture = result.data;
    return {
      'img_width': picture.imageWidth,
      'img_height': picture.imageHeight,
      'img_size': picture.imgSize,
      'img_src': picture.imageUrl,
    };
  }
}
