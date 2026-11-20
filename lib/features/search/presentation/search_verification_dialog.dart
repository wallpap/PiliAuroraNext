import 'dart:async';

import 'package:pili_aurora_next/features/search/application/search_verification.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/login/geetest/geetest_webview_dialog.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

Future<void> showSearchVerification(
  String voucher,
  FutureOr<void> Function(String) onSuccess, {
  required Account account,
  required bool Function() isCurrent,
}) async {
  final result = await requestSearchVerification(
    voucher: voucher,
    account: account,
    isCurrent: isCurrent,
    openChallenge: GeetestWebviewDialog.geetest,
  );
  if (!isCurrent()) return;
  switch (result) {
    case Success(response: final token):
      await onSuccess(token);
    case Error():
      unawaited(result.toast());
    default:
      break;
  }
}
