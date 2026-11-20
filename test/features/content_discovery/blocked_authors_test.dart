import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/application/blocked_authors.dart';
import 'package:pili_aurora_next/features/content_discovery/application/cooperative_authors.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_summary.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_id.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/memory_box.dart';

typedef _Request = ({
  RequestOptions options,
  RequestInterceptorHandler handler,
});

LoginAccount _account(int mid) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'fixture-csrf'}),
  null,
  null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<_Request> requests;
  late StreamIterator<_Request> iterator;
  late LoginAccount account;
  var accountId = 100;

  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
  });
  setUp(() {
    account = _account(accountId++);
    Accounts.accountMode[0] = account;
    requests = StreamController<_Request>();
    iterator = StreamIterator(requests.stream);
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add((options: options, handler: handler));
          },
        ),
      );
  });
  tearDown(() async {
    await iterator.cancel();
    await requests.close();
  });
  tearDownAll(() => Request.dio.close(force: true));

  Future<_Request> next([String path = Api.blackLst]) async {
    expect(await iterator.moveNext(), isTrue);
    final request = iterator.current;
    expect(request.options.path, path);
    return request;
  }

  void respond(_Request request, List<int> mids, int total) {
    request.handler.resolve(
      Response(
        requestOptions: request.options,
        data: {
          'code': 0,
          'data': {
            'total': total,
            'list': mids.map((mid) => {'mid': mid}).toList(),
          },
        },
      ),
    );
  }

  List<int>? persisted(int uid) =>
      (GStorage.localCache.get(LocalCacheKey.blackMidsByAccount)
              as Map?)?['$uid']
          as List<int>?;

  test('合并并发同步，完整读取多页后才更新账号缓存', () async {
    BlockedAuthors.setBlocked(999, true);
    final loading = BlockedAuthors.ensureLoaded();
    final shared = BlockedAuthors.ensureLoaded();
    final first = await next();
    expect(first.options.extra['account'], same(account));
    expect(first.options.queryParameters['pn'], 1);
    respond(first, List.generate(50, (i) => i + 1), 51);
    final second = await next();
    expect(second.options.queryParameters['pn'], 2);
    expect(BlockedAuthors.contains(999), isTrue);
    expect(BlockedAuthors.contains(1), isFalse);
    respond(second, [51], 51);
    await Future.wait([loading!, shared!]);
    expect(BlockedAuthors.contains(999), isFalse);
    expect(BlockedAuthors.contains(51), isTrue);
    expect(
      persisted(account.mid),
      unorderedEquals(List.generate(51, (i) => i + 1)),
    );
    expect(BlockedAuthors.ensureLoaded(), isNull);
  });

  test('后续页失败时保留完整缓存', () async {
    await GStorage.localCache.put(LocalCacheKey.blackMidsByAccount, {
      '${account.mid}': [999],
    });
    final loading = BlockedAuthors.ensureLoaded();
    respond(await next(), [7], 2);
    final second = await next();
    second.handler.resolve(
      Response(
        requestOptions: second.options,
        data: {'code': -1, 'message': 'fixture failure'},
      ),
    );
    await loading;
    expect(BlockedAuthors.contains(999), isTrue);
    expect(BlockedAuthors.contains(7), isFalse);
    expect(persisted(account.mid), [999]);
  });

  test('重复页不能靠条数覆盖本机完整名单', () async {
    BlockedAuthors.setBlocked(999, true);
    final loading = BlockedAuthors.ensureLoaded();
    respond(await next(), [7, 8], 4);
    respond(await next(), [7, 8], 4);
    await loading;
    expect(BlockedAuthors.contains(999), isTrue);
    expect(BlockedAuthors.contains(7), isFalse);
    expect(persisted(account.mid), [999]);
  });

  test('同步期间拉黑和解除操作优先于旧名单', () async {
    BlockedAuthors.setBlocked(7, true);
    final loading = BlockedAuthors.ensureLoaded();
    final request = await next();
    BlockedAuthors.setBlocked(7, false);
    BlockedAuthors.setBlocked(8, true);
    respond(request, [7, 9], 2);
    await loading;
    expect(BlockedAuthors.contains(7), isFalse);
    expect(BlockedAuthors.contains(8), isTrue);
    expect(BlockedAuthors.contains(9), isTrue);
    expect(persisted(account.mid), unorderedEquals([8, 9]));
  });

  test('账号切换隔离缓存及迟到的同步响应', () async {
    BlockedAuthors.setBlocked(7, true);
    final old = BlockedAuthors.ensureLoaded();
    final oldRequest = await next();
    final other = _account(accountId++);
    Accounts.accountMode[0] = other;
    expect(BlockedAuthors.hasBlockedAuthors, isFalse);
    final current = BlockedAuthors.ensureLoaded();
    final currentRequest = await next();
    respond(currentRequest, [8], 1);
    await current;
    respond(oldRequest, [9], 1);
    await old;
    expect(BlockedAuthors.contains(8), isTrue);
    expect(BlockedAuthors.contains(9), isFalse);
    Accounts.accountMode[0] = account;
    expect(BlockedAuthors.contains(7), isTrue);
    expect(BlockedAuthors.contains(8), isFalse);
    Accounts.accountMode[0] = AnonymousAccount();
    expect(BlockedAuthors.hasBlockedAuthors, isFalse);
    expect(BlockedAuthors.ensureLoaded(), isNull);
  });

  test('换凭据再切回时，原请求仍失效并保留最后确认的名单', () async {
    BlockedAuthors.setBlocked(7, true);
    final old = BlockedAuthors.ensureLoaded();
    final oldRequest = await next();
    Accounts.replaceCredentials(_account(account.mid));
    Accounts.replaceCredentials(account);
    respond(oldRequest, [9], 1);
    await old;
    expect(BlockedAuthors.contains(7), isTrue);
    expect(BlockedAuthors.contains(9), isFalse);
    final current = BlockedAuthors.ensureLoaded();
    respond(await next(), [8], 1);
    await current;
    expect(persisted(account.mid), [8]);
  });

  test('真正的空名单清空该账号缓存', () async {
    BlockedAuthors.setBlocked(7, true);
    final loading = BlockedAuthors.ensureLoaded();
    respond(await next(), [], 0);
    await loading;
    expect(BlockedAuthors.hasBlockedAuthors, isFalse);
    expect(persisted(account.mid), isEmpty);
  });

  test('合作作者补查通过现有详情接口绑定账号并读取staff', () async {
    await GStorage.localCache.put(
      LocalCacheKey.timeStamp,
      DateTime.now().millisecondsSinceEpoch,
    );
    await GStorage.localCache.put(LocalCacheKey.mixinKey, 'fixture-mixin-key');
    final authors = VideoAuthors(isCooperation: true);
    final query = CooperativeAuthors.shared.prepare([
      (aid: 123, bvid: IdUtils.av2bv(123), ownerMid: 8, authors: authors),
    ], isCurrent: () => true);
    final request = await next(Api.videoIntro);
    expect(request.options.extra['account'], same(account));
    expect(request.options.extra['noRetry'], isTrue);
    expect(request.options.queryParameters['bvid'], IdUtils.av2bv(123));
    expect(request.options.queryParameters['w_rid'], isNotEmpty);
    request.handler.resolve(
      Response(
        requestOptions: request.options,
        data: {
          'code': 0,
          'data': {
            'owner': {'mid': 8},
            'staff': [
              {'mid': 8},
              {'mid': '7'},
            ],
          },
        },
      ),
    );
    await query;
    expect(authors.mids, {7, 8});
  });
}
