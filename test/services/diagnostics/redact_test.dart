import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/services/diagnostics/redact.dart';

void main() {
  test(
    'long ordinary words stay intact and prefixed token keys stay redacted',
    () {
      final ordinary = 'x' * 65000;
      expect(DiagnosticRedactor.text(ordinary, maxLength: 65536), ordinary);
      final output = DiagnosticRedactor.text(
        'accessToken=prefixed-secret\nx-custom-token: hyphen-secret\n'
        '"token":"quoted-secret"\n${'a' * 12000}Token=long-prefix-secret',
        maxLength: 65536,
      );
      for (final secret in [
        'prefixed-secret',
        'hyphen-secret',
        'quoted-secret',
        'long-prefix-secret',
      ]) {
        expect(output, isNot(contains(secret)));
      }
    },
  );
  test('redaction remains stable through error and toast boundaries', () {
    final once = DiagnosticRedactor.text(
      'GET https://user:pass@example.test:8443/path?access_key=secret#private',
    );
    expect(DiagnosticRedactor.text(once), once);
    expect(once, 'GET https://example.test:8443/path?<redacted>');
  });
  test(
    'credential suffixes retain long prefixes and skip ordinary mentions',
    () {
      final prefix = 'segment-' * 1024;
      final ordinary = '${'buvid' * 512} ordinary=value';
      final input =
          '$ordinary\n'
          '${prefix}ToKeN="token-secret"; safe=1\n'
          'buvidMention buvidOther_3 = buvid-secret; safe=2\n'
          'notBuvid before-token-word my-access_token: token-two; safe=3\n'
          'tokenMention apiKeyMention authCodeMention signMention\n'
          'prefixBuvid_3: device-secret; safe=4';
      expect(
        DiagnosticRedactor.text(input, maxLength: 65536),
        '$ordinary\n'
        '${prefix}ToKeN=<redacted>; safe=1\n'
        'buvidMention buvidOther_3 = <redacted>; safe=2\n'
        'notBuvid before-token-word my-access_token: <redacted>; safe=3\n'
        'tokenMention apiKeyMention authCodeMention signMention\n'
        'prefixBuvid_3: <redacted>; safe=4',
      );
    },
  );
  test('redacts standalone markers without assignment delimiters', () {
    final cases = {
      'bEaReR\tstandalone-secret': 'bEaReR <redacted>',
      'BASIC\u2003standalone-secret': 'BASIC <redacted>',
      '/home/PrivateUser/file': '/<user>/file',
      '/Users/PrivateUser/file': '/<user>/file',
      '-----BEGIN RSA PRIVATE KEY-----\nunclosed-secret': '<private-key>',
      "track.m4s?unknown=standalone-secret": 'track.m4s?<redacted>',
    };
    for (final entry in cases.entries) {
      expect(DiagnosticRedactor.text(entry.key), entry.value);
    }
  });
  test('buvid mentions do not hide overlapping hyphenated credential keys', () {
    for (final key in ['api-key', 'access-key', 'private-key', 'auth-code']) {
      expect(
        DiagnosticRedactor.text('buvid$key=overlap-secret; safe=1'),
        'buvid$key=<redacted>; safe=1',
      );
    }
  });
  test(
    'ordinary keyword mentions do not hide overlapping credential names',
    () {
      for (final key in [
        'secretoken',
        'secreticket',
        'tickeToken',
        'passworDedeUserID',
        'SESSDATApi-key',
        'w_riDedeUserID',
      ]) {
        expect(
          DiagnosticRedactor.text('$key=overlap-secret; safe=1'),
          '$key=<redacted>; safe=1',
        );
      }
    },
  );
  test('redacts signatures, auth parameters and websocket credentials', () {
    final output = jsonEncode(
      DiagnosticRedactor.clean({
        'sign': 'map-sign-secret',
        'w_rid': 'map-wrid-secret',
        'authCode': 'map-auth-secret',
        'message':
            'sign=text-sign-secret\naccessToken=text-token-secret\n'
            'Basic basic-secret\nwss://user:pass@example.com:8443/socket?ticket=ws-secret#fragment-secret',
      }),
    );
    for (final secret in [
      'map-sign-secret',
      'map-wrid-secret',
      'map-auth-secret',
      'text-sign-secret',
      'text-token-secret',
      'basic-secret',
      'user:pass',
      'ws-secret',
      'fragment-secret',
    ]) {
      expect(output, isNot(contains(secret)));
    }
    expect(output, contains('wss://example.com:8443/socket'));
  });

  test('redacts credentials in maps, headers, URLs and quoted text', () {
    final output = jsonEncode(
      DiagnosticRedactor.clean({
        'Cookie': 'session-cookie-test',
        'accessToken': 'token-test-value',
        'message': 'Cookie: first=cookie-test-one; other=cookie-test-two\nAuthorization: Bearer auth-test-value\n{"password": "password-test-value"}\nhttps://user:pwd@host/path?sign=query-test-value',
        'path': r'C:\Users\SensitiveUser\private\file.txt',
        'key': '-----BEGIN PRIVATE KEY-----\nprivate-key-test-value\n-----END PRIVATE KEY-----',
        'credentials': 'apiKey=api-key-test-value\npasswd=passwd-test-value',
        'unixPath': '/home/PrivateUser/file',
      }),
    );
    for (final value in [
      'session-cookie-test',
      'token-test-value',
      'cookie-test-one',
      'cookie-test-two',
      'auth-test-value',
      'password-test-value',
      'query-test-value',
      'SensitiveUser',
      'user:pwd',
      'private-key-test-value',
      'api-key-test-value',
      'passwd-test-value',
      'PrivateUser',
    ]) {
      expect(output, isNot(contains(value)));
    }
    expect(output, contains('https://host/path'));
  });

  test('redacts signed queries in mpv filenames and relative URLs', () {
    final output = DiagnosticRedactor.text(
      "Audio 'track.m4s?e=synthetic-signature&mid=synthetic-user&upsig=synthetic-upsig' (aac)\n"
      '/video/chunk.m4s?token=synthetic-token&expires=123\n'
      '//cdn.example/chunk?sign=synthetic-cdn-signature#fragment',
    );
    for (final value in [
      'synthetic-signature',
      'synthetic-user',
      'synthetic-upsig',
      'synthetic-token',
      'synthetic-cdn-signature',
      '#fragment',
    ]) {
      expect(output, isNot(contains(value)));
    }
    expect(output, contains("Audio 'track.m4s?<redacted>' (aac)"));
    expect(output, contains('/video/chunk.m4s?<redacted>'));
  });

  test('redacting queries retains ordinary diagnostic questions', () {
    for (final text in [
      'GPU ready? paused=true',
      'GPU ready?yes',
      'assign=4',
    ]) {
      expect(DiagnosticRedactor.text(text), text);
    }
    expect(DiagnosticRedactor.text('?other=query-secret'), '?<redacted>');
  });

  test('redacts complete quoted and nested values while keeping JSON valid', () {
    const input =
        r'''{"token":"before, after; bracket} escaped\" last","api Key":{"first":"nested, tail","last":["nested-tail"]},"deviceId":"device value","elapsedMs":42}''';
    final output = DiagnosticRedactor.text(input);
    expect(jsonDecode(output), {
      'token': '<redacted>',
      'api Key': '<redacted>',
      'deviceId': '<redacted>',
      'elapsedMs': 42,
    });
    expect(DiagnosticRedactor.text(output), output);
  });

  test('recognizes escaped JSON quotes and unclosed secret values', () {
    final output = DiagnosticRedactor.text(
      r'''{\"password\":\"first; escaped\\\" still-secret\",\"ready\":true}''',
    );
    expect(output, r'''{\"password\":\"<redacted>\",\"ready\":true}''');
    expect(
      DiagnosticRedactor.text('token="before; unfinished-secret'),
      'token=<redacted>',
    );
  });

  test('redacts full header values and folded continuation lines', () {
    final output = DiagnosticRedactor.text(
      'Proxy-Authorization: Digest username="first", response="second"\r\n'
      '\tnonce="folded"\r\n'
      'xCustomCookie: "first"; other=cookie-tail\n'
      '  continued=cookie-folded\n'
      'X-Trace-Id: accepted',
    );
    expect(
      output,
      'Proxy-Authorization: <redacted>\r\n'
      'xCustomCookie: <redacted>\n'
      'X-Trace-Id: accepted',
    );
    expect(DiagnosticRedactor.text(output), output);
  });

  test('redacts credential pairs in structured header data', () {
    final output = DiagnosticRedactor.clean([
      {'name': 'Proxy-Authorization', 'value': 'pair-secret'},
      {'name': 'X-Trace-Id', 'value': 'trace-123'},
    ]);
    expect(output, [
      {'name': 'Proxy-Authorization', 'value': '<redacted>'},
      {'name': 'X-Trace-Id', 'value': 'trace-123'},
    ]);
  });

  test(
    'redacts userinfo in relative and playback URLs and hides file paths',
    () {
      final output = DiagnosticRedactor.text(
        'GET //user:pass@example.test/path?other=relative-secret#fragment\n'
        'PLAY rtsp://user:pass(word)@example.test:8554/live?stream=stream-secret\n'
        'track.m4s?value=sample(suffix)\n'
        'file:///storage/private-folder/media.m4s\n'
        r'\\WORKSTATION\private-share\media.m4s',
      );
      expect(
        output,
        'GET //example.test/path?<redacted>\n'
        'PLAY rtsp://example.test:8554/live?<redacted>\n'
        'track.m4s?<redacted>\n'
        '<local-path>\n<local-path>',
      );
      expect(DiagnosticRedactor.text(output), output);
    },
  );

  test('nested diagnostic payloads remain bounded', () {
    final large = List.generate(64, (_) => List.filled(64, 'x' * 10000));
    expect(jsonEncode(DiagnosticRedactor.clean(large)).length, lessThan(65536));
  });
  test('malformed sample sources remain readable and sanitized', () {
    for (final sources in [
      'token=source-secret',
      ['token=source-secret'],
      false,
    ]) {
      final output = DiagnosticRedactor.exportRecord({
        'type': 'sample',
        'state': 'ready',
        'sources': sources,
      });
      expect(output['state'], 'ready');
      expect(jsonEncode(output), isNot(contains('source-secret')));
    }
  });
}
