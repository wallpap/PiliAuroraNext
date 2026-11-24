import 'dart:collection';

/// 导出时清洗敏感字段；采集时只复制有界快照，避免正则处理阻塞播放。
abstract final class DiagnosticRedactor {
  static const _redacted = '<redacted>';
  static const _credentialTerms =
      r'authorization|cookies?|token|password|passwd|secret|credentials?|private[ _.-]?key|api[ _.-]?key|access[ _.-]?key|sessdata|bili_jct|csrf|dedeuserid|identifierforvendor|android[ _.-]?id|device[ _.-]?id|fingerprint|signature|w_rid|upsig|auth[ _.-]?(?:code|key)|ticket';
  static final _secretKey = RegExp(
    '$_credentialTerms|buvid|^sign\$',
    caseSensitive: false,
  );
  static final _assignmentKey = RegExp(
    '(?:$_credentialTerms)\$|(?:^|[-_.])sign\$',
    caseSensitive: false,
  );
  static final _headerKey = RegExp(r'(?:authorization|cookies?)$');
  static final _url = RegExp(
    r'''(?:(?:https?|wss?|ftps?|rtmps?|rtsps?|file)://|(?<![\w:/\\])//)[^\s<>"']+(?:<redacted>)?''',
    caseSensitive: false,
  );
  static final _query = RegExp(r'''\?[^\s<>"']+''');
  static final _relativeQuery = RegExp(
    r'''(?:[/\\]|\.[A-Za-z0-9]{1,8})[^\s<>"'()]*$''',
  );
  static final _delimiter = RegExp(r'[:=]');
  static final _lineEnd = RegExp(r'[\r\n]');
  static final _bareValueEnd = RegExp(r'[\r\n,;\]}]');
  static final _bearer = RegExp(
    r'''\b(Bearer|Basic)\s+[^\s,;"'<>()\[\]{}]+''',
    caseSensitive: false,
  );
  static final _privateKey = RegExp(
    r'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----[\s\S]*?(?:-----END (?:[A-Z0-9]+ )*PRIVATE KEY-----|$)',
  );
  static final _windowsPath = RegExp(
    r'''\b[A-Za-z]:[\\/][^\r\n"'<>]+|\\\\[^\s\\/"'<>]+[\\/][^\r\n"'<>]+''',
  );
  static final _unixUserPath = RegExp(
    r'''/(?:Users|home)/[^\s/"'<>]+''',
    caseSensitive: false,
  );
  static final _textMarker = RegExp(
    r'[:=?/\\]|-----BEGIN |\b(?:Bearer|Basic)\s',
    caseSensitive: false,
  );

  static String text(Object? value, {int maxLength = 4096}) {
    final input = value.toString();
    var result = input.length > 1048576 ? input.substring(0, 1048576) : input;
    if (!_textMarker.hasMatch(result)) {
      return boundedText(result, maxLength: maxLength);
    }
    if (result.contains('-----BEGIN ')) {
      result = result.replaceAll(_privateKey, '<private-key>');
    }
    if (result.contains('//')) {
      result = result.replaceAllMapped(_url, _redactUrl);
    }
    if (result.contains('?')) {
      final text = result;
      result = result.replaceAllMapped(_query, (match) {
        var start = match.start;
        while (start > 0 && !_isTokenBoundary(text.codeUnitAt(start - 1))) {
          start--;
        }
        final prefix = text.substring(start, match.start);
        return _relativeQuery.hasMatch(prefix) || match[0]!.contains('=')
            ? '?$_redacted'
            : match[0]!;
      });
    }
    if (_delimiter.hasMatch(result)) {
      result = _redactAssignments(result);
    }
    result = result.replaceAllMapped(
      _bearer,
      (match) => '${match[1]} $_redacted',
    );
    if (result.contains('\\') || result.contains(':')) {
      result = result.replaceAll(_windowsPath, '<local-path>');
    }
    if (result.contains('/')) {
      result = result.replaceAll(_unixUserPath, '/<user>');
    }
    return boundedText(result, maxLength: maxLength);
  }

  static String _redactUrl(Match match) {
    final uri = Uri.tryParse(match[0]!);
    if (uri == null || uri.host.isEmpty && uri.scheme != 'file') return '<url>';
    if (uri.scheme == 'file') return '<local-path>';
    final endpoint = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return '$endpoint${uri.hasQuery ? '?$_redacted' : ''}';
  }

