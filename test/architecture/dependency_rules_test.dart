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
    'account',
    'watch_later',
    'content_library',
    'content_discovery',
    'community',
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
  test('recommendation state has no legacy controller or settings-to-page dependency', () {
    const removed = [
      'pages/rcmd/controller.dart',
      'pages/rcmd/viewport.dart',
      'pages/hot/controller.dart',
      'pages/live/controller.dart',
      'pages/live_area_detail/controller.dart',
      'pages/live_area_detail/child/controller.dart',
      'pages/rank/controller.dart',
      'pages/rank/zone/controller.dart',
      'pages/popular_series/controller.dart',
      'pages/popular_precious/controller.dart',
      'pages/pgc/controller.dart',
      'pages/dynamics/controller.dart',
      'pages/dynamics_tab/controller.dart',
      'pages/bubble/controller.dart',
      'pages/emote/controller.dart',
    ];
    final violations = <String>[];
    for (final root in ['lib', 'tool']) {
      for (final file in Directory(root).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: root)
            .replaceAll('\\', '/');
        if (root == 'lib' && removed.contains(source)) violations.add(source);
        for (final uri in dependencies(file)) {
          final target = localDependency(file, uri);
          final settingsToPage =
              source == 'pages/setting/models/recommend_settings.dart' &&
              target?.startsWith('pages/rcmd/') == true;
          final enumDispatch =
              source == 'models/common/home_tab_type.dart' &&
              (uri.startsWith('package:get/') ||
                  target?.endsWith('/controller.dart') == true);
          if (removed.contains(target) || settingsToPage || enumDispatch) {
            violations.add('$root/$source -> $uri');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
  test('migrated discovery pages keep business state behind Riverpod', () {
    final violations = <String>[];
    for (final entry in [
      'hot/view.dart',
      'rank/view.dart',
      'rank/zone/view.dart',
      'popular_series/view.dart',
      'popular_precious/view.dart',
      'live/view.dart',
      'live_area_detail/view.dart',
      'live_area_detail/child/view.dart',
      'pgc/view.dart',
      'dynamics/view.dart',
      'dynamics_tab/view.dart',
      'bubble/view.dart',
      'emote/view.dart',
    ]) {
      final file = File('lib/pages/$entry');
      for (final uri in dependencies(file)) {
        final target = localDependency(file, uri);
        if ((target?.startsWith('http/') == true &&
                target != 'http/loading_state.dart') ||
            target?.startsWith('utils/storage') == true ||
            target?.startsWith('utils/accounts') == true ||
            (target?.startsWith('pages/common/common_') == true &&
                target != 'pages/common/common_page.dart')) {
          violations.add('$entry -> $uri');
        }
      }
      final source = file.readAsStringSync();
      for (final match in RegExp(r'Get\.find<([^>]+)>').allMatches(source)) {
        if (!['HomeController', 'MainController'].contains(match.group(1))) {
          violations.add('$entry finds a business controller');
        }
      }
      if (RegExp(r'Get\.(put|putOrFind|lazyPut)|Obx\(|\.obs\b|Rx[nA-Z]')
          .hasMatch(source)) {
        violations.add('$entry contains legacy business state');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
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
  test('account identity and profile have no legacy GetX state or page dependencies', () {
    const removed = [
      'services/account_service.dart',
      'pages/mine/controller.dart',
      'pages/mine/widgets/',
      'models/user/info.dart',
      'models/user/stat.dart',
    ];
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = path
          .relative(file.path, from: 'lib')
          .replaceAll('\\', '/');
      if (removed.any(source.startsWith)) violations.add(source);
      for (final uri in dependencies(file)) {
        final target = localDependency(file, uri);
        if (target == null) continue;
        if (removed.any(target.startsWith) ||
            ((source == 'utils/accounts.dart' ||
                    source == 'utils/login_utils.dart' ||
                    source == 'services/account_providers.dart') &&
                target.startsWith('pages/'))) {
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
