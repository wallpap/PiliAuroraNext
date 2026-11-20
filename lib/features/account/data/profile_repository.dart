import 'package:pili_aurora_next/features/account/domain/info.dart';
import 'package:pili_aurora_next/features/account/domain/stat.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/user.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

class ProfileRepository {
  const ProfileRepository();

  UserInfoData? cached(Account account) {
    if (!account.isLogin) return null;
    final info =
        GStorage.userInfo.get('userInfoCache:${account.mid}') ??
        GStorage.userInfo.get('userInfoCache');
    // 旧版全局缓存只允许被相同 UID 读取，不能作为登录依据。
    return info?.mid == account.mid ? info : null;
  }

  Future<void> save(Account account, UserInfoData info) =>
      GStorage.userInfo.put('userInfoCache:${account.mid}', info);

  Future<LoadingState<UserInfoData>> profile(Account account) =>
      UserHttp.userInfo(account: account);

  Future<LoadingState<UserStat>> stats(Account account) =>
      UserHttp.userStatOwner(account: account);

  Future<LoadingState<num?>> coins(Account account) =>
      UserHttp.getCoin(account: account);
}
