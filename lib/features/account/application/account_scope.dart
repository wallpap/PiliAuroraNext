import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final class AccountScope {
  AccountScope.capture() : this._(AccountType.main, Accounts.mainChanges);

  AccountScope.captureVideo()
    : this._(AccountType.video, Accounts.videoChanges);

  AccountScope.captureHeartbeat()
    : this._(AccountType.heartbeat, Accounts.heartbeatChanges);

  AccountScope._(this._type, this._changes)
    : account = Accounts.get(_type),
      _revision = _changes.value;

  final AccountType _type;
  final ValueListenable<int> _changes;
  final Account account;
  final int _revision;

  static ValueListenable<int> get changes => Accounts.mainChanges;
  static bool get signedIn => Accounts.main.isLogin;
  static bool get mainUsesVideoCredentials => Accounts.mainEqVideo;

  bool get isCurrent =>
      _revision == _changes.value && identical(account, Accounts.get(_type));
}
