import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/playback/application/video_playlist.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/common/widgets/route_aware_mixin.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/audio_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/features/playback/domain/play_info/subtitle.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/local/view.dart';
import 'package:pili_aurora_next/pages/video/view.dart';
import 'package:pili_aurora_next/plugin/pl_player/playback/playback_contracts.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/theme_utils.dart';

import '../../services/download/download_fixtures.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _PlaybackAdapter adapter;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'pili-playback-lifecycle-',
    );
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    GStorage.watchProgress = MemoryBox<int>();
    await GStorage.setting.put(SettingBoxKey.autoPlayEnable, true);
    await GStorage.localCache.put(
      LocalCacheKey.timeStamp,
      DateTime.now().millisecondsSinceEpoch,
    );
    await GStorage.localCache.put(LocalCacheKey.mixinKey, 'synthetic-test-key');
    Request();
    Request.dio.interceptors.clear();
    adapter = _PlaybackAdapter();
    Request.dio.httpClientAdapter = adapter;
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await directory.delete(recursive: true);
  });

  _VideoController page() => _VideoController()
    ..args = <String, Object>{}
    ..bvid = 'BV-test'
    ..aid = 1
    ..cid.value = 1
    ..videoType = VideoType.ugc
    ..isFileSource = false
    ..isVertical.value = false;

  testWidgets('同一转场标识的点播路由独立持有播放与窗口交接', (tester) async {
    await GStorage.setting.put(SettingBoxKey.autoPlayEnable, false);
    await GStorage.watchProgress.putAll({'11': 12000, '12': 59800});
    ThemeUtils.getAllTheme();
    addTearDown(() async {
      Get.reset();
      await GStorage.setting.put(SettingBoxKey.autoPlayEnable, true);
    });
    await tester.pumpWidget(
      ProviderScope(
        child: GetMaterialApp(
          navigatorObservers: [routeObserver],
          home: const Scaffold(),
          getPages: [
            GetPage(name: '/videoV', page: () => const VideoDetailPageV()),
          ],
        ),
      ),
    );
    Future<VideoDetailController> open(int cid) async {
      final entry = downloadEntry(cid: cid, completed: true)
        ..entryDirPath = directory.path;
      unawaited(
        Get.toNamed<void>(
          '/videoV',
          preventDuplicates: false,
          arguments: {
            'heroTag': 'same-hero',
            'videoType': VideoType.ugc,
            'sourceType': SourceType.file,
            'entry': entry,
            'aid': entry.avid,
            'cid': cid,
            'bvid': entry.bvid,
            'title': '离线视频 $cid',
          },
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      return tester
          .widget<LocalIntroPanel>(find.byType(LocalIntroPanel))
          .controller
          .videoDetailCtr;
    }

    final first = await open(11);
    final second = await open(12);
    expect(second, isNot(same(first)));
    expect(first.cid.value, 11);
    expect(second.cid.value, 12);
    expect(first.defaultST, const Duration(seconds: 12));
    expect(second.defaultST, Duration.zero);
    expect(second.playbackOwner.isActive, isTrue);
    int? windowCid() =>
        (first.plPlayerController.desktopPlaybackRequest?.call().arguments
            as Map?)?['cid'];
    expect(windowCid(), 12);

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(second.isClosed, isTrue);
    expect(first.playbackOwner.isActive, isTrue);
    expect(windowCid(), 11);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(first.isClosed, isTrue);
    expect(windowCid(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('点播与直播弹幕开关分别保存，临时设置不落盘', () async {
    final controller = page();
    final player = controller.plPlayerController;
    final video = player.enableShowDanmaku.value;
    final live = player.enableShowLiveDanmaku.value;
    try {
      await player.toggleDanmakuVisibility(live: false);
      expect(player.enableShowDanmaku.value, !video);
      expect(player.enableShowLiveDanmaku.value, live);
      expect(GStorage.setting.get(SettingBoxKey.enableShowDanmaku), !video);

      await player.toggleDanmakuVisibility(live: true);
      expect(player.enableShowLiveDanmaku.value, !live);
      expect(GStorage.setting.get(SettingBoxKey.enableShowLiveDanmaku), !live);

      await GStorage.setting.put(SettingBoxKey.tempPlayerConf, true);
      await player.toggleDanmakuVisibility(live: true);
      expect(player.enableShowLiveDanmaku.value, live);
      expect(GStorage.setting.get(SettingBoxKey.enableShowLiveDanmaku), !live);
    } finally {
      player.enableShowDanmaku.value = video;
      player.enableShowLiveDanmaku.value = live;
      await GStorage.setting.delete(SettingBoxKey.enableShowDanmaku);
      await GStorage.setting.delete(SettingBoxKey.enableShowLiveDanmaku);
      await GStorage.setting.delete(SettingBoxKey.tempPlayerConf);
      controller.closePlayback();
    }
  });

  test('切序与换号使在途分页失效，同向分页不重复请求', () async {
    LoginAccount account(String csrf) => LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '42', 'bili_jct': csrf}),
      null,
      null,
    );
    final previous = Accounts.main;
    final original = account('original');
    Accounts.accountMode[AccountType.main.index] = original;
    addTearDown(() => Accounts.accountMode[AccountType.main.index] = previous);
    final playlist = VideoPlaylist(
      source: SourceType.watchLater,
      id: 1,
      type: 2,
      descending: false,
      continueFromAnchor: true,
      anchor: 99,
    );
    addTearDown(playlist.close);
    Map<String, Object?> items(List<int> ids) => {
      'media_list': [
        for (final id in ids)
          {
            'id': id,
            'type': 2,
            'pages': [
              {'id': id},
            ],
          },
      ],
    };
    final initial = playlist.load();
    final first = await adapter.next();
    expect(first.options.queryParameters['oid'], 99);
    expect(first.options.queryParameters['with_current'], isTrue);
    expect(first.options.extra['account'], same(original));
    first.complete(items([99, 100]));
    await initial;

    final append = playlist.load();
    final old = await adapter.next();
    expect(old.options.queryParameters['oid'], 100);
    expect(await playlist.load(), isNull);
    final reverse = playlist.load(reverse: true);
    final newest = await adapter.next();
    expect(newest.options.queryParameters['desc'], isTrue);
    expect(newest.options.queryParameters['oid'], isNull);
    expect(newest.options.queryParameters['with_current'], isFalse);
    newest.complete(items([105, 104]));
    expect((await reverse)?.dataOrNull?.aid, 105);

    old.complete(items([101, 102]));
    expect(await append, isNull);
    expect(playlist.items.value.map((item) => item.aid), [105, 104]);

    final tail = playlist.load();
    (await adapter.next()).complete(items([104, 103]));
    await tail;
    expect(playlist.items.value.map((item) => item.aid), [105, 104, 103]);
    final pending = playlist.load();
    final inFlight = await adapter.next();
    Accounts.replaceCredentials(account('replacement'));
    inFlight.complete(items([102]));
    expect(await pending, isNull);
    expect(playlist.items.value, isEmpty);
  });

  test('快速切集执行新请求，旧响应不能初始化新集', () async {
    final controller = page();
    final old = controller.queryVideoUrl();
    final first = await adapter.next();
    expect(first.options.queryParameters['cid'], 1);
    controller.cid.value = 2;
    final current = controller.queryVideoUrl();
    final second = await adapter.next();
    expect(second.options.queryParameters['cid'], 2);
    second.complete(media(2));
    await current;
    expect(first.cancelled, isTrue);
    first.complete(media(1));
    await old;
    expect(controller.loads.map((e) => e.cid), [2]);
    expect(controller.videoUrl, contains('/2'));
    controller.closePlayback();
  });

  for (final preload in [false, true]) {
    test('关闭自动播放且预加载为 $preload 时按设置加载并保留暂停意图', () async {
      await GStorage.setting.put(SettingBoxKey.preInitPlayer, preload);
      final controller = page()..autoPlay = false;
      final query = controller.queryVideoUrl();
      (await adapter.next()).complete(media(1));
      await query;
      expect(controller.videoUrl, contains('/1'));
      expect(controller.loads.length, preload ? 1 : 0);
      if (preload) expect(controller.loads.single.autoplay, isFalse);
      expect(controller.plPlayerController.preInitPlayer, preload);
      controller.closePlayback();
      await GStorage.setting.put(SettingBoxKey.preInitPlayer, false);
    });
  }

  test('媒体计划读取新的同步设置和缓冲偏好，已捕获计划保持稳定', () async {
    final controller = page();
    final first = controller.plPlayerController.capturePlaybackConfiguration(
      live: false,
    );
    await GStorage.setting.putAll({
      SettingBoxKey.videoSync: 'audio',
      SettingBoxKey.autosync: '30',
      SettingBoxKey.bufferSec: 24.0,
      SettingBoxKey.bufferSize: 8.0,
    });
    final next = controller.plPlayerController.capturePlaybackConfiguration(
      live: false,
    );
    expect(next.mediaOptions['video-sync'], 'audio');
    expect(next.mediaOptions['autosync'], '30');
    expect(next.mediaOptions['cache-secs'], '24.000');
    expect(next.mediaOptions['demuxer-max-bytes'], '${32 * 1024 * 1024}');
    expect(first.mediaOptions['video-sync'], 'display-resample');
    controller.closePlayback();
    for (final key in [
      SettingBoxKey.videoSync,
      SettingBoxKey.autosync,
      SettingBoxKey.bufferSec,
      SettingBoxKey.bufferSize,
    ]) {
      await GStorage.setting.delete(key);
    }
  });

  test('缓存策略只影响下一次点播配置，直播保留独立预算', () async {
    final controller = page();
    final player = controller.plPlayerController;
    final first = player.capturePlaybackConfiguration(live: false);
    final live = player.capturePlaybackConfiguration(live: true);
    await GStorage.setting.put(SettingBoxKey.videoBufferPolicy, 'smooth');
    final next = player.capturePlaybackConfiguration(live: false);
    expect(first.mediaOptions['demuxer-max-bytes'], '${16 * 1024 * 1024}');
    expect(next.mediaOptions['demuxer-max-bytes'], '${32 * 1024 * 1024}');
    expect(next.mediaOptions['demuxer-max-back-bytes'], '${4 * 1024 * 1024}');
    expect(
      player.capturePlaybackConfiguration(live: true).mediaOptions,
      live.mediaOptions,
    );
    expect(live.mediaOptions['demuxer-max-bytes'], '${8 * 1024 * 1024}');
    expect(live.mediaOptions['demuxer-max-back-bytes'], '0');
    controller.closePlayback();
    await GStorage.setting.delete(SettingBoxKey.videoBufferPolicy);
  });

  test('首包满足起播画质，补档不阻塞且只更新菜单', () async {
    final controller = page();
    final query = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1, supplement: true));
    final supplement = await adapter.next();
    expect(controller.loads.map((entry) => entry.cid), [1]);
    await query;
    final sourceData = controller.data;
    final updated = Completer<Set<int>>();
    final qualities = controller.availableVideoQualities;
    void onQualityChanged() {
      if (!qualities.value.contains(64)) return;
      qualities.removeListener(onQualityChanged);
      updated.complete(qualities.value);
    }

    qualities.addListener(onQualityChanged);
    supplement.complete(media(1, quality: 64));
    expect(await updated.future.timeout(const Duration(seconds: 2)), {80, 64});
    expect(controller.data, same(sourceData));
    expect(sourceData.dash!.video!.availableVideoQualities, {80, 64});
    expect(controller.currentVideoQa.value?.code, 80);
    expect(controller.loads, hasLength(1));
    controller.closePlayback();
  });

  test('缺少起播画质时等待补档，补档失败仍选择实际存在的轨道', () async {
    final controller = page();
    controller.plPlayerController.cacheVideoQa = 64;
    final query = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1, supplement: true));
    final supplement = await adapter.next();
    expect(controller.loads, isEmpty);
    supplement.complete({'code': -1, 'message': '补档失败'}, raw: true);
    await query;
    expect(controller.currentVideoQa.value?.code, 80);
    expect(controller.loads, hasLength(1));
    controller.closePlayback();
  });

  test('补充画质请求也绑定原媒体，迟到补充不能污染当前数据', () async {
    final controller = page();
    final old = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1, supplement: true));
    final supplement = await adapter.next();
    expect(supplement.options.queryParameters['cid'], 1);
    expect(supplement.options.queryParameters['qn'], 64);
    controller.cid.value = 2;
    final current = controller.queryVideoUrl();
    (await adapter.next()).complete(media(2));
    await current;
    supplement.complete(media(1, quality: 64));
    await old;
    expect(controller.data.dash!.video!.map((e) => e.id), [80]);
    expect(controller.loads.map((e) => e.cid), [1, 2]);
    controller.closePlayback();
  });

  test('页面关闭后的地址响应不加载，初始化入口也检查关闭状态', () async {
    final controller = page();
    final query = controller.queryVideoUrl();
    final response = await adapter.next();
    controller.closePlayback();
    response.complete(media(1));
    await query;
    expect(response.cancelled, isTrue);
    expect(controller.loads, isEmpty);
    await controller.initializeClosedPage();
  });

  test('从有音轨切到无音轨，暂停后切画质保持暂停', () async {
    final controller = page();
    final first = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1));
    await first;
    expect(controller.currentAudioQa, isNotNull);
    controller.cid.value = 2;
    final second = controller.queryVideoUrl();
    (await adapter.next()).complete(media(2, audio: false));
    await second;
    expect(controller.currentAudioQa, isNull);
    await controller.plPlayerController.pause();
    final switched = await controller.updatePlayer();
    expect(switched.outcome, LoadOutcome.ready);
    expect(controller.routeLoads.last.start, PlaybackStartPolicy.preserve);
    expect(controller.audioUrl, isEmpty);
    controller.closePlayback();
  });

  test('字幕响应迟到且列表已切集清空时，不缓存或应用旧字幕', () async {
    final controller = page()
      ..currentSubtitleTracks = [
        Subtitle(lan: 'zh-CN', subtitleUrl: '//example.com/subtitle'),
      ];
    final loading = controller.setSubtitle(1);
    final request = await adapter.next();
    controller.cid.value = 2;
    controller.currentSubtitleTracks = const [];
    request.complete({'body': []}, raw: true);
    await loading;
    expect(controller.vttSubtitles, isEmpty);
    expect(controller.vttSubtitlesIndex.value, -1);
    controller.closePlayback();
  });

  test('互动视频先返回新节点，迟到的旧节点不覆盖可选分支', () async {
    final controller = page()..graphVersion = 1;
    addTearDown(controller.closePlayback);

    final old = controller.getSteinEdgeInfo(1);
    final oldRequest = await adapter.next();
    final current = controller.getSteinEdgeInfo(2);
    final currentRequest = await adapter.next();
    Map<String, Object?> branch(int edge) => {
      'edges': {
        'questions': [
          {
            'choices': [
              {'id': edge, 'cid': edge, 'option': '分支 $edge'},
            ],
          },
        ],
      },
    };
    currentRequest.complete(branch(2));
    await current;
    oldRequest.complete(branch(1));
    await old;

    expect(
      controller.steinEdgeInfo?.edges?.questions?.single.choices?.single.id,
      2,
    );
  });

  test('本地文件暂停且关闭预加载时，手动重试仍执行页面加载', () async {
    final controller = page()
      ..isFileSource = true
      ..autoPlay = false;
    await controller.retryPlayback();
    expect(controller.loads, hasLength(1));
    expect(controller.loads.single.autoplay, isFalse);
    controller.closePlayback();
  });

  test('手动重试重新查询地址，并保留暂停和续播位置', () async {
    final controller = page();
    final initial = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1));
    await initial;
    await controller.plPlayerController.pause();
    controller.playedTime = const Duration(seconds: 27);
    final reset = controller.retryPlayback();
    final request = await adapter.next();
    expect(request.options.queryParameters['cid'], 1);
    request.complete(media(2));
    await reset;
    expect(controller.loads.length, 2);
    expect(controller.loads.last.autoplay, isFalse);
    expect(controller.loads.last.source, 'https://example.com/video/2');
    expect(controller.plans.last.reloadPosition, const Duration(seconds: 27));
    controller.closePlayback();
  });

  test('查询被新页面取代时，返回会用保留意图重新解析', () async {
    final controller = page()..playedTime = const Duration(seconds: 27);
    final holdForRoute = controller.holdPlaybackForRoute;
    final restoreAfterRoute = controller.restorePlaybackAfterRoute;
    holdForRoute();
    final restore = restoreAfterRoute();
    final request = await adapter.next();
    request.complete(media(1));
    await restore;

    expect(controller.loads, hasLength(1));
    expect(controller.loads.single.autoplay, isFalse);
    controller.closePlayback();
  });

  test('返回已有媒体时重新提交页面计划并保留上次进度', () async {
    final controller = page();
    final initial = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1));
    await initial;
    controller
      ..playedTime = const Duration(seconds: 27)
      ..holdPlaybackForRoute();
    await controller.restorePlaybackAfterRoute();

    expect(controller.routeLoads, hasLength(1));
    expect(controller.routeLoads.single.start, PlaybackStartPolicy.preserve);
    expect(controller.routeLoads.single.plan.contentKey, 'ugc:BV-test:1');
    expect(
      controller.routeLoads.single.plan.reloadPosition,
      const Duration(seconds: 27),
    );
    controller.closePlayback();
  });

  test('字幕加载期间选择关闭，以最新选择为准', () async {
    final controller = page()
      ..currentSubtitleTracks = [
        Subtitle(lan: 'zh-CN', subtitleUrl: '//example.com/subtitle'),
      ];
    final loading = controller.setSubtitle(1);
    final request = await adapter.next();
    await controller.setSubtitle(0);
    request.complete({'body': []}, raw: true);
    await loading;
    expect(controller.vttSubtitlesIndex.value, 0);
    expect(controller.vttSubtitles, isEmpty);
    controller.closePlayback();
  });

  Future<_VideoController> selectionPage() async {
    final controller = page();
    final initial = controller.queryVideoUrl();
    (await adapter.next()).complete(media(1));
    await initial;
    controller.data.dash!.video!.add(
      PlayUrlModel.fromJson(media(2, quality: 64)).dash!.video!.single,
    );
    return controller;
  }

  test('切换来源等待 ready 后确认画质和缓存，保留暂停与续播位置', () async {
    final controller = await selectionPage();
    await controller.plPlayerController.pause();
    controller.playedTime = const Duration(seconds: 27);
    final completion = Completer<LoadResult>();
    controller.sourceLoad = (_) => completion.future;
    final switching = controller.updatePlayer(
      videoQuality: VideoQuality.high720,
    );
    expect(controller.currentVideoQa.value, VideoQuality.high1080);
    expect(controller.plPlayerController.cacheVideoQa, 80);
    expect(controller.videoUrl, 'https://example.com/video/1');
    expect(controller.routeLoads.last.start, PlaybackStartPolicy.preserve);
    expect(
      controller.routeLoads.last.plan.reloadPosition,
      const Duration(seconds: 27),
    );
    completion.complete(const LoadResult.ready(2));
    expect((await switching).outcome, LoadOutcome.ready);
    expect(controller.currentVideoQa.value, VideoQuality.high720);
    expect(controller.plPlayerController.cacheVideoQa, 64);
    expect(controller.videoUrl, 'https://example.com/video/2');
    controller.closePlayback();
  });

  test('同媒体较早切换成功回执不能覆盖较新选择', () async {
    final controller = await selectionPage();
    final completion = Completer<LoadResult>();
    controller.sourceLoad = (_) => completion.future;
    final first = controller.updatePlayer(videoQuality: VideoQuality.high720);
    controller.sourceLoad = null;
    final latest = await controller.updatePlayer(
      videoQuality: VideoQuality.high1080,
    );
    expect(latest.outcome, LoadOutcome.ready);
    completion.complete(const LoadResult.ready(2));
    expect((await first).outcome, LoadOutcome.superseded);
    expect(controller.currentVideoQa.value, VideoQuality.high1080);
    expect(controller.plPlayerController.cacheVideoQa, 80);
    controller.closePlayback();
  });

  test('画质切换中再选音质，最新加载保留两项用户目标', () async {
    final controller = await selectionPage();
    controller.data.dash!.audio!.add(
      AudioItem.fromJson({
        'id': 30216,
        'base_url': 'https://example.com/audio/64',
      }),
    );
    final completion = Completer<LoadResult>();
    controller.sourceLoad = (_) => completion.future;
    final first = controller.updatePlayer(videoQuality: VideoQuality.high720);
    controller.sourceLoad = null;
    final latest = await controller.updatePlayer(
      audioQuality: AudioQuality.k64,
    );
    expect(latest.outcome, LoadOutcome.ready);
    completion.complete(const LoadResult.ready(2));
    expect((await first).outcome, LoadOutcome.superseded);
    expect(controller.currentVideoQa.value, VideoQuality.high720);
    expect(controller.currentAudioQa, AudioQuality.k64);
    expect(controller.plPlayerController.cacheVideoQa, 64);
    expect(controller.plPlayerController.cacheAudioQa, 30216);
    controller.closePlayback();
  });

  test('换分 P 后迟到加载不能确认旧来源', () async {
    final controller = await selectionPage();
    final completion = Completer<LoadResult>();
    controller.sourceLoad = (_) => completion.future;
    final switching = controller.updatePlayer(
      videoQuality: VideoQuality.high720,
    );
    controller.cid.value = 2;
    completion.complete(const LoadResult.ready(2));
    expect((await switching).outcome, LoadOutcome.superseded);
    expect(controller.currentVideoQa.value, VideoQuality.high1080);
    expect(controller.plPlayerController.cacheVideoQa, 80);
    controller.closePlayback();
  });

  test('切换播放账号后迟到加载不能确认旧偏好', () async {
    final controller = await selectionPage();
    expect(controller.playbackSourceMatchesSelection, isTrue);
    final previous = Accounts.video;
    final completion = Completer<LoadResult>();
    controller.sourceLoad = (_) => completion.future;
    final switching = controller.updatePlayer(
      videoQuality: VideoQuality.high720,
    );
    Accounts.accountMode[AccountType.video.index] = const NoAccount();
    try {
      completion.complete(const LoadResult.ready(2));
      expect((await switching).outcome, LoadOutcome.superseded);
      expect(controller.currentVideoQa.value, VideoQuality.high1080);
      expect(controller.plPlayerController.cacheVideoQa, 80);
      expect(controller.playbackSourceMatchesSelection, isFalse);
      controller.sourceLoad = null;
      final restored = await controller.updatePlayer(
        videoQuality: VideoQuality.high1080,
      );
      expect(restored.outcome, LoadOutcome.ready);
      expect(
        controller.routeLoads.last.plan.source.currentVideoSource,
        'https://example.com/video/1',
      );
      expect(controller.playbackSourceMatchesSelection, isTrue);
    } finally {
      Accounts.accountMode[AccountType.video.index] = previous;
      controller.closePlayback();
    }
  });

  test('加载中离页持有已确认来源，返回时不恢复未确认画质', () async {
    final controller = await selectionPage();
    final completion = Completer<LoadResult>();
    controller.sourceLoad = (_) => completion.future;
    final switching = controller.updatePlayer(
      videoQuality: VideoQuality.high720,
    );
    controller.holdPlaybackForRoute();
    completion.complete(const LoadResult.ready(2));
    expect((await switching).outcome, LoadOutcome.superseded);
    controller.sourceLoad = null;
    await controller.restorePlaybackAfterRoute();
    expect(
      controller.routeLoads.last.plan.source.currentVideoSource,
      'https://example.com/video/1',
    );
    expect(controller.currentVideoQa.value, VideoQuality.high1080);
    controller.closePlayback();
  });

  testWidgets('切换失败保留确认值并消费异常，同一画质可以重试', (tester) async {
    await tester.pumpWidget(
      MaterialApp(builder: FlutterSmartDialog.init(), home: const SizedBox()),
    );
    final controller = (await tester.runAsync(selectionPage))!;
    try {
      const failure = PlaybackFailure(
        category: PlaybackFailureCategory.network,
        operation: 'open',
        stage: PlaybackStage.opening,
        recoverable: true,
        cause: 'fixture',
      );
      controller.sourceLoad = (_) async => const LoadResult.failed(failure);
      final rejected = await tester.runAsync(
        () => controller.updatePlayer(videoQuality: VideoQuality.high720),
      );
      expect(rejected!.outcome, LoadOutcome.failed);
      expect(rejected.failure, same(failure));
      expect(controller.currentVideoQa.value, VideoQuality.high1080);
      controller.sourceLoad = (_) async => throw StateError('private-url');
      final failed = await tester.runAsync(
        () => controller.updatePlayer(videoQuality: VideoQuality.high720),
      );
      expect(failed!.outcome, LoadOutcome.failed);
      expect(controller.currentVideoQa.value, VideoQuality.high1080);
      expect(controller.plPlayerController.cacheVideoQa, 80);
      expect(controller.videoUrl, 'https://example.com/video/1');
      await tester.pump();
      expect(find.text('播放源切换失败，请重试'), findsOneWidget);
      expect(find.textContaining('private-url'), findsNothing);
      controller.sourceLoad = null;
      final audioOnly = await tester.runAsync(
        () => controller.updatePlayer(audioQuality: AudioQuality.k192),
      );
      expect(audioOnly!.outcome, LoadOutcome.ready);
      expect(controller.currentVideoQa.value, VideoQuality.high1080);
      expect(controller.plPlayerController.cacheVideoQa, 80);
      final retry = await tester.runAsync(
        () => controller.updatePlayer(videoQuality: VideoQuality.high720),
      );
      expect(retry!.outcome, LoadOutcome.ready);
      expect(controller.currentVideoQa.value, VideoQuality.high720);
    } finally {
      await tester.runAsync(() async {
        controller.closePlayback();
        await Future<void>.delayed(Duration.zero);
      });
      final dismissed = SmartDialog.dismiss(status: SmartStatus.allToast);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await dismissed;
      await tester.pumpWidget(const SizedBox());
    }
  });
}