  static String _redactAssignments(String input) {
    StringBuffer? output;
    var copied = 0;
    var cursor = 0;
    while (cursor < input.length) {
      final delimiter = _delimiter.allMatches(input, cursor).firstOrNull;
      if (delimiter == null) break;
      cursor = delimiter.end;
      var keyEnd = delimiter.start;
      while (keyEnd > copied &&
          _isHorizontalSpace(input.codeUnitAt(keyEnd - 1))) {
        keyEnd--;
      }
      final quotedKey =
          keyEnd > copied && _isQuote(input.codeUnitAt(keyEnd - 1));
      var replacementQuote = '';
      if (quotedKey) {
        final quoteEnd = keyEnd;
        keyEnd--;
        if (keyEnd > copied && input.codeUnitAt(keyEnd - 1) == 92) keyEnd--;
        replacementQuote = input.substring(keyEnd, quoteEnd);
      }
      var keyStart = keyEnd;
      while (keyStart > copied &&
          (_isKeyCharacter(input.codeUnitAt(keyStart - 1)) ||
              (quotedKey && input.codeUnitAt(keyStart - 1) == 32))) {
        keyStart--;
      }
      if (keyStart == keyEnd) continue;
      final key = input.substring(keyStart, keyEnd).toLowerCase();
      if (!_assignmentKey.hasMatch(key) && !_hasBuvidSuffix(key)) continue;

      var valueStart = delimiter.end;
      while (valueStart < input.length &&
          _isHorizontalSpace(input.codeUnitAt(valueStart))) {
        valueStart++;
      }
      final header = _headerKey.hasMatch(key);
      final quote = header && !quotedKey ? null : _quoteAt(input, valueStart);
      final valueEnd = quote != null
          ? _quotedEnd(input, valueStart, quote)
          : _unquotedEnd(input, valueStart, header: header && !quotedKey);
      if (valueStart == valueEnd) continue;
      (output ??= StringBuffer())
        ..write(input.substring(copied, valueStart))
        ..write(replacementQuote)
        ..write(_redacted)
        ..write(replacementQuote);
      cursor = copied = valueEnd;
    }
    if (output == null) return input;
    return (output..write(input.substring(copied))).toString();
  }

  static bool _hasBuvidSuffix(String key) {
    final hyphen = key.lastIndexOf('-');
    final dot = key.lastIndexOf('.');
    return key.contains('buvid', (hyphen > dot ? hyphen : dot) + 1);
  }

  static bool _isHorizontalSpace(int character) =>
      character == 32 || character == 9;

  static bool _isQuote(int character) => character == 34 || character == 39;

  static bool _isKeyCharacter(int character) =>
      (character >= 48 && character <= 57) ||
      (character >= 65 && character <= 90) ||
      (character >= 97 && character <= 122) ||
      character == 45 ||
      character == 46 ||
      character == 95;

  static bool _isTokenBoundary(int character) =>
      character <= 32 ||
      _isQuote(character) ||
      character == 40 ||
      character == 41 ||
      character == 60 ||
      character == 62;

  static String? _quoteAt(String input, int start) {
    if (start == input.length) return null;
    final character = input.codeUnitAt(start);
    if (_isQuote(character)) return input[start];
    if (character == 92 &&
        start + 1 < input.length &&
        _isQuote(input.codeUnitAt(start + 1))) {
      return input.substring(start, start + 2);
    }
    return null;
  }

  static int _quotedEnd(String input, int start, String quote) {
    final expected = quote.codeUnitAt(quote.length - 1);
    var cursor = start + quote.length;
    while (cursor < input.length) {
      final slashStart = cursor;
      while (cursor < input.length && input.codeUnitAt(cursor) == 92) {
        cursor++;
      }
      if (cursor == input.length) break;
      final slashCount = cursor - slashStart;
      if (input.codeUnitAt(cursor) == expected &&
          (quote.length == 1 ? slashCount.isEven : slashCount == 1)) {
        return cursor + 1;
      }
      cursor++;
    }
    return input.length;
  }

  static int _unquotedEnd(String input, int start, {required bool header}) {
    if (start == input.length) return start;
    final first = input.codeUnitAt(start);
    if (!header) {
      if (first == 91 || first == 123) return _containerEnd(input, start);
      return _bareValueEnd.allMatches(input, start).firstOrNull?.start ??
          input.length;
    }
    var end = start;
    while (true) {
      end = _lineEnd.allMatches(input, end).firstOrNull?.start ?? input.length;
      var next = end;
      if (next < input.length && input.codeUnitAt(next) == 13) next++;
      if (next < input.length && input.codeUnitAt(next) == 10) next++;
      if (next == input.length || !_isHorizontalSpace(input.codeUnitAt(next))) {
        return end;
      }
      end = next + 1;
    }
  }

  static int _containerEnd(String input, int start) {
    final closers = <int>[];
    var cursor = start;
    while (cursor < input.length) {
      final quote = _quoteAt(input, cursor);
      if (quote != null) {
        cursor = _quotedEnd(input, cursor, quote);
        continue;
      }
      final character = input.codeUnitAt(cursor++);
      if (character == 91 || character == 123) {
        closers.add(character == 91 ? 93 : 125);
      } else if (character == 93 || character == 125) {
        if (character != closers.removeLast()) return input.length;
        if (closers.isEmpty) return cursor;
      }
    }
    return input.length;
  }

  static Object? clean(
    Object? value, {
    int maxCharacters = 8192,
    int maxStringLength = 4096,
  }) => _clean(value, _Budget(maxCharacters, maxStringLength), 0);

