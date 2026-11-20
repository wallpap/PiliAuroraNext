import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/application/comments/comments.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../support/comment_fixture.dart';

import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final responses = Queue<Object>();
  final requests = <MainListReq>[];
  late ProviderContainer container;
  late Comments controller;
  late CommentsQuery query;
  CommentsState snapshot() => container.read(commentsProvider(query));
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
  }

  Future<void> loaded() async {
    await until(() => requests.isNotEmpty);
    await until(() => !snapshot().busy);
  }

  MainListReply page(
    int id, {
    bool blocked = true,
    int? next,
    bool end = false,
  }) => MainListReply(
    replies: [
      ReplyInfo(
        id: Int64(id),
        content: Content(message: blocked ? 'blocked' : 'allowed'),
      ),
    ],
    cursor: CursorReply(next: Int64(next ?? id), isEnd: end),
    subjectControl: SubjectControl(count: Int64(100)),
  );
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(
              MainListReq.fromBuffer(GrpcReq.decompressProtobuf(options.data)),
            );
            var body = responses.removeFirst();
            if (body is Future<MainListReply>) body = await body;
            handler.resolve(
              Response(
                requestOptions: options,
                headers: Headers.fromMap({
                  'grpc-status': [body is MainListReply ? '0' : '13'],
                }),
                data: body is MainListReply
                    ? GrpcReq.compressProtobuf(body.writeToBuffer())
                    : null,
              ),
            );
          },
        ),
      );
  });
  LoginAccount account(String token) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': token}),
    null,
    null,
  );
  setUp(() async {
    responses.clear();
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account('old');
    await GStorage.setting.put(SettingBoxKey.banWordForReply, 'blocked');
    query = commentQuery();
    container = ProviderContainer.test();
    final provider = commentsProvider(query);
    container.listen(provider, (_, _) {});
    controller = container.read(provider.notifier);
  });
  tearDownAll(() => Request.dio.close(force: true));

  test(
    'keyword filtered first page continues with the server cursor',
    () async {
      responses.addAll([page(1), page(2, blocked: false, end: true)]);
      await loaded();
      expect(requests.map((r) => r.cursor.next.toInt()), [0, 1]);
      expect(snapshot().loading.dataOrNull!.single.id.toInt(), 2);
      expect(!snapshot().hasMore, isTrue);
    },
  );

  test('five filtered pages yield and allow explicit continuation', () async {
    responses.addAll([
      for (var i = 1; i <= 5; i++) page(i),
      page(6, blocked: false, end: true),
    ]);
    await loaded();
    expect(requests, hasLength(5));
    expect(snapshot().loading.dataOrNull, isEmpty);
    expect(snapshot().hasMore, isTrue);
    await controller.loadMore(retry: true);
    expect(requests, hasLength(6));
    expect(snapshot().loading.dataOrNull!.single.id.toInt(), 6);
  });

  test('repeated cursor stops automatic and manual pagination', () async {
    responses.addAll([page(1, next: 7), page(2, next: 7)]);
    await loaded();
    expect(requests, hasLength(2));
    expect(!snapshot().hasMore, isTrue);
    await controller.loadMore(retry: true);
    expect(requests, hasLength(2));
  });

  test(
    'filtered middle page preserves existing replies and reads the next page',
    () async {
      responses.addAll([
        page(1, blocked: false),
        page(2),
        page(3, blocked: false, end: true),
      ]);
      await loaded();
      expect(requests, hasLength(1));
      await controller.loadMore(retry: true);
      expect(requests, hasLength(3));
      expect(
        snapshot().loading.dataOrNull!.map((r) => r.id.toInt()),
        [1, 3],
      );
    },
  );

  test('failed refill preserves the last cursor for retry', () async {
    responses.addAll([page(1), 'failure', page(2, blocked: false, end: true)]);
    await loaded();
    expect(snapshot().loading.dataOrNull, isEmpty);
    expect(snapshot().hasMore, isTrue);
    await controller.loadMore(retry: true);
    expect(requests.map((r) => r.cursor.next.toInt()), [0, 1, 1]);
    expect(snapshot().loading.dataOrNull!.single.id.toInt(), 2);
  });

  test(
    'account replacement prevents refill after a late filtered page',
    () async {
      final reply = Completer<MainListReply>();
      responses.add(reply.future);
      await until(() => requests.length == 1);
      responses.add(Completer<MainListReply>().future);
      Accounts.replaceCredentials(account('new'));
      await container.pump();
      reply.complete(page(1));
      await until(() => requests.length == 2);
      expect(requests.map((r) => r.cursor.next.toInt()), [0, 0]);
      expect(snapshot().loading, isA<Loading>());
    },
  );
}