Map<String, Object?> media(
  int cid, {
  bool audio = true,
  bool supplement = false,
  int quality = 80,
}) => {
  'quality': quality,
  'timelength': 60000,
  'accept_quality': [80, 64],
  'support_formats': [
    {
      'quality': 80,
      'codecs': ['avc1'],
    },
    if (supplement)
      {
        'quality': 64,
        'codecs': ['avc1'],
      },
  ],
  'dash': {
    'video': [
      {
        'id': quality,
        'base_url': 'https://example.com/video/$cid',
        'codecs': 'avc1',
        'width': 1920,
        'height': 1080,
      },
    ],
    if (audio)
      'audio': [
        {'id': 30280, 'base_url': 'https://example.com/audio/$cid'},
      ],
  },
};

class _VideoController extends VideoDetailController {
  _VideoController() {
    playbackOwner = plPlayerController.attachPlaybackOwner();
    plPlayerController.cacheVideoQa = 80;
  }
  bool closed = false;
  List<Subtitle>? currentSubtitleTracks;
  @override
  List<Subtitle> get subtitles => currentSubtitleTracks ?? super.subtitles;
  int _queryGeneration = 0;
  int _routeLoadGeneration = 0;
  void Function()? _cancelQuery;
  final loads = <({int cid, String? source, bool autoplay})>[];
  final plans = <PlaybackPlan>[];
  final routeLoads = <({PlaybackPlan plan, PlaybackStartPolicy start})>[];
  Future<LoadResult> Function(PlaybackPlan plan)? sourceLoad;
  @override
  bool get isClosed => closed;
  @override
  Future<LoadResult> submitPlaybackQuery(
    Future<PlaybackPlan?> Function(PlaybackQuery) resolve, {
    required PlaybackStartPolicy start,
    bool Function()? shouldLoad,
  }) async {
    _cancelQuery?.call();
    _cancelQuery = null;
    final generation = ++_queryGeneration;
    bool isCurrent() => generation == _queryGeneration && !closed;
    final query = PlaybackQuery(
      requestId: generation,
      isCurrent: isCurrent,
      registerCancel: (cancel) {
        if (isCurrent()) {
          _cancelQuery = cancel;
        } else {
          cancel();
        }
      },
    );
    final plan = await resolve(query);
    if (!isCurrent()) return const LoadResult.superseded();
    if (plan == null) return const LoadResult.noMedia();
    if (shouldLoad?.call() == false) return const LoadResult.noMedia();
    plans.add(plan);
    loads.add((
      cid: cid.value,
      source: plan.source.currentVideoSource,
      autoplay: switch (start) {
        PlaybackStartPolicy.play => true,
        PlaybackStartPolicy.pause => false,
        PlaybackStartPolicy.preserve => plPlayerController.wantsToPlay,
      },
    ));
    return LoadResult.ready(generation);
  }

