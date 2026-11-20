import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/account/data/account_adapter.dart';
import 'package:pili_aurora_next/features/account/application/login_sync.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:hive_ce/hive.dart';

abstract final class Accounts {
  static late final Box<LoginAccount> account;
  static final List<Account> accountMode = List.filled(
    AccountType.values.length,
    AnonymousAccount(),
  );
  static bool get mainEqVideo => main == video;
  static Account get main => accountMode[AccountType.main.index];
  static final _mainChanges = ValueNotifier(0);
  static ValueListenable<int> get mainChanges => _mainChanges;
  static final _recommendChanges = ValueNotifier(0);
  static ValueListenable<int> get recommendChanges => _recommendChanges;

  static void _onMainChanged() {
    Messaging.onAccountChanged();
    _mainChanges.value++;
  }

  static Account get video => accountMode[AccountType.video.index];
  static final _videoChanges = ValueNotifier(0);
  static ValueListenable<int> get videoChanges => _videoChanges;
  static Account? _temporaryHeartbeatOwner;
  static final _heartbeatChanges = ValueNotifier(0);
  static ValueListenable<int> get heartbeatChanges => _heartbeatChanges;

  /// 临时无痕只替换运行时角色，并通知历史查询使旧请求失效。
  static void setTemporaryHeartbeat(Account account) {
    _temporaryHeartbeatOwner ??= heartbeat;
    final previousHistory = history;
    accountMode[AccountType.heartbeat.index] = account;
    _heartbeatChanges.value++;
    if (!identical(previousHistory, history)) _historyChanges.value++;
  }

  static Account get heartbeat => accountMode[AccountType.heartbeat.index];
  static final _historyChanges = ValueNotifier(0);
  static ValueListenable<int> get historyChanges => _historyChanges;

  static Account get history {
    final heartbeat = Accounts.heartbeat;
    if (heartbeat is AnonymousAccount) {
      return Accounts.main;
    }
    return heartbeat;
  }

  /// 重新登录也会替换账号对象，使使用旧凭据的在途结果失效。
  static void replaceCredentials(LoginAccount account) {
    final previousHistory = history;
    final previousMain = main;
    final previousVideo = video;
    final previousHeartbeat = heartbeat;
    final previousRecommend = get(AccountType.recommend);
    if (_temporaryHeartbeatOwner?.mid == account.mid) {
      _temporaryHeartbeatOwner = account;
      account.type.add(AccountType.heartbeat);
    }
    for (final type in AccountType.values) {
      if (accountMode[type.index].mid == account.mid) {
        accountMode[type.index] = account;
        account.type.add(type);
      }
    }
    if (!identical(previousMain, main)) _onMainChanged();
    if (!identical(previousVideo, video)) _videoChanges.value++;
    if (!identical(previousHeartbeat, heartbeat)) _heartbeatChanges.value++;
    if (!identical(previousRecommend, get(AccountType.recommend))) {
      _recommendChanges.value++;
    }
    if (!identical(previousHistory, history)) _historyChanges.value++;
  }
  // static set main(Account account) => set(AccountType.main, account);

  static Future<void> init({Uint8List? bytes}) async {
    LoginAccountAdapter.readLegacy = false;
    account = await Hive.openBox(
      'account',
      bytes: bytes,
      compactionStrategy: (int entries, int deletedEntries) {
        return deletedEntries > 2;
      },
    );
    if (bytes == null && LoginAccountAdapter.readLegacy) {
      // 成功重写后压缩，清除文件中旧的明文记录；子进程快照只读。
      await account.putAll(account.toMap());
      await account.compact();
    }
  }

  static Future<void> refresh() {
    _temporaryHeartbeatOwner = null;
    for (final a in account.values) {
      for (final t in a.type) {
        accountMode[t.index] = a;
      }
    }
    _onMainChanged();
    _videoChanges.value++;
    _recommendChanges.value++;
    _historyChanges.value++;
    _heartbeatChanges.value++;
    return Future.wait(
      (accountMode.toSet()..removeWhere((i) => i.activated)).map(
        Request.buvidActive,
      ),
    );
  }

  static Future<void> clear() async {
    await account.clear();
    _temporaryHeartbeatOwner = null;
    for (int i = 0; i < AccountType.values.length; i++) {
      accountMode[i] = AnonymousAccount();
    }
    _onMainChanged();
    _videoChanges.value++;
    _recommendChanges.value++;
    _historyChanges.value++;
    _heartbeatChanges.value++;
    await AnonymousAccount().delete();
    Request.buvidActive(AnonymousAccount());
  }

  static Future<void> deleteAll(Set<Account> accounts) async {
    final previousHistory = history;
    final previousMain = Accounts.main;
    final previousVideo = video;
    final previousRecommend = get(AccountType.recommend);
    final isLoginMain = previousMain.isLogin;
    for (int i = 0; i < AccountType.values.length; i++) {
      if (accounts.contains(accountMode[i])) {
        accountMode[i] = AnonymousAccount();
      }
    }
    if (!identical(previousMain, Accounts.main)) {
      _onMainChanged();
    }
    if (!identical(previousVideo, video)) _videoChanges.value++;
    if (!identical(previousRecommend, get(AccountType.recommend))) {
      _recommendChanges.value++;
    }
    if (!identical(previousHistory, history)) _historyChanges.value++;
    await Future.wait(accounts.map((i) => i.delete()));
    if (accounts.contains(_temporaryHeartbeatOwner)) {
      _temporaryHeartbeatOwner = null;
    }
    _heartbeatChanges.value++;
    if (isLoginMain && !Accounts.main.isLogin) {
      await LoginSync.onLogoutMain();
    }
  }

  static Future<void> set(AccountType key, Account account) async {
    final previousHistory = history;
    final oldAccount =
        (key == AccountType.heartbeat
              ? _temporaryHeartbeatOwner ?? accountMode[key.index]
              : accountMode[key.index])
          ..type.remove(key);
    if (key == AccountType.heartbeat) _temporaryHeartbeatOwner = null;
    accountMode[key.index] = account..type.add(key);
    if (key == AccountType.main) _onMainChanged();
    if (key == AccountType.video) _videoChanges.value++;
    if (key == AccountType.recommend) _recommendChanges.value++;
    if (key == AccountType.heartbeat) _heartbeatChanges.value++;
    if (!identical(previousHistory, history)) _historyChanges.value++;
    await Future.wait([?account.onChange(), ?oldAccount.onChange()]);
    if (!account.activated) await Request.buvidActive(account);
    switch (key) {
      case AccountType.main:
        await (account.isLogin
            ? LoginSync.onLoginMain()
            : LoginSync.onLogoutMain());
        break;

      default:
        break;
    }
  }

  @pragma("vm:prefer-inline")
  static Account get(AccountType key) {
    return accountMode[key.index];
  }
}
