import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pili_aurora_next/common/widgets/scale_app.dart';
import 'package:pili_aurora_next/http/search.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/home_tab_type.dart';
import 'package:pili_aurora_next/features/app_shell/domain/nav_bar_config.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/recommended_video.dart';
import 'package:pili_aurora_next/pages/home/view.dart';
import 'package:pili_aurora_next/pages/main/view.dart';
import 'package:pili_aurora_next/pages/search_result/view.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/services/diagnostics/process_metrics.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_id.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:material_ui/material_ui.dart' show TabBar, TabController;
import 'package:window_manager/window_manager.dart';

import 'feed_loading.dart';
import 'memory_logging.dart' as logging;
import 'mounted_state.dart';

Future<void> _until(bool Function() ready, String stage) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(seconds: 60)) {
      throw TimeoutException(stage);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

TabController? _searchTabs(State<SearchResultPage> page) {
  TabController? tabs;
  void visit(Element element) {
    if (tabs != null) return;
    if (element.widget case TabBar(:final controller?)) {
      tabs = controller;
      return;
    }
    element.visitChildren(visit);
  }

  page.context.visitChildElements(visit);
  return tabs;
}

/// 独立种子的真实页面复访与播放对照；仅在最终报告保存后卸载根页面。
Future<void> main(List<String> arguments) async {
  ScaledWidgetsFlutterBinding.ensureInitialized();
  final navigationOnly = arguments.contains('--navigation-only');
  final output = File(Platform.environment['PILIAURORANEXT_STUTTER_OUTPUT']!);
  final frames = <Map<String, Object?>>[];
  final stages = <Map<String, Object?>>[];
  final events = <Map<String, Object?>>[];
  final gaps = <Map<String, Object?>>[];
  final snapshots = <Map<String, Object?>>[];
  final process = ProcessMetrics();
  final clock = Stopwatch()..start();
  final report = <String, Object?>{
    'schema': 1,
    'pid': pid,
    'state': 'running',
    'validWorkload': false,
    'navigationOnly': navigationOnly,
    'frames': frames,
    'stages': stages,
    'events': events,
    'timerGaps': gaps,
    'playbackSnapshots': snapshots,
  };
  void timings(List<FrameTiming> values) {
    for (final f in values) {
      final finish = f.timestampInMicroseconds(FramePhase.rasterFinishWallTime);
      final start =
          finish -
          (f.timestampInMicroseconds(FramePhase.rasterFinish) -
              f.timestampInMicroseconds(FramePhase.buildStart));
      frames.add({
        'startUtcUs': start,
        'rasterFinishUtcUs': finish,
        'buildMs': f.buildDuration.inMicroseconds / 1000,
        'rasterMs': f.rasterDuration.inMicroseconds / 1000,
        'totalMs': f.totalSpan.inMicroseconds / 1000,
        'vsyncOverheadMs': f.vsyncOverhead.inMicroseconds / 1000,
      });
    }
  }

  SchedulerBinding.instance.addTimingsCallback(timings);
  var lastTick = clock.elapsedMicroseconds;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final now = clock.elapsedMicroseconds;
    final gap = now - lastTick;
    if (gap > 12000) {
      gaps.add({
        'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
        'gapMs': gap / 1000,
      });
    }
    lastTick = now;
  });
  final diagnostics = Diagnostics.instance;
  Future<T> stage<T>(String name, Future<T> Function() work) async {
    await output.parent.create(recursive: true);
    await File('${output.parent.path}/progress.json').writeAsString(
      jsonEncode({
        'stage': name,
        'pid': pid,
        'elapsedMs': clock.elapsedMilliseconds,
      }),
    );
    final row = <String, Object?>{
      'name': name,
      'startUtcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
    };
    stages.add(row);
    try {
      return await work();
    } finally {
      row['endUtcUs'] = DateTime.now().toUtc().microsecondsSinceEpoch;
      row['process'] = process.sample();
      if (navigationOnly && name != 'startup') {
        row['windowVisible'] = await windowManager.isVisible();
      }
    }
  }

  void mark(String name) => events.add({
    'name': name,
    'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
  });
  Future<void> pause(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
  Future<void> mode(String mode) async {
    await diagnostics.configure(
      level: mode == 'off' ? DiagnosticLogLevel.off : DiagnosticLogLevel.debug,
      playerLevel: mode == 'debug'
          ? DiagnosticLogLevel.debug
          : mode == 'off'
          ? DiagnosticLogLevel.off
          : DiagnosticLogLevel.info,
      tracing: mode != 'off',
      intervalMs: 250,
    );
    await pause(1500);
  }

  try {
    await stage('startup', () => logging.main(arguments));
    await _until(
      () =>
          findMountedState<MainAppState>() != null && !SmartDialog.checkExist(),
      'startup',
    );
    final main = findMountedState<MainAppState>()!;
    if (!main.mounted) throw StateError('main page unmounted');
    report['refreshRateHz'] = View.of(main.context).display.refreshRate;
    if (navigationOnly) {
      if (!await windowManager.isVisible()) await windowManager.show();
      final visibilityWait = Stopwatch()..start();
      while (!await windowManager.isVisible()) {
        if (visibilityWait.elapsed > const Duration(seconds: 5)) {
          throw TimeoutException('window visible');
        }
        await pause(100);
      }
      report['windowVisible'] = true;
    }
    void selectMain(NavigationBarType tab) {
      if (!main.showDestination(tab)) throw StateError('missing main tab');
    }

    selectMain(.home);
    HomePageState? mountedHome;
    await _until(
      () => (mountedHome = findMountedDescendant<HomePageState>(main)) != null,
      'homePage',
    );
    final home = mountedHome!;
    void selectHome(HomeTabType tab) {
      selectMain(NavigationBarType.home);
      if (!home.showTab(tab)) throw StateError('missing home tab');
    }

    const tabs = [
      HomeTabType.rcmd,
      HomeTabType.hot,
      HomeTabType.rank,
      HomeTabType.bangumi,
      HomeTabType.cinema,
      HomeTabType.live,
    ];
    final visits = <Map<String, Object?>>[];
    report['visits'] = visits;
    await mode('debug');
    for (final tab in tabs) {
      await stage('first:${tab.name}', () async {
        mark('first:${tab.name}');
        selectHome(tab);
        await pause(5000);
        final source = diagnostics.readSources(prefix: 'homePage');
        final controller = home.registeredPage(tab);
        final loaded = feedLoading(controller)?.isSuccess ?? false;
        visits.add({'tab': tab.name, 'source': source, 'loaded': loaded});
        final scroll = controller?.scrollController;
        if (scroll != null &&
            scroll.hasClients &&
            scroll.positions.length == 1) {
          await scroll.animateTo(
            (scroll.position.viewportDimension * .8).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
        await pause(1500);
      });
    }
    // 顺序ABBA，减少预热及时间漂移对诊断开关对照的影响。
    for (final (i, label) in ['debug', 'off', 'off', 'debug'].indexed) {
      await mode(label);
      await stage('revisit:$i:$label', () async {
        for (var round = 0; round < 2; round++) {
          for (final tab in tabs) {
            mark('revisit:$i:$round:${tab.name}');
            selectHome(tab);
            await pause(800);
          }
          for (final tab in [
            NavigationBarType.dynamics,
            NavigationBarType.mine,
            NavigationBarType.home,
          ]) {
            mark('revisit:$i:$round:main:${tab.name}');
            selectMain(tab);
            await pause(800);
          }
        }
        await pause(1200);
      });
    }
    if (navigationOnly) {
      String? currentRoutePath() => Uri.tryParse(Get.currentRoute)?.path;

      Future<void> waitForRoute(String route) async {
        try {
          await _until(() => currentRoutePath() == route, route);
        } on TimeoutException {
          final results = findMountedState<State<SearchResultPage>>();
          final resultRoute = results != null && results.mounted
              ? ModalRoute.of(results.context)
              : null;
          report['routeTimeout'] = {
            'action': events.last['name'],
            'expectedPath': route,
            'observedPath': currentRoutePath(),
            'resultRouteCurrent': resultRoute?.isCurrent,
            'resultRouteActive': resultRoute?.isActive,
            'canPop': Get.key.currentState?.canPop(),
            'smartDialogOpen': SmartDialog.checkExist(),
          };
          rethrow;
        }
      }

      await mode('debug');
      for (final round in [0, 1, 2]) {
        await stage('routes:$round', () async {
          for (final route in ['/search', '/history', '/setting']) {
            mark('routes:$round:push:$route');
            unawaited(Get.toNamed<void>(route));
            await waitForRoute(route);
            await pause(1200);
            if (route == '/search') {
              mark('routes:$round:push:/searchResult');
              unawaited(
                Get.toNamed<void>(
                  '/searchResult',
                  parameters: {'keyword': '开源'},
                  arguments: {'fromSearch': true},
                ),
              );
              await waitForRoute('/searchResult');
              TabController? tabs;
              await _until(() {
                final results = findMountedState<State<SearchResultPage>>();
                if (results != null) tabs = _searchTabs(results);
                return tabs != null;
              }, 'search tabs');
              await pause(1600);
              mark('routes:$round:tab:/searchResult');
              tabs!.animateTo(1);
              await pause(1600);
              mark('routes:$round:pop:/searchResult');
              Get.back<void>();
              await waitForRoute('/search');
              await pause(1200);
            }
            mark('routes:$round:pop:$route');
            Get.back<void>();
            await waitForRoute('/');
            await pause(1200);
          }
        });
      }
      report['validWorkload'] =
          stages.skip(1).every((stage) => stage['windowVisible'] == true) &&
          visits.every((visit) => visit['loaded'] == true);
      report['state'] = 'completed';
      return;
    }
    // 设置只影响隔离种子；播放固定同一条推荐，复测首次/再次起播。
    for (final entry in {
      SettingBoxKey.desktopVolume: 0.0,
      SettingBoxKey.playerVolume: 0.0,
      SettingBoxKey.enableAutoEnter: false,
      SettingBoxKey.autoPiP: false,
      SettingBoxKey.continuePlayInBackground: false,
      SettingBoxKey.autoPlayEnable: true,
    }.entries) {
      await GStorage.setting.put(entry.key, entry.value);
    }
    selectHome(HomeTabType.rcmd);
    await _until(
      () =>
          (home.registeredPage(HomeTabType.rcmd) is RecommendationPageHandle) &&
          ((home.registeredPage(HomeTabType.rcmd) as RecommendationPageHandle)
                  .snapshot
                  .loading
                  .dataOrNull
                  ?.isNotEmpty ??
              false),
      'recommendations',
    );
    final recommendations =
        (home.registeredPage(HomeTabType.rcmd) as RecommendationPageHandle);
    final item = recommendations.snapshot.loading.dataOrNull!
        .whereType<BaseRcmdVideoItemModel>()
        .where(
          (x) =>
              !recommendations.isPending(x) &&
              x.goto == 'av' &&
              (x.aid != null || x.bvid?.isNotEmpty == true) &&
              x.duration >= 90,
        )
        .first;
    final bvid = item.bvid ?? IdUtils.av2bv(item.aid!);
    final cid =
        item.cid ??
        (await SearchHttp.ab2cWithDimension(aid: item.aid, bvid: bvid))?.cid;
    if (cid == null) throw StateError('missing cid');
    for (var round = 0; round < 2; round++) {
      await mode('debug');
      final player = PlPlayerController.getInstance();
      player.volume.value = 0;
      player.muted.value = true;
      player.autoPipEnabled.value = false;
      player.continuePlayInBackground.value = false;
      final tag = 'stutter-probe-$round';
      await stage('load:$round', () async {
        mark('load:$round');
        PageUtils.toVideoPage(
          aid: item.aid,
          bvid: bvid,
          cid: cid,
          cover: item.cover,
          title: item.title,
          progress: 0,
          extraArguments: {'heroTag': tag},
        );
        await _until(
          () =>
              player.currentPlaybackSnapshot.phase == PlaybackPhase.ready &&
              player.currentPlaybackSnapshot.actual.playing == true &&
              player.videoFramePresented.value,
          'playing',
        );
      });
      final detail = Get.find<VideoDetailController>(tag: tag);
      final startPosition = player.positionInMilliseconds;
      for (final (i, label) in ['debug', 'off', 'off', 'debug'].indexed) {
        await mode(label);
        await stage('play:$round:$i:$label', () async {
          for (var second = 0; second < 8; second++) {
            snapshots.add({
              'utcUs': DateTime.now().toUtc().microsecondsSinceEpoch,
              'round': round,
              'mode': label,
              'sources': diagnostics.readSources(prefix: 'danmaku.layer'),
              'player': diagnostics.readSources(prefix: 'player.'),
            });
            await pause(1000);
          }
        });
      }
      report['playbackAdvancedMs$round'] =
          player.positionInMilliseconds - startPosition;
      await stage('return:$round', () async {
        Get.back<void>();
        await _until(() => detail.isClosed, 'detailClose');
        await player.playbackReleased.timeout(const Duration(seconds: 30));
        await pause(2000);
      });
    }
    report['validWorkload'] =
        visits.every((v) => v['loaded'] == true) &&
        (report['playbackAdvancedMs0'] as int) >= 25000 &&
        (report['playbackAdvancedMs1'] as int) >= 25000;
    report['state'] = 'completed';
  } catch (error, stack) {
    report['state'] = 'failed';
    report['errorType'] = error.runtimeType.toString();
    report['error'] = error.toString();
    report['stack'] = stack.toString();
  } finally {
    await pause(1500); // 等待最后一批FrameTiming上报。
    heartbeat.cancel();
    SchedulerBinding.instance.removeTimingsCallback(timings);
    await diagnostics.flush();
    report['finalProcess'] = process.sample();
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    await logging.closeProbeWindow();
  }
}
