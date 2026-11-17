import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dependency_rules_test.dart' show dependencies, localDependency;

void main() {
  test('播放器展示模块独立成库，不反向依赖视图装配入口', () {
    final violations = <String>[];
    for (final file in Directory('lib/plugin/pl_player/view').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final uri in dependencies(file)) {
        if (localDependency(file, uri) == 'plugin/pl_player/view/view.dart') {
          violations.add('${file.path} -> $uri');
        }
      }
      if (RegExp(r'^\s*part\s', multiLine: true).hasMatch(file.readAsStringSync())) {
        violations.add('${file.path} shares a library through part');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('输入和输出协调不直接依赖业务页面、HTTP 或全局存储', () {
    for (final name in ['player_gestures', 'video_output']) {
      final file = File('lib/plugin/pl_player/view/$name.dart');
      for (final uri in dependencies(file)) {
        final target = localDependency(file, uri);
        expect(
          target != null &&
              (target.startsWith('pages/') ||
                  target.startsWith('http/') ||
                  target.startsWith('utils/storage')),
          isFalse,
          reason: '${file.path} -> $uri',
        );
      }
    }
  });
}
