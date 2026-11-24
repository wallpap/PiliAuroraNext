import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pili_aurora_next/http/response_decoder.dart';

/// 大响应在一次后台任务中完成解压、UTF-8 和 JSON 转换。
class CompressedResponseTransformer extends BackgroundTransformer {
  static const _sampleKey = 'piliResponseDecodeSample';

  static void setDecodeSampling(
    RequestOptions options, {
    required bool enabled,
  }) {
    options.extra.remove(_sampleKey);
    if (enabled) options.extra[_sampleKey] = true;
  }

  static Map<String, Object?>? takeDecodeSample(RequestOptions options) {
    final sample = options.extra.remove(_sampleKey);
    return sample is Map<String, Object?> ? sample : null;
  }

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    if (options.responseType == ResponseType.stream ||
        options.responseType == ResponseType.bytes ||
        options.responseDecoder != null) {
      return super.transformResponse(options, responseBody);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in responseBody.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final encoding = responseBody.headers['content-encoding']?.firstOrNull;
    final parseJson =
        options.responseType == ResponseType.json &&
        Transformer.isJsonMimeType(
          responseBody.headers[Headers.contentTypeHeader]?.firstOrNull,
        );
    final useIsolate = ResponseBodyDecoder.shouldUseIsolate(bytes, encoding);
    final measure = options.extra[_sampleKey] == true;
    final watch = measure ? (Stopwatch()..start()) : null;
    final result = useIsolate
        ? await _decodeInBackground((
            bytes: TransferableTypedData.fromList([bytes]),
            encoding: encoding,
            parseJson: parseJson,
            measure: measure,
          ))
        : _decode(bytes, encoding, parseJson, measure: measure);
    if (watch == null) return result;
    watch.stop();
    final (value, decodedBytes) = result as (Object?, int);
    options.extra[_sampleKey] = <String, Object?>{
      'responseBodyBytes': bytes.length,
      'decodedResponseBytes': decodedBytes,
      'responseEncoding': switch (encoding?.trim().toLowerCase()) {
        'br' => 'br',
        'gzip' => 'gzip',
        null || '' || 'identity' => 'identity',
        _ => 'other',
      },
      'decodeInBackground': useIsolate,
      'decodeElapsedUs': watch.elapsedMicroseconds,
    };
    return value;
  }
}

Object? _decode(
  List<int> bytes,
  String? encoding,
  bool parseJson, {
  required bool measure,
}) {
  final decoded = ResponseBodyDecoder.decompress(bytes, encoding);
  final text = utf8.decode(decoded, allowMalformed: true);
  final value = parseJson && text.isNotEmpty ? jsonDecode(text) : text;
  return measure ? (value, decoded.length) : value;
}

Future<Object?> _decodeInBackground(
  ({
    TransferableTypedData bytes,
    String? encoding,
    bool parseJson,
    bool measure,
  })
  args,
) => Isolate.run(
  () => _decode(
    args.bytes.materialize().asUint8List(),
    args.encoding,
    args.parseJson,
    measure: args.measure,
  ),
);
