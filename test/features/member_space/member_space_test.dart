import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/member_space/application/member_space.dart';
import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/data.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/memory_box.dart';

class _Account extends MainAccountNotifier {
  _Account(this.initial);
  final Account initial;
  @override
  Account build() => initial;
  void replace(Account value) => state = value;
}

class _Repository extends SpaceRepository {
  final requests =
      <(Account, int, String?, Completer<LoadingState<SpaceData>>)>[];
  @override
  Future<LoadingState<SpaceData>> space(Account account, int mid, String? aid) {
    final response = Completer<LoadingState<SpaceData>>();
    requests.add((account, mid, aid, response));
    return response.future;
  }
}

void main() {
  test('同 UID 换凭据和刷新使旧确认失效，空间实例独立保留查询参数', () async {
    GStorage.setting = MemoryBox();
    LoginAccount account(String csrf) => LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
      null,
      null,
    )..activated = true;
    final old = account('old');
    final fresh = account('fresh');
    final accounts = _Account(old);
    final repository = _Repository();
    final container = ProviderContainer.test(
      overrides: [
        mainAccountProvider.overrideWith(() => accounts),
        spaceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final page = spaceProvider((owner: Object(), mid: 9, fromViewAid: '17'));
    final other = spaceProvider((owner: Object(), mid: 9, fromViewAid: null));
    final sub = container.listen(page, (_, _) {});
    container.listen(other, (_, _) {});
    expect(repository.requests.map((r) => (r.$2, r.$3)), [
      (9, '17'),
      (9, null),
    ]);
    repository.requests[0].$4.complete(Success(SpaceData(relation: 4)));
    repository.requests[1].$4.complete(const Error('不可访问'));
    await container.read(page.future);
    expect((await container.read(other.future)).tabs.indexOf('contribute'), 1);
    final notifier = container.read(page.notifier);
    final first = notifier.capture();
    final inProgress = Completer<void>();
    final pending = notifier.runRelation((_, _) => inProgress.future);
    var calls = 0;
    await notifier.runRelation((_, _) async => calls++);
    expect(calls, 0);
    accounts.replace(fresh);
    expect(first(), isFalse);
    await container.pump();
    expect(sub.read().isLoading, isTrue);
    expect(
      repository.requests.skip(2).map((r) => identical(r.$1, fresh)),
      everyElement(isTrue),
    );
    for (final r in repository.requests.skip(2)) {
      r.$4.complete(Success(SpaceData(relation: 2)));
    }
    expect((await container.read(page.future)).relation, 2);
    inProgress.complete();
    await pending;
    final updated = notifier.capture();
    final refresh = notifier.refresh();
    expect(updated(), isFalse);
    repository.requests.last.$4.complete(Success(SpaceData(relation: 0)));
    await refresh;
    final disposed = notifier.capture();
    sub.close();
    await container.pump();
    expect(disposed(), isFalse);
  });
}
