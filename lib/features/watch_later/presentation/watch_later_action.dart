import 'package:pili_aurora_next/features/account/application/account_scope.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

Future<void> addToWatchLater({String? bvid, Object? aid}) async {
  final owner = AccountScope.capture();
  final result = await LaterLibrary.legacy.add(
    bvid: bvid,
    aid: aid,
    account: owner.account,
  );
  if (!owner.isCurrent) return;
  if (result.isSuccess) {
    SmartDialog.showToast('已添加到稍后再看');
  } else {
    result.toast();
  }
}
