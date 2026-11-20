import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/generated/bilibili/pagination.pb.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/features/playback/domain/audio_track.dart';
import 'package:pili_aurora_next/generated/bilibili/app/listener/v1.pb.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/pages/audio/controller.dart';
import 'package:pili_aurora_next/pages/audio/view.dart';
import 'package:pili_aurora_next/services/audio_handler.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/controlled_http_adapter.dart';

class _Adapter extends ControlledHttpAdapter {
  void playlist(int index, List<int> ids, {String? prev, String? next}) =>
      pending[index].complete(
        ResponseBody.fromBytes(
          GrpcReq.compressProtobuf(
            PlaylistResp(
              list: ids.map(
                (id) => DetailItem(
                  item: PlayItem(
                    oid: Int64(id),
                    subId: [Int64(id)],
                    itemType: 2,
                  ),
                ),
              ),
              reachStart: prev == null,
              reachEnd: next == null,
              paginationReply: PaginationReply(prev: prev, next: next),
            ).writeToBuffer(),
          ),
          200,
          headers: {
            'grpc-status': ['0'],
            'content-type': ['application/grpc'],
          },
        ),
      );

  void malformed(int index) => pending[index].complete(
    ResponseBody.fromBytes(
      [0],
      200,
      headers: {
        'grpc-status': ['0'],
        'content-type': ['application/grpc'],
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adapter adapter;
  late List<Account> previousAccounts;
  late AudioController controller;
  var closed = false;
  setUpAll(() async {
    GStorage.setting = await Hive.openBox(
      'audit-round2-setting',
      bytes: Uint8List(0),
    );
    GStorage.video = await Hive.openBox(
      'audit-round2-video',
      bytes: Uint8List(0),
    );
    GStorage.localCache = await Hive.openBox(
      'audit-round2-cache',
      bytes: Uint8List(0),
    );
    previousAccounts = List<Account>.of(Accounts.accountMode);
    Request();
    Request.dio.interceptors.clear();
  });
  setUp(() {
    adapter = _Adapter();
    Request.dio.httpClientAdapter = adapter;
    controller = AudioController()
      ..id = Int64(11)
      ..oid = Int64(11)
      ..subId = [Int64(11)]
      ..itemType = 2
      ..from = AudioPlaylistSource.fallback;
    closed = false;
  });
  tearDown(() {
    if (!closed) controller.dispose();
    adapter.close();
    Accounts.accountMode.setAll(0, previousAccounts);
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await Hive.close();
  });

  Future<void> initialize({String? prev, String? next}) async {
    final operation = controller.reloadPlaylist();
    await adapter.waitForRequests(1);
    adapter.playlist(0, [11, 22], prev: prev, next: next);
    expect(await operation, isTrue);
  }

  testWidgets(
    'popping the audio route detaches controls before replies arrive',
    (
      tester,
    ) async {
      final handler = videoPlayerServiceHandler = VideoPlayerServiceHandler();
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: GetMaterialApp(
              home: const SizedBox(),
              getPages: [
                GetPage(name: '/audio', page: () => const AudioPage()),
              ],
            ),
          ),
        );
        AudioPage.toAudioPage(
          oid: 11,
          itemType: 2,
          from: AudioPlaylistSource.fallback,
        );
        await tester.pump();
        var playlistRequest = -1;
        for (var attempt = 0; attempt < 20 && playlistRequest < 0; attempt++) {
          await tester.pump(const Duration(milliseconds: 30));
          playlistRequest = adapter.requests.indexWhere(
            (request) => request.path.endsWith('/Playlist'),
          );
        }
        expect(playlistRequest, isNot(-1));
        expect(find.byTooltip('排序'), findsOneWidget);
        expect(handler.onPlay, isNotNull);
        expect(handler.onPause, isNotNull);
        expect(handler.onSeek, isNotNull);

        Get.back();
        await tester.pumpAndSettle();
        expect(find.byTooltip('排序'), findsNothing);
        expect(handler.onPlay, isNull);
        expect(handler.onPause, isNull);
        expect(handler.onSeek, isNull);
        adapter.playlist(playlistRequest, [11]);
        for (var index = 0; index < adapter.requests.length; index++) {
          if (index != playlistRequest) adapter.malformed(index);
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(handler.mediaItem.value, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        handler.clear();
        videoPlayerServiceHandler = null;
      }
    },
  );

  test('playlist order keeps the most recent selection', () async {
    final first = controller.onChangeOrder(AudioPlaylistOrder.reverse);
    await adapter.waitForRequests(1);
    final second = controller.onChangeOrder(AudioPlaylistOrder.normal);
    await adapter.waitForRequests(2);
    adapter.playlist(1, [11, 22]);
    expect(await second, isTrue);
    adapter.playlist(0, [22, 11]);
    expect(await first, isFalse);
    expect(controller.playlistState.value.order, AudioPlaylistOrder.normal);
    expect(controller.playlist!.map((e) => e.info.target.oid.toInt()), [
      11,
      22,
    ]);
  });

  test(
    'pagination is serial and overlapping pages preserve selection',
    () async {
      await initialize(prev: 'prev', next: 'next');
      final next = controller.loadNext();
      expect(await controller.loadNext(), isFalse);
      expect(await controller.loadPrev(), isFalse);
      await adapter.waitForRequests(2);
      adapter.playlist(1, [22, 33, 33], next: 'next2');
      expect(await next, isTrue);
      expect(controller.playlist!.map((e) => e.info.target.oid.toInt()), [
        11,
        22,
        33,
      ]);
      final prev = controller.loadPrev();
      await adapter.waitForRequests(3);
      adapter.playlist(2, [1, 11], prev: 'prev2');
      expect(await prev, isTrue);
      expect(controller.playlist!.map((e) => e.info.target.oid.toInt()), [
        1,
        11,
        22,
        33,
      ]);
      expect(controller.index, 1);
      expect(controller.audioItem.value!.info.target.oid, Int64(11));
    },
  );

  test('failed page retains content and cursor until explicit retry', () async {
    await initialize(prev: 'prev', next: 'next');
    final operation = controller.loadNext();
    await adapter.waitForRequests(2);
    adapter.malformed(1);
    expect(await operation, isFalse);
    expect(controller.playlistState.value.pageStatus, isA<Error>());
    expect(controller.playlist!.length, 2);
    expect(await controller.loadNext(), isFalse);
    expect(await controller.loadPrev(), isFalse);
    expect(adapter.requests.length, 2);
    final retry = controller.retryPlaylistPage();
    await adapter.waitForRequests(3);
    final request = PlaylistReq.fromBuffer(
      GrpcReq.decompressProtobuf(adapter.requests[2].data),
    );
    expect(request.pagination.next, 'next');
    adapter.playlist(2, [33]);
    expect(await retry, isTrue);
    expect(controller.playlist!.length, 3);
  });

  test(
    'sorting invalidates an older page and immediately permits a new query',
    () async {
      await initialize(next: 'next');
      final page = controller.loadNext();
      await adapter.waitForRequests(2);
      final refresh = controller.onChangeOrder(AudioPlaylistOrder.reverse);
      await adapter.waitForRequests(3);
      adapter.playlist(2, [22, 11]);
      expect(await refresh, isTrue);
      adapter.playlist(1, [33]);
      expect(await page, isFalse);
      expect(controller.playlist!.map((e) => e.info.target.oid.toInt()), [
        22,
        11,
      ]);
      expect(controller.index, 1);
    },
  );

  test('account replacement hides old list and rejects late results', () async {
    await initialize(next: 'next');
    final oldPage = controller.loadNext();
    await adapter.waitForRequests(2);
    Accounts.accountMode[AccountType.main.index] = const NoAccount();
    final changes = Accounts.mainChanges as ValueNotifier<int>;
    changes.value++;
    expect(controller.playlist, isNull);
    expect(controller.index, isNull);
    expect(controller.playlistState.value.status, isA<Loading>());
    await adapter.waitForRequests(3);
    adapter.playlist(1, [33]);
    expect(await oldPage, isFalse);
    final updated = Completer<void>();
    void onUpdated() {
      if (controller.playlistState.value.status.isSuccess) updated.complete();
    }

    controller.playlistState.addListener(onUpdated);
    adapter.playlist(2, [11, 44]);
    await updated.future;
    controller.playlistState.removeListener(onUpdated);
    expect(controller.playlist!.map((e) => e.info.target.oid.toInt()), [
      11,
      44,
    ]);
  });

  test('initialization failure permits same-order retry and valid missing-anchor or empty lists', () async {
    final first = controller.onChangeOrder(AudioPlaylistOrder.reverse);
    await adapter.waitForRequests(1);
    adapter.malformed(0);
    expect(await first, isFalse);
    expect(controller.playlistState.value.status, isA<Error>());
    final retry = controller.onChangeOrder(AudioPlaylistOrder.reverse);
    await adapter.waitForRequests(2);
    adapter.playlist(1, [22, 33]);
    expect(await retry, isTrue);
    expect(controller.playlist!.length, 2);
    expect(controller.index, isNull);
    expect(controller.oid, Int64(11));
    expect(controller.audioItem.value, isNull);
    final empty = controller.reloadPlaylist();
    await adapter.waitForRequests(3);
    adapter.playlist(2, []);
    expect(await empty, isTrue);
    expect(controller.playlist, isEmpty);
  });

  test('removed entries stay removed across overlapping pages and cursor cycles stop', () async {
    await initialize(next: 'next');
    controller.removePlaylistItem(controller.playlist!.last);
    final operation = controller.loadNext();
    await adapter.waitForRequests(2);
    adapter.playlist(1, [11, 22], next: 'next2');
    expect(await operation, isTrue);
    final secondPage = controller.loadNext();
    await adapter.waitForRequests(3);
    adapter.playlist(2, [22, 33], next: 'next');
    expect(await secondPage, isTrue);
    expect(controller.playlist!.map((e) => e.info.target.oid.toInt()), [
      11,
      33,
    ]);
    expect(await controller.loadNext(), isFalse);
    expect(adapter.requests.length, 3);
  });

  test('selection changed during initialization is not overwritten by its old anchor', () async {
    final operation = controller.reloadPlaylist();
    await adapter.waitForRequests(1);
    controller
      ..oid = Int64(22)
      ..subId = [Int64(22)];
    adapter.playlist(0, [11, 22]);
    expect(await operation, isTrue);
    expect(controller.index, 1);
    expect(controller.audioItem.value, isNull);
  });

  test('closed controller rejects in-flight initialization', () async {
    final operation = controller.reloadPlaylist();
    await adapter.waitForRequests(1);
    controller.dispose();
    closed = true;
    adapter.playlist(0, [11, 22]);
    expect(await operation, isFalse);
    expect(controller.playlist, isNull);
  });
  test(
    'row actions do not target equal entries from a newer playlist snapshot',
    () async {
      await initialize();
      final oldItem = controller.playlist!.last;
      final operation = controller.reloadPlaylist();
      await adapter.waitForRequests(2);
      adapter.playlist(1, [11, 22]);
      expect(await operation, isTrue);
      controller.removePlaylistItem(oldItem);
      await controller.selectPlaylistItem(oldItem);
      expect(controller.playlist!.length, 2);
      expect(adapter.requests.length, 2);
    },
  );
}
