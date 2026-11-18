import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/retry_interceptor.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../support/memory_box.dart';

class VideoWriteFixture {
  VideoWriteFixture(this.timeout);

  final DioExceptionType timeout;
  final requests = <RequestOptions>[];
  Object? body;
  bool fail = false;

  void install() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(RetryInterceptor(Request.dio, 2, 0))
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (fail) {
              handler.reject(
                DioException(requestOptions: options, type: timeout),
                true,
              );
            } else {
              handler.resolve(Response(requestOptions: options, data: body));
            }
          },
        ),
      );
  }

  void reset() {
    requests.clear();
    body = {'code': 0};
    fail = false;
  }

  void close() => Request.dio.close(force: true);
}
