import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

final _directives = RegExp(
  r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
);

Iterable<String> dependencies(File file) => _directives
    .allMatches(file.readAsStringSync())
    .map((match) => match.group(1)!);

String? localDependency(File file, String uri) {
  const prefix = 'package:pili_aurora_next/';
  if (uri.startsWith(prefix)) return uri.substring(prefix.length);
  if (uri.contains(':')) return null;
  return path
      .relative(
        path.normalize(path.join(file.parent.path, uri)),
        from: 'lib',
      )
      .replaceAll('\\', '/');
}

void main() {
  const sharedRestrictions = [
    'package:flutter/',
    'package:get/',
    '/pages/',
    '/http/',
  ];
  const coreRestrictions = [
    ...sharedRestrictions,
    'package:dio/',
    '/storage',
  ];
  const rules = <String, List<String>>{
    'plugin/pl_player/playback/playback_session.dart': coreRestrictions,
    'plugin/pl_player/playback/network_recovery.dart': coreRestrictions,
    'features/download/data/download_repository.dart': [
      ...coreRestrictions,
      '/logger.dart',
    ],
    'services/settings/settings_backup.dart': [
      ...sharedRestrictions,
      'package:dio/',
      '/utils/storage',
      '/logger.dart',
    ],
    'services/settings/webdav_sync.dart': [
      ...sharedRestrictions,
      'package:flutter_smart_dialog/',
      '/utils/storage',
      '/device_utils',
    ],
    'features/download/data/download_manager.dart': ['/http/'],
  };
  test(
    'download feature enforces domain, application and presentation boundaries',
    () {
      final violations = <String>[];
      for (final file in Directory(
        'lib/features/download',
      ).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: 'lib')
            .replaceAll('\\', '/');
        final domain = source.startsWith('features/download/domain/');
        final application = source.startsWith('features/download/application/');
        final presentation = source.startsWith(
          'features/download/presentation/',
        );
        for (final uri in dependencies(file)) {
          final target = localDependency(file, uri);
          final isRouteCompatibility =
              presentation && uri == 'package:get/route_manager.dart';
          final forbidden =
              (uri.startsWith('package:get/') && !isRouteCompatibility) ||
              (domain &&
                  (uri.startsWith('package:flutter') ||
                      uri.startsWith('package:material_ui/') ||
                      uri.startsWith('package:dio/') ||
                      (target != null &&
                          !target.startsWith('features/download/domain/') &&
                          !target.startsWith('utils/extension/')))) ||
              (application &&
                  (target?.startsWith('features/download/presentation/') ==
                          true ||
                      target?.startsWith('pages/') == true ||
                      uri.startsWith('package:flutter_smart_dialog/'))) ||
              (presentation &&
                  (target?.startsWith('features/download/data/') == true ||
                      (target?.startsWith('http/') == true &&
                          target != 'http/loading_state.dart') ||
                      target?.startsWith('utils/storage') == true));
          if (forbidden) violations.add('$source -> $uri');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
  for (final feature in [
    'watch_later',
    'content_library',
    'history',
    'favorites',
    'subscriptions',
  ]) {
    test('$feature enforces its migrated Interface', () {
      final violations = <String>[];
      for (final file in Directory(
        'lib/features/$feature',
      ).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: 'lib')
            .replaceAll('\\', '/');
        for (final uri in dependencies(file)) {
          final target = localDependency(file, uri);
          final presentation = source.contains('/presentation/');
          final application = source.contains('/application/');
          final domain = source.contains('/domain/');
          final data = source.contains('/data/');
          final forbidden =
              (uri.startsWith('package:get/') &&
                  !(presentation && uri == 'package:get/route_manager.dart')) ||
              (domain &&
                  (uri.startsWith('package:flutter') ||
                      uri.startsWith('package:material_ui/') ||
                      target?.startsWith('pages/') == true ||
                      target?.startsWith('http/') == true ||
                      target?.contains('/application/') == true ||
                      target?.contains('/data/') == true ||
                      target?.contains('/presentation/') == true ||
                      target?.startsWith('utils/storage') == true)) ||
              (data &&
                  (target?.startsWith('pages/') == true ||
                      target?.contains('/presentation/') == true)) ||
              (application &&
                  (target?.startsWith('pages/') == true ||
                      target?.contains('/presentation/') == true ||
                      uri.startsWith('package:flutter_smart_dialog/'))) ||
              (presentation &&
                  (target?.contains('/data/') == true ||
                      (target?.startsWith('http/') == true &&
                          target != 'http/loading_state.dart') ||
                      target?.startsWith('utils/storage') == true));
          if (forbidden) violations.add('$source -> $uri');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }
  test('subscription legacy entries stay removed', () {
    const legacy = [
      'pages/subscription/',
      'pages/subscription_detail/',
      'models/remote/sub/',
    ];
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = path
          .relative(file.path, from: 'lib')
          .replaceAll('\\', '/');
      if (legacy.any(source.startsWith)) violations.add(source);
      for (final uri in dependencies(file)) {
        final target = localDependency(file, uri);
        if (target != null && legacy.any(target.startsWith)) {
          violations.add('$source -> $uri');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
  for (final entry in rules.entries) {
    test('${entry.key} respects its dependency boundary', () {
      final file = File('lib/${entry.key}');
      expect(
        dependencies(file).where(
          (uri) =>
              !(entry.key == 'services/settings/settings_backup.dart' &&
                  localDependency(file, uri) == 'utils/storage_key.dart') &&
              entry.value.any(
                (restriction) => restriction.startsWith('package:')
                    ? uri.startsWith(restriction)
                    : uri.contains(restriction),
              ),
        ),
        isEmpty,
        reason: file.path,
      );
    });
  }
  test(
    'main and app composition modules are never imported by lower layers',
    () {
      final violations = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: 'lib')
            .replaceAll('\\', '/');
        for (final uri in dependencies(file)) {
          final target = localDependency(file, uri);
          if (target == 'main.dart' ||
              (source != 'main.dart' &&
                  !source.startsWith('app/') &&
                  (target?.startsWith('app/') ?? false))) {
            violations.add('$source -> $uri');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