  @override
  Future<void> playerInit({
    bool? autoplay,
    bool autoFullScreenFlag = false,
  }) async {
    loads.add((
      cid: cid.value,
      source: videoUrl,
      autoplay: autoplay ?? plPlayerController.wantsToPlay,
    ));
  }

  @override
  Future<LoadResult> loadPlaybackPlanForRoute(
    PlaybackPlan plan, {
    required PlaybackStartPolicy start,
    required void Function() onReady,
  }) async {
    routeLoads.add((plan: plan, start: start));
    plPlayerController.preparePlaybackPlan(
      owner: playbackOwner,
      plan: plan,
      live: false,
    );
    if (sourceLoad case final load?) return load(plan);
    return LoadResult.ready(++_routeLoadGeneration);
  }

  @override
  Future<CommandResult> applyPlaybackSubtitleTrack(
    PlaybackSubtitleTrack? track,
  ) async => const CommandResult.applied();

  @override
  void afterPlaybackReady(bool Function() valid) {}

  Future<void> initializeClosedPage() => super.playerInit();
  void closePlayback() {
    closed = true;
    _cancelQuery?.call();
    playbackOwner.close();
  }
}

class _PendingPlayback {
  _PendingPlayback(this.options);
  final RequestOptions options;
  final response = Completer<ResponseBody>();
  bool cancelled = false;
  void complete(Map<String, Object?> data, {bool raw = false}) =>
      response.complete(
        ResponseBody.fromString(
          jsonEncode(raw ? data : {'code': 0, 'data': data}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
}

class _PlaybackAdapter implements HttpClientAdapter {
  final _requests = <_PendingPlayback>[];
  Completer<void> _arrived = Completer<void>();
  Future<_PendingPlayback> next() async {
    if (_requests.isEmpty) await _arrived.future;
    final next = _requests.removeAt(0);
    if (_requests.isEmpty) _arrived = Completer<void>();
    return next;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final request = _PendingPlayback(options);
    cancelFuture?.then((_) => request.cancelled = true);
    _requests.add(request);
    if (!_arrived.isCompleted) _arrived.complete();
    return request.response.future;
  }

  @override
  void close({bool force = false}) {}
}
