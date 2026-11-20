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
      '/services/settings/storage',
      '/logger.dart',
    ],
    'services/settings/webdav_sync.dart': [
      ...sharedRestrictions,
      'package:flutter_smart_dialog/',
      '/services/settings/storage',
      '/platform/device_actions',
    ],
    'features/download/data/download_manager.dart': ['/http/'],
    'services/settings/window_preferences.dart': [
      'package:get/',
      '/pages/',
      '/services/settings/stored_preferences',
    ],
    'services/settings/theme_preferences.dart': [
      'package:get/',
      '/pages/',
      '/services/settings/stored_preferences',
    ],
  };
  test('recommendation state has no legacy controller or settings-to-page dependency', () {
    const removed = [
      'pages/main/controller.dart',
      'pages/home/controller.dart',
      'pages/rcmd/controller.dart',
      'pages/rcmd/view.dart',
      'pages/rcmd/viewport.dart',
      'pages/hot/controller.dart',
      'pages/live/controller.dart',
      'pages/live_area/controller.dart',
      'pages/live_area_detail/controller.dart',
      'pages/live_area_detail/child/controller.dart',
      'pages/common/discovery_list_controller.dart',
      'pages/video/related/controller.dart',
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
      for (final file in dartFiles(root)) {
        final source = path
            .relative(file.path, from: root)
            .replaceAll('\\', '/');
        if (root == 'lib' && removed.contains(source)) violations.add(source);
        for (final uri in dependencies(file)) {
          final target = localDependency(file, uri);
          final settingsToPage =
              source == 'pages/setting/models/recommend_settings.dart' &&
              target?.startsWith('pages/rcmd/') == true;
          if (removed.contains(target) || settingsToPage) {
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
      'home/view.dart',
      'hot/view.dart',
      'rank/view.dart',
      'rank/zone/view.dart',
      'popular_series/view.dart',
      'popular_precious/view.dart',
      'live/view.dart',
      'live_area/view.dart',
      'live_area_detail/view.dart',
      'live_area_detail/child/view.dart',
      'video/related/view.dart',
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
        if (target?.startsWith('pages/common/common_') == true &&
            target != 'pages/common/common_page.dart') {
          violations.add('$entry -> $uri');
        }
      }
      final source = file.readAsStringSync();
      if (RegExp(r'Obx\(|\.obs\b|Rx[nA-Z]').hasMatch(source)) {
        violations.add('$entry contains legacy business state');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
  test(
    'dynamic and reply attachment transports stay in community data',
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
        'ReplyGrpc.searchItem':
            'features/community/data/comments/reply_search_repository.dart',
      };
      final candidates = owners.keys.toSet();
      final transportNames = candidates
          .map((key) => key.split('.').first)
          .toSet();
      for (final file in dartFiles('lib')) {
        final source = libPath(file);
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
            (target) => target != null && removed.contains(target),
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
    for (final file in dartFiles('lib')) {
      final source = libPath(file);
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
  test(
    'models and utilities stay with their owners and core stays neutral',
    () {
      const retired = ['models/', 'utils/', 'services/danmaku/work_quota.dart'];
      final violations = <String>[];
      for (final root in ['lib', 'test', 'tool']) {
        for (final file in dartFiles(root)) {
          final source = path
              .relative(file.path, from: root)
              .replaceAll('\\', '/');
          if (root == 'lib' && retired.any(source.startsWith)) {
            violations.add(source);
          }
          for (final uri in dependencies(file)) {
            final target = localDependency(file, uri);
            final isCore = root == 'lib' && source.startsWith('core/');
            final coreDependency =
                target?.startsWith('core/') == true ||
                (uri.startsWith('dart:') && uri != 'dart:ui') ||
                uri.startsWith('package:intl/');
            if ((target != null && retired.any(target.startsWith)) ||
                (isCore && !coreDependency)) {
              violations.add('$root/$source -> $uri');
            }
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
  test('account identity and profile have no legacy GetX state or page dependencies', () {
    const removed = [
      'services/account_service.dart',
      'pages/mine/controller.dart',
      'pages/mine/widgets/',
      'models/user/info.dart',
      'models/user/stat.dart',
    ];
    final violations = <String>[];
    for (final file in dartFiles('lib')) {
      final source = libPath(file);
      if (removed.any(source.startsWith)) violations.add(source);
      for (final uri in dependencies(file)) {
        final target = localDependency(file, uri);
        if (target == null) continue;
        if (removed.any(target.startsWith)) {
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
                  localDependency(file, uri) ==
                      'services/settings/storage_key.dart') &&
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
      for (final file in dartFiles('lib')) {
        final source = libPath(file);
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
