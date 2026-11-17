import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/account/data/profile_repository.dart';
import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/features/account/domain/stat.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/global_data.dart';

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
  Future<void> _cacheTail = Future.value();

  bool owns(Account account) => identical(account, _currentAccount());
  UserInfoData? cached(Account account) => !account.isLogin
      ? null
      : identical(_confirmed?.$1, account)
      ? _confirmed!.$2
      : repository.cached(account);

  Future<ProfileReceipt?> refresh(
    Account account, {
    bool Function()? isActive,
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
    if (!current()) return null;
    if (result case Success(:final response)) {
      if (response.isLogin != true) {
        return const ProfileReceipt(Error('账号未登录'));
      }
      if (response.mid != account.mid) {
        return const ProfileReceipt(Error('账号资料身份不匹配，请重试'));
      }
      final receipt = await _publish(account, response, current);
      return current() ? receipt : null;
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
    return _publish(account, info, () => owns(account));
  }

  Future<ProfileReceipt> _publish(
    Account account,
    UserInfoData info,
    bool Function() current,
  ) async {
    _confirmed = (account, info);
    GlobalData().coins = info.money;
    _changes.add((account, info));
    Object? cacheError;
    final save = _cacheTail.then((_) async {
      if (current()) await repository.save(account, info);
    });
    _cacheTail = save.then<void>((_) {}, onError: (Object _, StackTrace _) {});
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
    if (!active || !life.mounted || receipt == null) return;
    state = ProfileState(
      info: receipt.result.dataOrNull ?? state.info,
      error: receipt.result is Error ? receipt.result : null,
      cacheError: receipt.cacheError,
    );
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
