import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pili_aurora_next/app/app_paths.dart';
import 'package:pili_aurora_next/app/platform_setup.dart';
import 'package:pili_aurora_next/common/appearance/theme_builder.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/common/widgets/scale_app.dart';
import 'package:pili_aurora_next/features/download/domain/download_entry.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/platform/files/path_actions.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/presentation_profile.dart';
import 'package:pili_aurora_next/router/app_pages.dart';
import 'package:pili_aurora_next/services/app_icon.dart';
import 'package:pili_aurora_next/services/cache/image_cache.dart';
import 'package:pili_aurora_next/services/logger.dart';
import 'package:pili_aurora_next/services/service_locator.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import 'page_replay_observation.dart';

Future<void> main() async {
  if (!Platform.isAndroid) throw UnsupportedError('仅支持 Android');
  ScaledWidgetsFlutterBinding.ensureInitialized();
  const lengthMs = int.fromEnvironment('PAGE_REPLAY_DURATION_MS');
  if (lengthMs < 5000) throw ArgumentError('需要至少 5 秒的样片时长');
  final root =
      await getExternalStorageDirectory() ??
      (throw StateError('Android 应用外部存储不可用'));
  final fixture = File('${root.path}/video/${PathUtils.videoNameType1}');
  if (!fixture.existsSync()) {
    debugPrint('ANDROID_PAGE_REPLAY_WAITING_FOR_MEDIA');
    return;
  }

  const cid = 1;
  const positionKey = '$cid';
  final report = <String, Object?>{'passed': false};
  var step = 'initialize';
  var deniedHttpRequests = 0;
  try {
    initializePresentationEngineConfiguration();
    MediaKit.ensureInitialized();
    await initializeSupportPath();
    await initializeTemporaryPath();
    await LoggerUtils.prepare();
    await GStorage.init(memorySnapshot: const {});
    await GStorage.setting.putAll({
      SettingBoxKey.dynamicColor: false,
      SettingBoxKey.enableAutoEnter: false,
      SettingBoxKey.autoPlayEnable: true,
      SettingBoxKey.preInitPlayer: false,
      SettingBoxKey.showVideoReply: false,
      SettingBoxKey.showRelatedVideo: false,
      SettingBoxKey.enableHA: true,
    });
    await LoggerUtils.initialize();
    AppIcon.load();
    await CacheManager.ensureInitialized();
    await initializePlatformServices();
    await initializePlatformWindow();
    Request();
    Request.dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          deniedHttpRequests++;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'code': -1, 'message': 'offline playback probe'},
            ),
          );
        },
      ),
    );
    Request.setCookie(syncWebView: false);

    final (light, dark) = ThemeUtils.getAllTheme();
    final videoRoute = Routes.getPages.singleWhere(
      (page) => page.name == '/videoV',
    );
    runApp(
      ProviderScope(
        child: GetMaterialApp(
          theme: light,
          darkTheme: dark,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          defaultTransition: Transition.noTransition,
          builder: FlutterSmartDialog.init(),
          navigatorObservers: [routeObserver, FlutterSmartDialog.observer],
          home: const Scaffold(),
          getPages: [videoRoute],
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;

    final entry =
        BiliDownloadEntryInfo(
            isCompleted: true,
            totalBytes: fixture.lengthSync(),
            downloadedBytes: fixture.lengthSync(),
            title: 'Android replay fixture',
            typeTag: 'video',
            cover: '',
            preferedVideoQuality: 80,
            guessedTotalBytes: fixture.lengthSync(),
            totalTimeMilli: lengthMs,
            danmakuCount: 0,
            avid: 1,
            bvid: 'BV-local-replay',
            pageData: PageInfo(
              cid: cid,
              page: 1,
              hasAlias: false,
              tid: 0,
              width: 960,
              height: 540,
            ),
          )
          ..entryDirPath = root.path
          ..pageDirPath = fixture.parent.path;
    Future<(PlPlayerController, VideoDetailController)> openPage() {
      unawaited(
        Get.toNamed<void>(
          videoRoute.name,
          arguments: {
            'aid': entry.avid,
            'bvid': entry.bvid,
            'cid': cid,
            'heroTag': 'android-page-replay',
            'videoType': VideoType.ugc,
            'sourceType': SourceType.file,
            'entry': entry,
            'title': entry.title,
            'dirPath': root.path,
          },
        ),
      );
      return _waitFor(() {
        final player = PlPlayerController.instance;
        final page = mountedVideoPage(player);
        if (player == null ||
            page == null ||
            !page.playbackOwner.hasLoadedMedia) {
          return null;
        }
        return (player, page);
      });
    }

    step = 'open-completed-history';
    await GStorage.watchProgress.put(positionKey, lengthMs);
    final (player, page) = await openPage();
    report['firstOpen'] = await _observeFreshPlayback(player);

    step = 'reopen-mounted-page';
    final replay = await observeReplayProgress(player, page);
    report['samePage'] = replay;
    if (replay['passed'] != true) throw StateError('same-page replay failed');

    step = 'leave-at-eof';
    await player.seekTo(const Duration(milliseconds: lengthMs - 1000));
    await _waitFor(() => player.isCompleted ? true : null);
    Get.back<void>();
    await _waitFor(() => mountedVideoPage(player) == null ? true : null);
    final saved = GStorage.watchProgress.get(positionKey);
    report['savedAtExitMs'] = saved;
    if (saved != lengthMs) throw StateError('completed history was not saved');
    await player.playbackReleased.timeout(const Duration(seconds: 12));

    step = 'open-saved-history';
    final (next, nextPage) = await openPage();
    report['newPage'] = !identical(nextPage, page);
    report['reopenedRoute'] = await _observeFreshPlayback(next);
    if (identical(nextPage, page)) throw StateError('page was not replaced');

    step = 'release';
    final released = await next.shutdownPlaybackFacade();
    report['shutdown'] = released.outcome.name;
    if (released.outcome != PlaybackShutdownOutcome.released) {
      throw StateError('playback was not released');
    }
    await closePlatformAudioSession();
    await CacheManager.close();
    Request.close();
    await GStorage.close();
    report['passed'] = true;
  } catch (error, stack) {
    report['failedStep'] = step;
    report['errorType'] = error.runtimeType.toString();
    report['stack'] = stack.toString().split('\n').take(8).toList();
    if (PlPlayerController.instance case final player?) {
      final snapshot = player.currentPlaybackSnapshot;
      report['lastPlayback'] = {
        'phase': snapshot.phase.name,
        'stage': snapshot.stage.name,
        'load': snapshot.loadId,
        'positionMs': player.positionInMilliseconds,
        'playing': snapshot.actual.playing,
        'framePresented': player.videoFramePresented.value,
        'failure': snapshot.failure?.operation,
      };
    }
  }
  report['deniedHttpRequests'] = deniedHttpRequests;
  await File('${root.path}/page-replay.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  debugPrint('ANDROID_PAGE_REPLAY_DONE ${report['passed']}');
  exit(report['passed'] == true ? 0 : 1);
}

Future<Map<String, Object?>> _observeFreshPlayback(PlPlayerController player) =>
    _waitFor(() {
      final snapshot = player.currentPlaybackSnapshot;
      final position = player.positionInMilliseconds;
      if (snapshot.phase != PlaybackPhase.ready ||
          !player.videoFramePresented.value ||
          position <= 0 ||
          position >= 3000) {
        return null;
      }
      final native = player.videoPlayerController;
      return {
        'positionMs': position,
        'playing': snapshot.actual.playing,
        'load': snapshot.loadId,
        'framePresented': true,
        'decoder': native is NativePlayer
            ? native.getProperty('hwdec-current')
            : null,
      };
    });

Future<T> _waitFor<T extends Object>(T? Function() observe) async {
  final watch = Stopwatch()..start();
  do {
    if (observe() case final value?) return value;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  } while (watch.elapsed < const Duration(seconds: 12));
  throw TimeoutException('等待 Android 页面状态超时');
}
