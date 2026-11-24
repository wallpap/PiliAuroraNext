import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/response_transformer.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/diagnostics/http_diagnostics.dart';
import 'package:pili_aurora_next/http/request_failure_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Diagnostics diagnostics;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pili-http-diagnostics-');
    diagnostics = Diagnostics(processReader: () => {});
    await diagnostics.initialize(directory: directory);
  });
  tearDown(() async {
    diagnostics.dispose();
    await diagnostics.flush();
    await directory.delete(recursive: true);
  });

  test(
    'debug HTTP logs record decoded and buffered sizes with no payload',
    () async {
      await diagnostics.configure(level: DiagnosticLogLevel.debug);
      final dio = Dio()
        ..httpClientAdapter = _TestHttpAdapter()
        ..transformer = CompressedResponseTransformer();
      dio.interceptors.add(DiagnosticHttpInterceptor(diagnostics: diagnostics));
      addTearDown(() => dio.close(force: true));

      final response = await dio.get<String>('https://example.test/brotli');
      expect(response.data, 'time');
      final record = diagnostics.recentLogs.single;
      final details = record['details'] as Map;
      expect(details['responseEncoding'], 'br');
      expect(details['responseBodyBytes'], 8);
      expect(details['decodedResponseBytes'], 4);
      expect(details['decodeInBackground'], isTrue);
      expect(details['decodeElapsedUs'], greaterThanOrEqualTo(0));
      expect(details.values, isNot(contains('time')));
      expect(
        CompressedResponseTransformer.takeDecodeSample(response.requestOptions),
        isNull,
      );

      await dio.get<List<int>>(
        'https://example.test/brotli',
        options: Options(responseType: ResponseType.bytes),
      );
      expect(
        (diagnostics.recentLogs.first['details'] as Map).keys,
        isNot(contains('decodeElapsedUs')),
      );
    },
  );

  test('HTTP success and failure finish operations without copying request secrets', () async {
    await diagnostics.configure(tracing: true, level: DiagnosticLogLevel.debug);
    final dio = Dio()
      ..httpClientAdapter = _TestHttpAdapter()
      ..transformer = CompressedResponseTransformer();
    dio.interceptors.add(DiagnosticHttpInterceptor(diagnostics: diagnostics));
    try {
      await dio.post<Object?>(
        'https://example.test/success?token=http-query-test',
        data: {'password': 'http-body-test'},
        options: Options(headers: {'Cookie': 'http-cookie-test'}),
      );
      await expectLater(
        dio.get<Object?>('https://example.test/failure'),
        throwsA(isA<DioException>()),
      );
      diagnostics.capture();
      final http = (diagnostics.latest!['operations'] as Map)['http'] as Map;
      expect(http['active'], 0);
      expect(http['completed'], 2);
      expect(http['errors'], 1);
      expect(diagnostics.recentLogs, hasLength(2));
      final success = diagnostics.recentLogs
          .map((record) => record['details'] as Map)
          .singleWhere((details) => details['status'] == 200);
      expect(success['responseBodyBytes'], 2);
      expect(success['decodedResponseBytes'], 2);
      expect(success['responseEncoding'], 'identity');
      expect(success['decodeInBackground'], isFalse);
      final records = jsonEncode(diagnostics.recentLogs);
      for (final secret in [
        'http-query-test',
        'http-body-test',
        'http-cookie-test',
      ]) {
        expect(records, isNot(contains(secret)));
      }
      await diagnostics.configure(level: DiagnosticLogLevel.error);
      await expectLater(
        dio.get<Object?>('https://example.test/failure'),
        throwsA(isA<DioException>()),
      );
      expect(diagnostics.recentLogs, hasLength(3));
    } finally {
      dio.close(force: true);
    }
  });

  test(
    'toast layer does not duplicate an interceptor failure record',
    () async {
      await diagnostics.configure(level: DiagnosticLogLevel.debug);
      final before = Diagnostics.instance.recentLogs.length;
      final dio = Dio()..httpClientAdapter = _FailureAdapter();
      dio.interceptors.addAll([
        DiagnosticHttpInterceptor(diagnostics: diagnostics),
        InterceptorsWrapper(
          onError: (error, handler) {
            showRequestFailure(error);
            handler.next(error);
          },
        ),
      ]);
      try {
        await expectLater(
          dio.get<Object?>(
            'https://api.bilibili.com/x/click-interface/web/heartbeat',
          ),
          throwsA(isA<DioException>()),
        );
        expect(diagnostics.recentLogs, hasLength(1));
        expect(Diagnostics.instance.recentLogs.length, before);
      } finally {
        dio.close(force: true);
      }
    },
  );

  for (final tracing in [false, true]) {
    test('expected HTTP failures use debug with tracing=$tracing', () async {
      await diagnostics.configure(tracing: tracing);
      final dio = Dio()..httpClientAdapter = _FailureAdapter();
      dio.interceptors.add(DiagnosticHttpInterceptor(diagnostics: diagnostics));
      const expected = [
        'https://api.bilibili.com/x/click-interface/web/heartbeat',
        'https://api.bilibili.com/x/player/online/total',
        'https://account.bilibili.com/site/getCoin',
        'https://api.bilibili.com/x/v2/history/report',
        'https://api.bilibili.com/x/v2/dm/web/seg.so',
        'https://api.live.bilibili.com/xlive/web-room/v1/index/roomEntryAction',
        'https://api.github.com/repos/test/project',
        'https://raw.githubusercontent.com/test/project/file',
        'https://i0.hdslb.com/test.jpg',
        'https://test.biliimg.com/test.jpg',
        'https://custom.example/api/skipSegments',
      ];
      try {
        for (final url in expected) {
          await expectLater(
            dio.get<Object?>(url),
            throwsA(isA<DioException>()),
          );
        }
        expect(diagnostics.recentLogs, isEmpty);
        await expectLater(
          dio.get<Object?>('https://example.test/x/player/online/total'),
          throwsA(isA<DioException>()),
        );
        expect(diagnostics.recentLogs.single['level'], 'error');
        await diagnostics.configure(level: DiagnosticLogLevel.debug);
        for (final url in expected) {
          await expectLater(
            dio.get<Object?>(url),
            throwsA(isA<DioException>()),
          );
        }
        expect(
          diagnostics.recentLogs.where((r) => r['level'] == 'debug'),
          hasLength(expected.length),
        );
        if (tracing) {
          diagnostics.capture();
          final stats =
              (diagnostics.latest!['operations'] as Map)['http'] as Map;
          expect(stats['errors'], expected.length * 2 + 1);
        }
      } finally {
        dio.close(force: true);
      }
    });
  }

  test('HTTP retries do not leave an active operation behind', () async {
    await diagnostics.configure(tracing: true);
    final interceptor = DiagnosticHttpInterceptor(diagnostics: diagnostics);
    final options = RequestOptions(path: 'https://example.test/retry');
    interceptor
      ..onRequest(options, RequestInterceptorHandler())
      ..onRequest(options, RequestInterceptorHandler())
      ..onResponse(
        Response<Object?>(requestOptions: options, statusCode: 200),
        ResponseInterceptorHandler(),
      );
    diagnostics.capture();
    final http = (diagnostics.latest!['operations'] as Map)['http'] as Map;
    expect(http['active'], 0);
    expect(http['completed'], 2);
  });
}

class _TestHttpAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/failure') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    }
    if (options.uri.path == '/brotli') {
      return ResponseBody.fromBytes(
        const [0x8b, 1, 0x80, 116, 105, 109, 101, 3],
        200,
        headers: {
          'content-type': ['text/plain'],
          'content-encoding': ['br'],
        },
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        'content-type': ['application/json'],
        'content-length': ['2'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailureAdapter extends _TestHttpAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Future<ResponseBody>.error(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      ),
    );
  }
}
