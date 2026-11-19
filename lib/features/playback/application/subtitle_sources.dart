import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pili_aurora_next/features/playback/data/subtitle_repository.dart';
import 'package:pili_aurora_next/features/playback/domain/subtitle_format.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

typedef SubtitleSource = ({bool isData, String id});

class SubtitleSources {
  final Map<int, SubtitleSource> _sources = {};

  Map<int, SubtitleSource> get snapshot => Map.unmodifiable(_sources);

  void clear() => _sources.clear();

  void remember(int index, SubtitleSource source) => _sources[index] = source;

  Future<LoadingState<SubtitleSource>?> forPlayback(
    int index,
    String url, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    if (_sources[index] case final cached?) return Success(cached);
    final result = await SubtitleRepository.fetch(url);
    if (!isCurrent()) return null;
    return switch (result) {
      Success(:final response) => Success(
        _sources[index] = (isData: true, id: response),
      ),
      Error() => result,
      Loading() => null,
    };
  }

  static Future<SubtitleSource> importFile(String path, String name) async {
    if (!name.endsWith('.json') && !name.endsWith('.bcc')) {
      return (isData: false, id: path);
    }
    final contents = await File(path).readAsString();
    final body = jsonDecode(contents)['body'] as List;
    final subtitle = await compute<List, String>(SubtitleUtils.json2Vtt, body);
    return (isData: true, id: subtitle);
  }

  Future<LoadingState<Uint8List>?> forExport(
    String url,
    SubtitleFormat format, {
    required int index,
    required SubtitleSource? cached,
    required bool Function() isCurrent,
  }) async {
    if (format == .json) {
      final bytes = await SubtitleRepository.originalBytes(url);
      return bytes == null ? null : Success(bytes);
    }
    if (format == .vtt && cached != null && cached.isData) {
      return Success(utf8.encode(cached.id));
    }
    final result = await SubtitleRepository.fetch(url, format: format);
    return switch (result) {
      Success(:final response) => Success(
        _encodeExport(
          response,
          index: index,
          rememberVtt: format == .vtt && isCurrent(),
        ),
      ),
      Error() => result,
      Loading() => null,
    };
  }

  Uint8List _encodeExport(
    String subtitle, {
    required int index,
    required bool rememberVtt,
  }) {
    if (rememberVtt) remember(index, (isData: true, id: subtitle));
    return utf8.encode(subtitle);
  }
}
