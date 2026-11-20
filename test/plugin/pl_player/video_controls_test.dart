import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:pili_aurora_next/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/media/video_quality.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/data.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/page.dart';
import 'package:pili_aurora_next/features/playback/domain/play_info/subtitle.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/data_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/bottom_progress_behavior.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/play_status.dart';
import 'package:pili_aurora_next/plugin/pl_player/models/video_fit_type.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_controls.dart';
import 'package:pili_aurora_next/plugin/pl_player/view/video_progress.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/memory_box.dart';
import 'support/presentation_player.dart';

void main() {
  testWidgets('进度刷新不重建趋势图，展开控制栏时卸载简版进度条', (tester) async {
    GStorage.setting = MemoryBox();
    final player = _ControlPlayer()..dmChartEnabled = true;
    final page = _Page()..dmTrend.value = const Success([0.0, 1.0, 0.5]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              CompactVideoProgress(
                plPlayerController: player,
                videoDetailController: page,
                isFullScreen: false,
              ),
            ],
          ),
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    player.position.value = 120;
    player.buffered.value = 180;
    await tester.pump();
    expect(tester.widget<ProgressBar>(find.byType(ProgressBar)).progress, 120);
    expect(tester.widget<LineChart>(find.byType(LineChart)), same(chart));

    player.showControls.value = true;
    await tester.pump();
    expect(find.byType(ProgressBar, skipOffstage: false), findsNothing);
    expect(find.byType(LineChart, skipOffstage: false), findsNothing);
    player.dmChartEnabled = false;
    player.showControls.value = false;
    await tester.pump();
    expect(find.byType(ProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制条保留上下集、倍速和两种全屏入口', (tester) async {
    final player = _ControlPlayer();
    final intro = _Intro();
    final page = _Page();
    await tester.pumpWidget(_app(player, intro, page));
    await tester.tap(find.byTooltip('上一集'));
    await tester.tap(find.byTooltip('下一集'));
    expect((intro.previous, intro.next), (1, 1));
    await tester.tap(find.byTooltip('倍速'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0X'));
    await tester.pumpAndSettle();
    expect(player.playbackSpeed, 2);
    await tester.tap(find.byTooltip('全屏'));
    await tester.tap(find.byTooltip('全屏'), buttons: kSecondaryMouseButton);
    expect(player.fullScreenCommands, [(true, false), (true, true)]);
    await tester.pumpWidget(const SizedBox());
    expect(player.statusListeners, isEmpty);
  });

  testWidgets('分P选集回调保留集列表和当前媒体身份', (tester) async {
    final player = _ControlPlayer()..isFileSource = false;
    final intro = _Intro();
    final parts = [Part(cid: 11, part: '一'), Part(cid: 22, part: '二')];
    intro.videoDetail.value = VideoDetailData(pages: parts);
    final page = _Page()..isFileSource = false;
    List<Object?>? selected;
    await tester.pumpWidget(
      _app(
        player,
        intro,
        page,
        showEpisodes: ([index, season, episodes, bvid, aid, cid]) {
          selected = [index, season, episodes, bvid, aid, cid];
        },
      ),
    );
    await tester.tap(find.byTooltip('选集'));
    expect(selected, [null, null, same(parts), player.bvid, 170001, 22]);
  });
}

Widget _app(
  _ControlPlayer player,
  _Intro intro,
  _Page page, {
  ShowPlayerEpisodes? showEpisodes,
}) => MaterialApp(
  home: Scaffold(
    body: VideoControls(
      plPlayerController: player,
      videoDetailController: page,
      introController: intro,
      maxWidth: 800,
      isLandscape: true,
      isFullScreen: false,
      showEpisodes: showEpisodes,
    ),
  ),
);

class _ControlPlayer extends PresentationPlayer {
  @override
  RxBool get muted => _muted;
  final _muted = false.obs;
  @override
  PlayerStatus get playerStatus => PlayerStatus.paused;
  @override
  Rx<DataStatus> get dataStatus => _dataStatus;
  final _dataStatus = Rx(DataStatus.none);
  bool dmChartEnabled = false;
  @override
  bool get showDmChart => dmChartEnabled;
  @override
  bool get enableBlock => false;
  final _buffered = 0.obs;
  @override
  RxInt get buffered => _buffered;
  @override
  int get progress => position.value;
  @override
  BtmProgressBehavior get progressType => .alwaysShow;
  @override
  bool get showViewPoints => false;
  @override
  bool get isDesktopPip => false;
  @override
  bool get isAnim => false;
  @override
  Rx<VideoFitType> get videoFit => _videoFit;
  final _videoFit = VideoFitType.contain.obs;
  @override
  List<double> get speedList => [1, 2];
  final speed = 1.0.obs;
  @override
  double get playbackSpeed => speed.value;
  @override
  String get bvid => 'BV17x411w7KC';
  @override
  int? get cid => 22;
  final statusListeners = <ValueChanged<PlayerStatus>>{};
  @override
  void addStatusLister(ValueChanged<PlayerStatus> listener) =>
      statusListeners.add(listener);
  @override
  void removeStatusLister(ValueChanged<PlayerStatus> listener) =>
      statusListeners.remove(listener);
  @override
  Future<void> setPlaybackSpeed(double value) async => speed.value = value;
}

class _Intro implements CommonIntroController {
  @override
  final videoDetail = ValueNotifier(VideoDetailData());
  int previous = 0;
  int next = 0;
  @override
  bool prevPlay() {
    previous++;
    return true;
  }

  @override
  bool nextPlay() {
    next++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected intro dependency: ${invocation.memberName}');
}

class _Page implements VideoDetailController {
  @override
  final dmTrend = ValueNotifier<LoadingState<List<double>>?>(null);
  @override
  final showDmTrendChart = ValueNotifier(true);
  @override
  final showVP = ValueNotifier(true);
  @override
  final viewPoints = ValueNotifier<List<ViewPointSegment>>(const []);
  @override
  List<ViewPointSegment> get viewPointList => viewPoints.value;
  @override
  bool isUgc = true;
  @override
  bool isPlayAll = false;
  @override
  bool isFileSource = true;
  @override
  final subtitleTracks = ValueNotifier<List<Subtitle>>(const []);
  @override
  List<Subtitle> get subtitles => subtitleTracks.value;
  @override
  final vttSubtitlesIndex = ValueNotifier(-1);
  @override
  final languages = ValueNotifier<List<LanguageItem>?>(null);
  @override
  final currLang = ValueNotifier<String?>(null);
  @override
  final currentVideoQa = ValueNotifier<VideoQuality?>(null);
  @override
  final availableVideoQualities = ValueNotifier<Set<int>>(const {});
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected page dependency: ${invocation.memberName}');
}
