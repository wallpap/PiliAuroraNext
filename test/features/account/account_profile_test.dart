import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/account/data/profile_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/global_data.dart';

import '../../support/memory_box.dart';

class FakeProfiles extends ProfileRepository {
  final requests = <Completer<LoadingState<UserInfoData>>>[];
  final owners = <Account>[];
  final saved = <UserInfoData>[];
  UserInfoData? cache;
  bool failCache = false;

  @override
  UserInfoData? cached(Account account) =>
      cache?.mid == account.mid ? cache : null;
  @override
  Future<LoadingState<UserInfoData>> profile(Account account) {
    owners.add(account);
    final pending = Completer<LoadingState<UserInfoData>>();
    requests.add(pending);
    return pending.future;
  }

  @override
  Future<void> save(Account account, UserInfoData info) async {
    if (failCache) throw StateError('fixture');
    saved.add(info);
    cache = info;
  }
}

LoginAccount login(int mid) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture'}),
  null,
  null,
);
UserInfoData info(int mid, String name) => UserInfoData(
  mid: mid,
  uname: name,
  face: '$name.png',
  isLogin: true,
  money: 12,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeProfiles repository;
  late AccountProfile module;
  late Account owner;
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    GStorage.userInfo = MemoryBox<UserInfoData>();
  });
  setUp(() {
    owner = login(1);
    Accounts.accountMode[AccountType.main.index] = owner;
    repository = FakeProfiles();
    module = AccountProfile(repository, currentAccount: () => owner);
    GlobalData().coins = 0;
  });
  tearDown(() async {
    await module.dispose();
  });

  test('同 UID 新凭据使旧请求失效，旧资料不发布、不落盘、不改硬币', () async {
    final pending = module.refresh(owner);
    owner = login(1);
    repository.requests.single.complete(Success(info(1, 'old')));
    expect(await pending, isNull);
    expect(repository.saved, isEmpty);
    expect(GlobalData().coins, 0);
  });

  test('最新刷新优先，旧查询不覆盖确认快照', () async {
    final old = module.refresh(owner);
    final latest = module.refresh(owner);
    repository.requests[1].complete(Success(info(1, 'latest')));
    expect((await latest)?.result.data.uname, 'latest');
    repository.requests[0].complete(Success(info(1, 'old')));
    expect(await old, isNull);
    expect(module.cached(owner)?.uname, 'latest');
    expect(repository.saved.length, 1);
  });

  test('确认编辑废弃在途查询并复制快照，本地失败保留远端成功', () async {
    repository.cache = info(1, 'before');
    final original = repository.cache!;
    final pending = module.refresh(owner);
    repository.failCache = true;
    final receipt = await module.updateDisplay(
      owner,
      name: 'after',
      avatar: 'new',
    );
    expect(receipt?.result.isSuccess, isTrue);
    expect(receipt?.cacheError, isA<StateError>());
    expect(original.uname, 'before');
    expect(module.cached(owner)?.uname, 'after');
    expect(module.cached(owner)?.money, 12);
    repository.requests.single.complete(Success(info(1, 'old')));
    expect(await pending, isNull);
    expect(module.cached(owner)?.uname, 'after');
  });

  test('账号缓存只向所属 UID 提供，匿名身份不读取资料', () async {
    const real = ProfileRepository();
    await GStorage.userInfo.put('userInfoCache', info(1, 'legacy'));
    expect(real.cached(owner)?.uname, 'legacy');
    expect(real.cached(login(2)), isNull);
    expect(real.cached(AnonymousAccount()), isNull);
    await real.save(login(2), info(2, 'second'));
    expect(real.cached(login(2))?.uname, 'second');
    expect(real.cached(owner)?.uname, 'legacy');
  });

  test('provider 释放后不发布或写入迟到资料', () async {
    final container = ProviderContainer(
      overrides: [
        accountProfileModuleProvider.overrideWithValue(module),
      ],
    );
    container.listen(accountProfileProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests.length, 1);
    container.dispose();
    repository.requests.single.complete(Success(info(1, 'late')));
    await Future<void>.delayed(Duration.zero);
    expect(repository.saved, isEmpty);
    expect(GlobalData().coins, 0);
  });

  test('账号资料身份不符和未登录结果不能写入', () async {
    final pending = module.refresh(owner);
    repository.requests.single.complete(Success(info(2, 'wrong')));
    expect((await pending)?.result, isA<Error>());
    expect(repository.saved, isEmpty);
    final denied = module.refresh(owner);
    repository.requests.last.complete(Success(UserInfoData(isLogin: false)));
    expect((await denied)?.result.toString(), '账号未登录');
  });
}
