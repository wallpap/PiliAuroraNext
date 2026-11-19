import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'dart_source.dart';

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
    'search',
    'following',
    'community',
    'member_space',
    'playback',
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
      'pages/live_emote/controller.dart',
      'pages/dynamics_create_vote/controller.dart',
      'pages/dynamics_create_reserve/controller.dart',
      'pages/dynamics_topic/controller.dart',
      'pages/dynamics_topic_rcmd/controller.dart',
      'pages/dynamics_select_topic/controller.dart',
      'pages/dynamics_mention/controller.dart',
      'pages/member_dynamics/controller.dart',
      'pages/common/dyn/like_list/controller.dart',
      'pages/common/dyn/repost_list/controller.dart',
      'services/blocked_authors.dart',
      'services/cooperative_authors.dart',
      'utils/media_author_filter.dart',
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
                  target?.startsWith('pages/') == true);
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
      'live_emote/view.dart',
      'dynamics_create_vote/view.dart',
      'dynamics_create_reserve/view.dart',
      'dynamics_topic/view.dart',
      'dynamics_topic_rcmd/view.dart',
      'dynamics_select_topic/view.dart',
      'dynamics_mention/view.dart',
      'member_dynamics/view.dart',
      'common/dyn/like_list/view.dart',
      'common/dyn/repost_list/view.dart',
    ]) {
      final file = File('lib/pages/$entry');
      for (final uri in dependencies(file)) {
        final target = localDependency(file, uri);
        if ((target?.startsWith('http/') == true &&
                target != 'http/loading_state.dart') ||
            target?.contains('/data/') == true ||
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
  test(
    'dynamic transports stay in community data',
    () {
      final violations = <String>[];
      const owners = {
        'MemberHttp.memberDynamic':
            'features/community/data/dynamics_repository.dart',
        'MsgHttp.removeDynamic':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.setTop':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.rmTop':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.createDynamic':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.editDyn':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.thumbDynamic':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.dynamicDetail':
            'features/community/data/dynamics_repository.dart',
        'DynamicsHttp.dynPrivatePubSetting':
            'features/community/data/dynamics_repository.dart',
        'ReplyHttp.replySubjectModify':
            'features/community/data/dynamics_repository.dart',
        'DynGrpc.likeList':
            'features/community/data/dynamic_activity_repository.dart',
        'DynGrpc.repostList':
            'features/community/data/dynamic_activity_repository.dart',
      };
      final candidates = owners.keys.toSet();
      final transportNames = candidates
          .map((key) => key.split('.').first)
          .toSet();
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: 'lib')
            .replaceAll('\\', '/');
        final body = file.readAsStringSync();
        if (!transportNames.any(body.contains)) continue;
        for (final call in matchingStaticCalls(body, candidates)) {
          if (source != owners[call]) {
            violations.add('$source calls $call');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
  test('space pages and shared comment panels do not restore legacy query controllers', () {
    const removed = [
      'pages/member/controller.dart',
      'pages/member_contribute/controller.dart',
      'pages/member_favorite/controller.dart',
      'pages/member_opus/controller.dart',
      'pages/member_pgc/controller.dart',
      'pages/member_video/controller.dart',
      'pages/member_video_web/archive/controller.dart',
      'pages/member_video_web/base/controller.dart',
      'pages/member_video_web/season_series/controller.dart',
      'pages/common/reply_controller.dart',
      'pages/main_reply/controller.dart',
      'pages/video/reply/controller.dart',
      'pages/video/reply_reply/controller.dart',
    ];
    for (final entry in removed) {
      expect(File('lib/$entry').existsSync(), isFalse, reason: entry);
    }
    const views = [
      'pages/member_favorite/view.dart',
      'pages/member_video/view.dart',
      'pages/member_video_web/base/view.dart',
      'pages/common/dyn/common_dyn_page.dart',
      'pages/main_reply/view.dart',
      'pages/video/reply/view.dart',
      'pages/video/reply_reply/view.dart',
    ];
    for (final entry in views) {
      final file = File('lib/$entry');
      final forbidden = dependencies(file)
          .map((uri) => localDependency(file, uri))
          .where(
            (target) =>
                target != null &&
                (removed.contains(target) ||
                    (target.startsWith('http/') &&
                        target != 'http/loading_state.dart') ||
                    target == 'grpc/reply.dart'),
          );
      expect(forbidden, isEmpty, reason: entry);
    }
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
  test('migrated community models have a single feature owner', () {
    const legacy = [
      'models/remote/emote/',
      'models/remote/live/live_emote/',
      'models/dynamics/vote_model.dart',
      'models/remote/dynamic/dyn_reserve_info/',
      'models/remote/dynamic/dyn_topic_top/',
      'models/remote/dynamic/dyn_topic_feed/',
      'models/remote/dynamic/dyn_topic_pub_search/',
      'models/remote/dynamic/dyn_mention/',
    ];
    final violations = <String>[];
    for (final root in ['lib', 'test', 'tool']) {
      for (final file in Directory(root).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: root)
            .replaceAll('\\', '/');
        if (root == 'lib' && legacy.any(source.startsWith)) {
          violations.add(source);
        }
        for (final uri in dependencies(file)) {
          final target = localDependency(file, uri);
          if (target != null && legacy.any(target.startsWith)) {
            violations.add('$root/$source -> $uri');
          }
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
