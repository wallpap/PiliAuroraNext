import 'package:pili_aurora_next/features/search/data/search_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/login/gaia_result.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

Future<LoadingState<String>?> requestSearchVerification({
  required String voucher,
  required Account account,
  required bool Function() isCurrent,
  required Future<Map<String, dynamic>?> Function(String, String) openChallenge,
}) async {
  if (!isCurrent()) return null;
  const repository = SearchRepository();
  const unconfirmed = Error('验证响应未能确认，请重新打开验证');
  final registration = await repository.registerChallenge(account, voucher);
  if (!isCurrent()) return null;
  if (registration is UnknownResult) return unconfirmed;
  if (registration is Error) return registration;
  final data = registration.data;
  final Map<String, dynamic>? json;
  try {
    json = await openChallenge(data.gt, data.challenge);
  } catch (error, stackTrace) {
    logger.w('打开风控验证失败', error: error.runtimeType, stackTrace: stackTrace);
    return isCurrent() ? const Error('无法打开验证，请重试') : null;
  }
  if (!isCurrent() || json == null) return null;
  final challenge = json['geetest_challenge'];
  final seccode = json['geetest_seccode'];
  final validate = json['geetest_validate'];
  if (challenge is! String ||
      seccode is! String ||
      validate is! String ||
      [challenge, seccode, validate].any((value) => value.trim().isEmpty)) {
    return const Error('验证结果不完整，请重新打开验证');
  }
  final result = await repository.submitChallenge(
    account: account,
    token: data.token,
    challenge: challenge,
    seccode: seccode,
    validate: validate,
  );
  if (!isCurrent()) return null;
  return switch (result) {
    Success(response: GaiaVerified(:final riskId)) => Success(riskId),
    Success(response: GaiaRejected()) => const Error('验证未通过，请重试'),
    UnknownResult() => unconfirmed,
    Error() => result,
    Loading() => null,
  };
}
