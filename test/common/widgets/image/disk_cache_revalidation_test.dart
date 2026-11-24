import 'dart:async';
import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late DefaultCacheManager manager;
  late String url;
  late List<String?> validators;
  late Future<void> Function(HttpRequest) respond;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image-revalidation-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://${server.address.address}:${server.port}/image.png';
    manager = await DefaultCacheManager.init(
      stalePeriod: const Duration(seconds: 1),
      cacheDirectoryProvider: () async => directory,
    );
    validators = [];
    server.listen((request) async {
      validators.add(request.headers.value(HttpHeaders.ifNoneMatchHeader));
      await respond(request);
      await request.response.close();
    });
  });

  tearDown(() async {
    await manager.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<File> seed() async {
    respond = (request) async {
      request.response.headers.set(HttpHeaders.etagHeader, '"v1"');
      request.response.add(List.filled(256 * 1024, 0));
    };
    final file = await manager.getSingleFile(url, key: 'image');
    final cached = (await manager.getFileFromCache('image'))!;
    await Future<void>.delayed(
      cached.validTill.difference(DateTime.now()) +
          const Duration(milliseconds: 2),
    );
    validators.clear();
    return file;
  }

  test(
    'stale stream yields once and 304 renews metadata without a write',
    () async {
      final file = await seed();
      file.setLastModifiedSync(DateTime.utc(2000));
      final modified = file.lastModifiedSync();
      respond = (request) async {
        request.response.statusCode = HttpStatus.notModified;
      };

      final events = await manager.getFileStream(url, key: 'image').toList();
      final cached = events.single as FileInfo;
      expect(cached.source, FileSource.Cache);
      expect(cached.validTill.isBefore(DateTime.now()), isTrue);
      expect(validators, ['"v1"']);
      expect(file.lastModifiedSync(), modified);
      expect(await file.length(), 256 * 1024);
      expect(manager.getTotalLength(), 256 * 1024);
      final renewed = (await manager.getFileFromCache('image'))!;
      expect(renewed.validTill.isAfter(DateTime.now()), isTrue);

      expect(await manager.getFileStream(url, key: 'image').length, 1);
      expect(validators, hasLength(1));
    },
  );

  test('single file also reuses a cached file after 304', () async {
    final file = await seed();
    respond = (request) async {
      request.response.statusCode = HttpStatus.notModified;
    };

    expect((await manager.getSingleFile(url, key: 'image')).path, file.path);
    expect(validators, ['"v1"']);
  });

  test('concurrent 304 responses reuse the same cached file', () async {
    final file = await seed();
    final firstRefresh = Completer<void>();
    final firstRequest = Completer<void>();
    final secondRequest = Completer<void>();
    respond = (request) async {
      if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == null) {
        request.response.add([9]);
        return;
      }
      if (firstRequest.isCompleted) {
        secondRequest.complete();
        await firstRefresh.future;
      } else {
        firstRequest.complete();
        await secondRequest.future;
      }
      request.response.statusCode = HttpStatus.notModified;
    };

    final first = manager
        .getSingleFile(url, key: 'image')
        .whenComplete(
          firstRefresh.complete,
        );
    await firstRequest.future;
    final second = manager.getSingleFile(url, key: 'image');
    final files = await Future.wait([first, second]);

    expect(files.map((result) => result.path), [file.path, file.path]);
    expect(validators, ['"v1"', '"v1"']);
    expect(await file.length(), 256 * 1024);
  });

  test('a changed response replaces the cached bytes', () async {
    final file = await seed();
    respond = (request) async {
      request.response.headers.set(HttpHeaders.etagHeader, '"v2"');
      request.response.add([2, 3, 4]);
    };

    final events = await manager.getFileStream(url, key: 'image').toList();
    expect(events.map((event) => (event as FileInfo).source), [
      FileSource.Cache,
      FileSource.Online,
    ]);
    expect(validators, ['"v1"']);
    expect(await file.readAsBytes(), [2, 3, 4]);
    expect(manager.getTotalLength(), 3);
  });

  test(
    '304 after file deletion retries without the cached validator',
    () async {
      final file = await seed();
      respond = (request) async {
        if (validators.length == 1) {
          await file.delete();
          request.response.statusCode = HttpStatus.notModified;
        } else {
          request.response.add([5, 6]);
        }
      };

      final restored = await manager.getSingleFile(url, key: 'image');
      expect(await restored.readAsBytes(), [5, 6]);
      expect(validators, ['"v1"', null]);
    },
  );

  test('a cached validator is never sent to a different URL', () async {
    await seed();
    respond = (request) async => request.response.add([7]);

    final file = await manager.getSingleFile('$url?other', key: 'image');
    expect(await file.readAsBytes(), [7]);
    expect(validators, [null]);
  });

  test('a caller supplied validator takes precedence', () async {
    await seed();
    respond = (request) async => request.response.add([8]);

    await manager.getSingleFile(
      url,
      key: 'image',
      headers: const {'If-None-Match': '"caller"'},
    );
    expect(validators, ['"caller"']);
  });
}