  static Object? snapshot(
    Object? value, {
    int maxCharacters = 8192,
    int maxStringLength = 4096,
    bool immutable = false,
  }) => _clean(
    value,
    _Budget(
      maxCharacters,
      maxStringLength,
      redact: false,
      immutable: immutable,
    ),
    0,
  );

  static String boundedText(Object? value, {int maxLength = 4096}) {
    final input = value.toString();
    return input.length <= maxLength
        ? input
        : '${input.substring(0, maxLength)}…<truncated>';
  }

  static Map<String, Object?> snapshotNativeMemory(
    Map<String, Object?> value,
  ) => _resourceOwners(value, 'owners', redact: false);

  static Map<String, Object?> _resourceOwners(
    Map value,
    String ownerKey, {
    bool redact = true,
  }) {
    Object? copy(Object? item) => redact ? clean(item) : snapshot(item);
    return {
      ...Map<String, Object?>.from(
        copy({
          for (final entry in value.entries)
            if (entry.key != ownerKey && entry.key != 'resources')
              entry.key: entry.value,
        }) as Map,
      ),
      if (value.containsKey('resources')) 'resources': copy(value['resources']),
      if (value[ownerKey] is List)
        ownerKey: [
          for (final owner in (value[ownerKey] as List).take(8)) copy(owner),
        ],
    };
  }

  /// sample 的各字段与来源独立限界，不能让内存明细耗尽后续来源预算。
  static Map<String, Object?> exportRecord(Map<String, Object?> record) {
    if (record['type'] == 'memoryAttribution') {
      final owners = record['owners'];
      return {
        for (final entry in record.entries)
          if (entry.key != 'owners') entry.key: clean(entry.value),
        if (owners is Map)
          'owners': {
            for (final entry in owners.entries.take(16))
              entry.key: entry.key == 'plugin.video' && entry.value is Map
                  ? _resourceOwners(entry.value as Map, 'outputs')
                  : clean(entry.value),
          },
      };
    }
    if (record['type'] == 'sample') {
      final sources = record['sources'] ?? const {};
      return {
        for (final entry in record.entries)
          if (entry.key != 'sources')
            entry.key: entry.key == 'nativeMemory' && entry.value is Map
                ? _resourceOwners(entry.value as Map, 'owners')
                : clean(entry.value),
        'sources': sources is Map
            ? {
                for (final entry in sources.entries.take(64))
                  ...Map<String, Object?>.from(
                    clean({entry.key: entry.value}) as Map,
                  ),
              }
            : clean(sources),
      };
    }
    // 日志顶层、正文和详情分别处理，保留播放器的长日志和内存分块。
    final player = record['channel'] == 'player';
    return {
      ...Map<String, Object?>.from(
        clean({
          for (final entry in record.entries)
            if (entry.key != 'details' &&
                entry.key != 'message' &&
                entry.key != 'stack')
              entry.key: entry.value,
        }) as Map,
      ),
      if (record.containsKey('message'))
        'message': record['message'] is Map || record['message'] is Iterable
            ? clean(record['message'])
            : text(record['message'], maxLength: player ? 65536 : 16384),
      if (record.containsKey('stack'))
        'stack': text(record['stack'], maxLength: player ? 65536 : 4096),
      if (record.containsKey('details'))
        'details': clean(
          record['details'],
          maxCharacters: player ? 262144 : 8192,
          maxStringLength: player ? 65536 : 4096,
        ),
    };
  }

  static Object? _clean(Object? value, _Budget budget, int depth) {
    if (depth > 8 || budget.nodes-- <= 0 || budget.characters <= 0) {
      return '<truncated>';
    }
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : null;
    if (value is Map) {
      final result = <String, Object?>{};
      final name = budget.redact ? value['name'] : null;
      final sensitivePair = name is String && _secretKey.hasMatch(name);
      for (final entry in value.entries.take(64)) {
        final key = budget.redact ? text(entry.key) : entry.key.toString();
        // 原键保留到导出，避免截掉敏感键后缀后失去识别依据。
        final outputKey = budget.redact
            ? key.substring(0, key.length.clamp(0, 96))
            : key;
        result[outputKey] =
            budget.redact &&
                (_secretKey.hasMatch(entry.key.toString()) ||
                    (sensitivePair && entry.key == 'value'))
            ? _redacted
            : _clean(entry.value, budget, depth + 1);
      }
      return budget.immutable ? UnmodifiableMapView(result) : result;
    }
    if (value is Iterable) {
      final items = value
          .take(64)
          .map((item) => _clean(item, budget, depth + 1));
      return budget.immutable
          ? List<Object?>.unmodifiable(items)
          : items.toList();
    }
    final result = (budget.redact ? text : boundedText)(
      value,
      maxLength: budget.characters.clamp(0, budget.maxStringLength),
    );
    final length = result.length.clamp(0, budget.characters);
    budget.characters -= length;
    return length == result.length ? result : '${result.substring(0, length)}…';
  }
}

class _Budget {
  _Budget(
    this.characters,
    this.maxStringLength, {
    this.redact = true,
    this.immutable = false,
  });
  final bool redact;
  final bool immutable;
  final int maxStringLength;
  int nodes = 256;
  int characters;
}
