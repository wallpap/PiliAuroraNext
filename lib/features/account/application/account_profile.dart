import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/application/coin_balance.dart';
import 'package:pili_aurora_next/features/account/data/profile_repository.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/features/account/domain/stat.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

export 'package:pili_aurora_next/features/account/domain/info.dart';
export 'package:pili_aurora_next/features/account/domain/stat.dart';

class ProfileReceipt {
  const ProfileReceipt(this.result, {this.cacheError});
  final LoadingState<UserInfoData> result;
  // 远端成功已经发布，本地失败单独交付，不能诱导重复修改资料。
  final Object? cacheError;
}

/// 登录、查询和编辑共用发布顺序；账号身份仍由 Accounts 独占。
class AccountProfile {
  AccountProfile(this.repository, {Account Function()? currentAccount})
    : _currentAccount = currentAccount ?? (() => Accounts.main);

  static final legacy = AccountProfile(const ProfileRepository());
  final ProfileRepository repository;
  final Account Function() _currentAccount;
  final _changes = StreamController<(Account, UserInfoData)>.broadcast(
    sync: true,
  );
  Stream<(Account, UserInfoData)> get changes => _changes.stream;
  int _revision = 0;
  (Account, UserInfoData)? _confirmed;
  Future<void>? _cacheTail;

  bool owns(Account account) => identical(account, _currentAccount());
  UserInfoData? get currentInfo => cached(_currentAccount());

  UserInfoData? cached(Account account) => !account.isLogin
      ? null
      : identical(_confirmed?.$1, account)
      ? _confirmed!.$2
      : repository.cached(account);

  Future<ProfileReceipt?> refresh(
    Account account, {
    bool Function()? isActive,
  }) => _refresh(account, isActive: isActive);

  // 同账号的页面刷新可以淘汰资料快照，但不能取消已确认登录后的原生同步。
  Future<ProfileReceipt?> confirmLogin(Account account) =>
      _refresh(account, retainLoginConfirmation: true);

  Future<ProfileReceipt?> _refresh(
    Account account, {
    bool Function()? isActive,
    bool retainLoginConfirmation = false,
  }) async {
    if (!account.isLogin || !owns(account)) return null;
    final revision = ++_revision;
    bool current() =>
        owns(account) && revision == _revision && (isActive?.call() ?? true);
    if (!account.isLogin || !current()) return null;
    LoadingState<UserInfoData> result;
    try {
      result = await repository.profile(account);
    } catch (error, stack) {
      result = Error('账号资料读取失败，请重试', cause: error, stackTrace: stack);
    }
    if (!current()) {
      if (result case Success(:final response)
          when retainLoginConfirmation &&
              owns(account) &&
              response.isLogin == true &&
              response.mid == account.mid) {
        return ProfileReceipt(result);
      }
      return null;
    }
    if (result case Success(:final response)) {
      if (response.isLogin != true) {
        return const ProfileReceipt(Error('账号未登录'));
      }
      if (response.mid != account.mid) {
        return const ProfileReceipt(Error('账号资料身份不匹配，请重试'));
      }
      final receipt = await _publish(account, response, current);
      return current() || (retainLoginConfirmation && owns(account))
          ? receipt
          : null;
    }
    return ProfileReceipt(result);
  }

  Future<ProfileReceipt?> updateDisplay(
    Account account, {
    String? name,
    String? avatar,
  }) {
    if (!owns(account)) return Future.value();
    ++_revision;
    final info =
        (cached(account) ?? UserInfoData(mid: account.mid, isLogin: true))
            .withDisplay(name: name, avatar: avatar);
    return _publish(account, info, () => owns(account), updateCoins: false);
  }

  Future<ProfileReceipt> _publish(
    Account account,
    UserInfoData info,
    bool Function() current, {
    bool updateCoins = true,
  }) async {
    _confirmed = (account, info);
    if (updateCoins) CoinBalance.instance.confirm(account, info.money);
    _changes.add((account, info));
    Object? cacheError;
    final previous = _cacheTail;
    Future<void> writeCache() async {
      if (previous != null) await previous;
      if (current()) await repository.save(account, info);
    }

    final save = writeCache();
    final tail = _cacheTail = save.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(
      tail.then((_) {
        if (identical(_cacheTail, tail)) _cacheTail = null;
      }),
    );
    try {
      await save;
    } catch (error) {
      cacheError = error;
    }
    return ProfileReceipt(Success(info), cacheError: cacheError);
  }

  Future<void> dispose() => _changes.close();
}

final accountProfileModuleProvider = Provider<AccountProfile>(
  (ref) => AccountProfile.legacy,
);

class ProfileState {
  const ProfileState({
    this.info,
    this.loading = false,
    this.error,
    this.cacheError,
  });
  final UserInfoData? info;
  final bool loading;
  final Object? error;
  final Object? cacheError;
}

final accountProfileProvider =
    NotifierProvider<AccountProfileNotifier, ProfileState>(
      AccountProfileNotifier.new,
      isAutoDispose: true,
    );

class AccountProfileNotifier extends Notifier<ProfileState> {
  int _request = 0;
  @override
  ProfileState build() {
    final account = ref.watch(mainAccountProvider);
    final module = ref.watch(accountProfileModuleProvider);
    final life = ref;
    var active = true;
    final subscription = module.changes.listen((event) {
      if (active && identical(event.$1, account)) {
        state = ProfileState(info: event.$2);
      }
    });
    ref.onDispose(() {
      active = false;
      unawaited(subscription.cancel());
    });
    if (account.isLogin) {
      Future.microtask(() {
        if (active && life.mounted) unawaited(refresh());
      });
    }
    return ProfileState(info: module.cached(account));
  }

  Future<void> refresh() async {
    final request = ++_request;
    final life = ref;
    final account = ref.read(mainAccountProvider);
    if (!account.isLogin) return;
    final module = ref.read(accountProfileModuleProvider);
    var active = true;
    ref.onDispose(() => active = false);
    state = ProfileState(info: state.info, loading: true);
    final receipt = await module.refresh(
      account,
      isActive: () => active && life.mounted,
    );
    if (!active || !life.mounted || request != _request) return;
    if (receipt == null) {
      state = ProfileState(info: state.info);
      return;
    }
    state = ProfileState(
      info: receipt.result.dataOrNull ?? state.info,
      error: receipt.result is Error ? receipt.result : null,
      cacheError: receipt.cacheError,
    );
    if (receipt.result case Error error when error.toString() == '账号未登录') {
      try {
        if (module.owns(account)) await Accounts.deleteAll({account});
      } catch (error, stack) {
        logger.w('账号注销后的本地清理失败', error: error.runtimeType, stackTrace: stack);
      }
    }
  }
}

final accountStatsProvider = FutureProvider.autoDispose<UserStat>((ref) async {
  final account = ref.watch(mainAccountProvider);
  if (!account.isLogin) return const UserStat();
  return (await ref
          .watch(accountProfileModuleProvider)
          .repository
          .stats(account))
      .data;
});
