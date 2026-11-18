import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/http/api.dart';

import '../../../support/controlled_interceptor.dart';

Future<({Future<void> completion, RequestOptions request})> reachPublishRequest(
  WidgetTester tester, {
  required ControlledInterceptor interceptor,
  required Future<void> Function() publish,
  required void Function() replaceDraft,
}) async {
  late Future<void> pending;
  await tester.runAsync(() async {
    pending = publish();
    await publish();
    await interceptor.waitForRequests(1);
  });
  expect(interceptor.requests.single.options.path, Api.uploadBfs);
  replaceDraft();
  await tester.runAsync(() async {
    interceptor.requests.single.reply.complete(uploadedPicture());
    await interceptor.waitForRequests(2);
  });
  return (completion: pending, request: interceptor.requests.last.options);
}

Object uploadedPicture() => {
  'code': 0,
  'data': {
    'image_url': 'https://example.invalid/image.png',
    'image_width': 1,
    'image_height': 1,
  },
};
