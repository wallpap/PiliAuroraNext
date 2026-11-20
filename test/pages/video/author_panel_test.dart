import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/member_space/application/space_archive.dart';
import 'package:pili_aurora_next/features/member_space/application/video_author.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final wire = ControlledInterceptor();
  final requests = wire.requests;
  final author = videoAuthorProvider((owner: Object(), mid: 3));
  final archive = anchoredSpaceArchiveProvider((
    owner: Object(),
    mid: 3,
    aid: '20',
  ));
  late ProviderContainer container;

  Account account(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  )..activated = true;

  Map<String, Object> profile(String name) => {
    'code': 0,
    'data': {'mid': 3, 'name': name, 'vip': <String, dynamic>{}},
  };

  Map<String, Object> segment(
    List<String> aids, {
    bool newer = false,
    bool older = false,
  }) => {
    'code': 0,
    'data': {
      'count': 3,
      'has_prev': newer,
      'has_next': older,
      'next': 999,
      'item': [
        for (final aid in aids) {'param': aid, 'title': aid},
      ],
    },
  };

  Future<void> waitFor<T>(
    NotifierProvider<Notifier<T>, T> provider,
    bool Function(T) ready,
  ) async {
    final found = Completer<void>();
    final sub = container.listen(provider, (_, value) {
      if (!found.isCompleted && ready(value)) found.complete();
    }, fireImmediately: true);
    try {
      await found.future.timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
  }

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox({
      LocalCacheKey.mixinKey: 'fixture',
      LocalCacheKey.timeStamp: DateTime.now().millisecondsSinceEpoch,
    });
    Accounts.account = MemoryBox<LoginAccount>();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(wire);
  });
  setUp(() {
    container = ProviderContainer.test();
    Accounts.accountMode[AccountType.main.index] = account('old');
    requests.clear();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await wire.close();
  });

  test('换凭据隔离迟到统计与关注回执；单项统计失败不覆盖资料和其它统计', () async {
    container.listen(author, (_, _) {});
    await wire.waitForRequests(1);
    requests[0].reply.complete(profile('旧资料'));
    await wire.waitForRequests(3);
    final old = container.read(author);
    final replacement = account('fresh') as LoginAccount;
    Accounts.replaceCredentials(replacement);
    await wire.waitForRequests(4);
    expect(requests[3].options.extra['account'], same(replacement));
    requests[3].reply.complete(profile('新资料'));
    await wire.waitForRequests(6);
    final fresh = requests.skip(4).toList();
    expect(
      fresh.map((r) => r.options.path),
      unorderedEquals([Api.userStat, Api.getMemberViewApi]),
    );
    expect(
      fresh.every((r) => identical(r.options.extra['account'], replacement)),
      isTrue,
    );

    container.read(author.notifier).setFollowed(old, true);
    for (final request in requests.getRange(1, 3)) {
      request.reply.complete({
        'code': 0,
        'data': {'follower': 999, 'likes': 999},
      });
    }
    fresh.firstWhere((r) => r.options.path == Api.userStat).reply.complete({
      'code': 0,
      'data': 'malformed',
    });
    fresh
        .firstWhere((r) => r.options.path == Api.getMemberViewApi)
        .reply
        .complete({
          'code': 0,
          'data': {'likes': 20},
        });
    await waitFor(author, (state) => state.likes == 20);
    final current = container.read(author);
    expect(current.profile.data.name, '新资料');
    expect(current.followers, isNull);
    expect(current.followed, isFalse);
  });

  test('作者投稿沿 AID 向两侧分页，续页失败重试，换排序回到当前视频', () async {
    container.listen(archive, (_, _) {});
    final listing = container.read(archive.notifier);
    Map<String, dynamic> params(int index) =>
        requests[index].options.queryParameters;
    Iterable<String?> aids() =>
        container.read(archive).loading.data.map((row) => row.param);

    await wire.waitForRequests(1);
    expect(params(0)['aid'], '20');
    expect(params(0)['include_cursor'], true);
    requests[0].reply.complete(segment(['20'], newer: true, older: true));
    await waitFor(archive, (state) => state.loading.isSuccess);

    final previous = listing.previous();
    await wire.waitForRequests(2);
    expect(params(1)['aid'], '20');
    expect(params(1)['sort'], 'asc');
    requests[1].reply.complete(segment(['30', '20']));
    expect((await previous).data, 1);
    expect(aids(), ['30', '20']);

    final next = listing.more();
    await wire.waitForRequests(3);
    expect(params(2)['aid'], '20');
    expect(params(2), isNot(contains('next')));
    expect(params(2), isNot(contains('include_cursor')));
    requests[2].reply.complete({'code': -403, 'message': '续页失败'});
    await next;
    expect(aids(), ['30', '20']);
    expect(container.read(archive).pageError?.code, -403);
    await listing.more();
    expect(requests, hasLength(3));

    final retry = listing.more(retry: true);
    await wire.waitForRequests(4);
    expect(params(3)['aid'], '20');
    requests[3].reply.complete(segment(['10']));
    await retry;
    expect(aids(), ['30', '20', '10']);
    expect(container.read(archive).hasNext, isFalse);

    final sorting = listing.toggleSort();
    await wire.waitForRequests(5);
    expect(params(4)['aid'], '20');
    expect(params(4)['include_cursor'], true);
    expect(params(4)['order'], 'click');
    requests[4].reply.complete(segment(['20', '30']));
    await sorting;
    expect(aids(), ['20', '30']);
  });
}
