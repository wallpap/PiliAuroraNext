import 'package:dio/dio.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/common/service_urls.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/profile_details.dart';
import 'package:pili_aurora_next/features/account/domain/profile_type.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/app_sign.dart';

/// 账号资料查询及写入，账号和签名参数属于同一次操作。
abstract final class ProfileEditorRepository {
  static Map<String, String> _appParameters(Account account) => {
    'access_key': ?account.accessKey,
    'build': '2001100',
    'c_locale': 'zh_CN',
    'channel': 'master',
    'mobi_app': 'android_hd',
    'platform': 'android',
    's_locale': 'zh_CN',
    'statistics': Constants.statistics,
  };

  static Future<LoadingState<AccountMyInfoData>> info(Account account) async {
    if (!account.isLogin) return const Error('请先登录');
    final parameters = _appParameters(account);
    AppSign.appSign(parameters);
    return Request().requestApi(
      '${HttpString.appBaseUrl}/x/v2/account/myinfo',
      kind: ApiCallKind.query,
      queryParameters: parameters,
      options: Options(extra: {'account': account}),
      decode: (body) {
        final result = AccountMyInfoData.fromJson(body['data']);
        if (result.mid != account.mid ||
            (result.coins != null &&
                (!result.coins!.isFinite || result.coins! < 0))) {
          throw const FormatException('账号资料无效');
        }
        return result;
      },
    );
  }

  static Future<LoadingState<void>> update({
    required Account account,
    required ProfileType type,
    required String value,
  }) async {
    if (!account.isLogin || account.accessKey?.isNotEmpty != true) {
      return const Error('请退出账号后重新登录');
    }
    final parameters = _appParameters(account)
      ..[switch (type) {
            ProfileType.uname => 'uname',
            ProfileType.sign => 'user_sign',
            ProfileType.sex => 'sex',
            ProfileType.birthday => 'birthday',
          }] =
          value;
    AppSign.appSign(parameters);
    return Request().requestApi<void>(
      '/x/member/app/${type.name}/update',
      kind: ApiCallKind.mutation,
      data: parameters,
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
      decode: (_) {},
    );
  }

  static Future<LoadingState<void>> avatar({
    required Account account,
    required String filePath,
  }) async {
    if (!account.isLogin) return const Error('请先登录');
    final FormData data;
    try {
      data = FormData.fromMap({
        'dopost': 'save',
        'DisplayRank': 10000,
        'face': await MultipartFile.fromFile(filePath),
      });
    } catch (error, stackTrace) {
      return Error('头像文件读取失败，请重新选择', cause: error, stackTrace: stackTrace);
    }
    return Request().requestApi<void>(
      '/x/member/web/face/update',
      kind: ApiCallKind.mutation,
      queryParameters: {'csrf': account.csrf},
      data: data,
      options: Options(extra: {'account': account}),
      decode: (_) {},
    );
  }
}
