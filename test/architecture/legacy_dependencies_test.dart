import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'dart_source.dart';

const _getxTypes = {
  'FullLifeCycleController',
  'GetLifeCycleBase',
  'GetLifeCycleMixin',
  'GetxController',
  'GetxService',
  'GetxServiceMixin',
  'RxController',
  'SuperController',
};

const _legacyUtilities = {
  'utils/accounts.dart',
  'utils/app_sign.dart',
  'utils/credential_cipher.dart',
  'utils/danmaku_utils.dart',
  'utils/global_data.dart',
  'utils/login_utils.dart',
  'utils/media_author_filter.dart',
  'utils/recommend_filter.dart',
  'utils/reply_filter.dart',
  'utils/reply_utils.dart',
  'utils/request_utils.dart',
  'utils/storage.dart',
  'utils/storage_pref.dart',
  'utils/storage_utils.dart',
  'utils/video_utils.dart',
  'utils/wbi_sign.dart',
};

bool _isPresentation(String source) =>
    source.startsWith('pages/') ||
    source.startsWith('common/widgets/') ||
    (source.startsWith('features/') && source.contains('/presentation/'));

bool _isRestricted(String target) =>
    (target.startsWith('http/') && target != 'http/loading_state.dart') ||
    (target.startsWith('grpc/') && !target.startsWith('grpc/bilibili/')) ||
    _legacyUtilities.contains(target) ||
    target.startsWith('package:dio/') ||
    target.startsWith('package:grpc/') ||
    target.startsWith('package:hive_ce/') ||
    target.startsWith('package:shared_preferences/');

void main() {
  test('application code introduces no new legacy dependency', () {
    final baseTypes = <String, Set<String>>{};
    final violations = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = path
          .relative(file.path, from: 'lib')
          .replaceAll('\\', '/');
      if (source.startsWith('grpc/bilibili/') || source.endsWith('.g.dart')) {
        continue;
      }
      final unit = parseSource(file.readAsStringSync());
      if (_isPresentation(source)) {
        for (final uri in unitDependencies(unit)) {
          final target = localDependency(file, uri) ?? uri;
          if (_isRestricted(target)) violations.add('$source -> $target');
        }
      }
      for (final (:name, :base) in typeInheritance(unit)) {
        baseTypes.putIfAbsent(base, () => {}).add('$source#$name');
      }
    }

    final pending = _getxTypes.toList();
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final base = pending.removeLast();
      if (!visited.add(base)) continue;
      for (final subtype in baseTypes[base] ?? const <String>{}) {
        violations.add('$subtype -> $base');
        pending.add(subtype.split('#').last);
      }
    }

    final baseline = File('test/architecture/legacy_dependencies.txt')
        .readAsLinesSync()
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet();
    final added = violations.difference(baseline).toList()..sort();
    final removed = baseline.difference(violations).toList()..sort();
    expect(
      added,
      isEmpty,
      reason: 'New legacy dependencies:\n${added.join('\n')}',
    );
    expect(
      removed,
      isEmpty,
      reason: 'Remove obsolete baseline entries:\n${removed.join('\n')}',
    );
  });
}
