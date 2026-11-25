import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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
  const focusRecovery = bool.fromEnvironment('PAGE_RECOVER_AUDIO_FOCUS');
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
  const reportName = focusRecovery ? 'page-audio-focus' : 'page-replay';
  final report = <String, Object?>{'passed': false};
  final focusEvents = <Map<String, Object?>>[];
  StreamSubscription<AudioInterruptionEvent>? focusSubscription;
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
      if (focusRecovery) SettingBoxKey.continuePlayInBackground: true,
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

    BiliDownloadEntryInfo entryFor(int mediaCid) =>
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
              cid: mediaCid,
              page: 1,
              hasAlias: false,
              tid: 0,
              width: 960,
              height: 540,
            ),
          )
          ..entryDirPath = root.path
          ..pageDirPath = fixture.parent.path;
    Future<(PlPlayerController, VideoDetailController)> openPage(int mediaCid) {
      final entry = entryFor(mediaCid);
      unawaited(
        Get.toNamed<void>(
          videoRoute.name,
          preventDuplicates: false,
          arguments: {
            'aid': entry.avid,
            'bvid': entry.bvid,
            'cid': mediaCid,
            'heroTag': 'android-page-replay-$mediaCid',
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
        final page = mountedVideoPage(player, cid: mediaCid);
        if (player == null ||
            page == null ||
            !page.playbackOwner.hasLoadedMedia) {
          return null;
        }
        return (player, page);
      });
    }

    final PlPlayerController next;
    if (focusRecovery) {
      step = 'focus-first-page';
      final (player, _) = await openPage(cid);
      report['firstOpen'] = await _observeFreshPlayback(player);
      final audioSession = await AudioSession.instance;
      focusSubscription = audioSession.interruptionEventStream.listen((event) {
        focusEvents.add({'type': event.type.name, 'begin': event.begin});
      });
      await player.play();

      step = 'expect-system-interruption';
      final inject = File('${root.path}/$reportName.inject').existsSync();
      report['trigger'] = inject ? 'injected-platform-callback' : 'system';
      if (inject) {
        if (!await audioSession.setActive(false)) {
          throw StateError('cannot abandon native focus before injecting loss');
        }
        ui.channelBuffers.push(
          'com.ryanheise.android_audio_manager',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onAudioFocusChanged', [-1]),
          ),
          (_) {},
        );
      } else {
        await File('${root.path}/$reportName.ready').writeAsString(
          'request competing AUDIOFOCUS_GAIN',
          flush: true,
        );
      }
      await _waitFor(
        () =>
            focusEvents.any(
                  (event) =>
                      event['type'] == 'unknown' && event['begin'] == true,
                ) &&
                _focusInhibited(player) &&
                player.currentPlaybackSnapshot.actual.playing == false &&
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed
            ? true
            : null,
      );
      report['pausedAfterLoss'] = true;
      final previousLoad = player.currentPlaybackSnapshot.loadId;

      step = 'switch-while-focus-lost';
      (next, _) = await openPage(2);
      await _waitFor(() {
        final snapshot = next.currentPlaybackSnapshot;
        return snapshot.phase == PlaybackPhase.ready &&
                snapshot.loadId != previousLoad &&
                snapshot.intent.playing &&
                snapshot.actual.playing == false &&
                _focusInhibited(next)
            ? true
            : null;
      });
      if (!identical(player, next)) {
        throw StateError('switch did not reuse the same playback facade');
      }
      report['pausedAfterSwitch'] = true;

      step = 'explicit-focus-reacquisition';
      await next.play();
      report['afterReacquisition'] = await _observeFreshPlayback(next);
      if (_focusInhibited(next)) throw StateError('focus inhibitor remained');
    } else {
      step = 'open-completed-history';
      await GStorage.watchProgress.put(positionKey, lengthMs);
      final (player, page) = await openPage(cid);
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
      if (saved != lengthMs) {
        throw StateError('completed history was not saved');
      }
      await player.playbackReleased.timeout(const Duration(seconds: 12));

      step = 'open-saved-history';
      final (reopenedPlayer, nextPage) = await openPage(cid);
      next = reopenedPlayer;
      report['newPage'] = !identical(nextPage, page);
      report['reopenedRoute'] = await _observeFreshPlayback(next);
      if (identical(nextPage, page)) throw StateError('page was not replaced');
    }

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
        'playIntent': snapshot.intent.playing,
        'inhibitors': snapshot.inhibitors
            .map((token) => token.source.name)
            .toList(),
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'framePresented': player.videoFramePresented.value,
        'failure': snapshot.failure?.operation,
      };
    }
  }
  await focusSubscription?.cancel();
  if (focusRecovery) report['focusEvents'] = focusEvents;
  report['deniedHttpRequests'] = deniedHttpRequests;
  await File('${root.path}/$reportName.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  debugPrint('ANDROID_PAGE_REPLAY_DONE ${report['passed']}');
  exit(report['passed'] == true ? 0 : 1);
}

bool _focusInhibited(PlPlayerController player) =>
    player.currentPlaybackSnapshot.inhibitors.any(
      (token) => token.source == PlaybackInhibitorSource.audioFocus,
    );

Future<Map<String, Object?>> _observeFreshPlayback(PlPlayerController player) =>
    _waitFor(() {
      final snapshot = player.currentPlaybackSnapshot;
      final position = player.positionInMilliseconds;
      if (snapshot.phase != PlaybackPhase.ready ||
          snapshot.actual.playing != true ||
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
