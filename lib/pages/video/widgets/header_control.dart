import 'dart:async' show Timer, unawaited;
import 'dart:io' show Platform;

import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/custom_icon.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/marquee.dart';
import 'package:pili_aurora_next/features/playback/application/video_danmaku_interactions.dart';
import 'package:pili_aurora_next/features/playback/presentation/danmaku_actions.dart';
import 'package:pili_aurora_next/features/playback/presentation/danmaku_like_control.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/subtitle_format.dart';
import 'package:pili_aurora_next/features/playback/domain/media/url.dart';
import 'package:pili_aurora_next/pages/common/common_intro_controller.dart';
import 'package:pili_aurora_next/features/playback/domain/danmaku_metadata.dart';
import 'package:pili_aurora_next/pages/danmaku/interaction.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/controller.dart';
import 'package:pili_aurora_next/pages/video/introduction/ugc/widgets/action_item.dart';
import 'package:pili_aurora_next/pages/video/widgets/header_mixin.dart';
import 'package:pili_aurora_next/pages/video/widgets/more_settings_sheet.dart';
import 'package:pili_aurora_next/plugin/pl_player/controller.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/player_info_dialog.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/desktop_playback_menu.dart';
import 'package:pili_aurora_next/plugin/pl_player/widgets/desktop_window_controls.dart';
import 'package:pili_aurora_next/platform/android/bindings.g.dart';
import 'package:pili_aurora_next/common/layout/num_ext.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:pili_aurora_next/services/settings/display_preferences.dart';
import 'package:pili_aurora_next/common/widgets/dialog/export_import.dart';
import 'package:pili_aurora_next/common/feedback/clipboard_actions.dart';
import 'package:pili_aurora_next/core/async/rate_limiter.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide showBottomSheet;
import 'package:pili_aurora_next/common/widgets/app_select_field.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;

mixin TimeBatteryMixin<T extends StatefulWidget> on State<T> {
  PlPlayerController get plPlayerController;
  late final titleKey = GlobalKey();
  ContextSingleTicker? provider;
  ContextSingleTicker get effectiveProvider => provider ??= ContextSingleTicker(
    context,
    autoStart: () =>
        plPlayerController.showControls.value &&
        !plPlayerController.controlsLock.value,
  );

  bool get isPortrait;
  bool get isFullScreen;
  bool get horizontalScreen;

  Timer? _clock;
  final _currentTime = ValueNotifier('');

  static final _format = DateFormat('HH:mm');

  @override
  void dispose() {
    stopClock();
    _currentTime.dispose();
    _batteryLevel.dispose();
    super.dispose();
  }

  void startClock() {
    if (!_showCurrTime) return;
    if (_clock == null) {
      _currentTime.value = _format.format(DateTime.now());
      _clock ??= Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          stopClock();
          return;
        }
        _currentTime.value = _format.format(DateTime.now());
      });
    }
  }

  void stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  bool _showCurrTime = false;
  void showCurrTimeIfNeeded(bool isFullScreen) {
    _showCurrTime = !isPortrait && (isFullScreen || !horizontalScreen);
    if (!_showCurrTime) {
      stopClock();
    }
  }

  late final _battery = Battery();
  final _batteryLevel = ValueNotifier<int?>(null);
  late final _showBatteryLevel = DisplayPreferences.showBatteryLevel;
  void getBatteryLevelIfNeeded() {
    if (!_showCurrTime || !_showBatteryLevel) return;
    ActionThrottle.run(
      'getBatteryLevel$hashCode',
      const Duration(seconds: 30),
      () async {
        try {
          final level = await _battery.batteryLevel;
          if (mounted) _batteryLevel.value = level;
        } catch (_) {}
      },
    );
  }

  List<Widget>? get timeBatteryWidgets {
    if (_showCurrTime) {
      return [
        if (_showBatteryLevel) ...[
          ValueListenableBuilder(
            valueListenable: _batteryLevel,
            builder: (context, batteryLevel, _) {
              if (batteryLevel == null) {
                return const SizedBox.shrink();
              }
              return Text(
                '$batteryLevel%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
              );
            },
          ),
          const SizedBox(width: 10),
        ],
        ValueListenableBuilder(
          valueListenable: _currentTime,
          builder: (context, time, _) => Text(
            time,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ),
      ];
    }
    return null;
  }
}

class HeaderControl extends StatefulWidget {
  const HeaderControl({
    required this.isPortrait,
    required this.controller,
    required this.videoDetailCtr,
    required this.introController,
    super.key,
  });

  final bool isPortrait;
  final PlPlayerController controller;
  final VideoDetailController videoDetailCtr;
  final CommonIntroController introController;

  @override
  State<HeaderControl> createState() => HeaderControlState();
}

class HeaderControlState extends State<HeaderControl>
    with HeaderMixin, TimeBatteryMixin {
  @override
  late final PlPlayerController plPlayerController = widget.controller;
  late final VideoDetailController videoDetailCtr = widget.videoDetailCtr;
  late final PlayUrlModel videoInfo = videoDetailCtr.data;
  static const TextStyle titleStyle = TextStyle(fontSize: 14);

  CommonIntroController get introController => widget.introController;

  @override
  bool get isPortrait => widget.isPortrait;
  @override
  late final horizontalScreen = videoDetailCtr.horizontalScreen;

  /// 播放前后共用同一个更多面板。
  void showSettingSheet() {
    unawaited(
      showVideoMoreSettings(
        context,
        controller: videoDetailCtr,
        introController: introController,
        onSubtitleSettings: showSetSubtitle,
        onLoadSubtitle: loadLocalSubtitle,
        onSaveSubtitle: onExportSubtitle,
        onDanmakuList: showDanmakuPool,
      ),
    );
  }

  Future<void> loadLocalSubtitle() async {
    final currentMedia = videoDetailCtr.captureSubtitleMedia();
    bool isCurrent() => mounted && currentMedia();
    try {
      final result = await FilePicker.pickFile(
        type: .custom,
        allowedExtensions: const [
          'json',
          'vtt',
          'srt',
          'ass',
          'bcc',
        ],
      );
      if (result != null && isCurrent()) {
        final file = result.xFile;
        await videoDetailCtr.addLocalSubtitle(
          file.path,
          file.name,
          isCurrent: isCurrent,
        );
      }
    } catch (e) {
      if (isCurrent()) SmartDialog.showToast('加载失败: $e');
    }
  }

  static void showPlayerInfo(
    BuildContext context, {
    required NativePlayer player,
  }) {
    final dialog = PlayerInfoDialog(
      state: player.state,
      hwdec: player.getProperty('hwdec-current'),
      volume: player.getProperty('volume'),
    );
    showDialog(context: context, builder: (_) => dialog);
  }

  void onExportSubtitle() {
    final currentMedia = videoDetailCtr.captureSubtitleMedia();
    final video = videoDetailCtr.bvid;
    final part = videoDetailCtr.cid.value;
    final videoDetail = introController.videoDetail.value;
    final subtitleItems = List.of(videoDetailCtr.subtitles);
    final cachedSubtitles = Map.of(videoDetailCtr.vttSubtitles);
    showDialog(
      context: context,
      builder: (context) {
        SubtitleFormat format = .vtt;
        final subtitles = subtitleItems;
        return SimpleDialog(
          clipBehavior: .hardEdge,
          contentPadding: const .only(bottom: 12),
          titlePadding: const .fromLTRB(20, 20, 20, 12),
          title: Row(
            children: [
              const Expanded(child: Text('保存字幕')),
              const Text('格式: ', style: TextStyle(fontSize: 14)),
              AppSelectField<SubtitleFormat>(
                value: format,
                label: '格式',
                selectedLabel: format.label,
                width: 96,
                menuWidth: 190,
                options: [
                  for (final item in SubtitleFormat.values) (item, item.label),
                ],
                onSelected: (value) {
                  format = value;
                  (context as Element).markNeedsBuild();
                },
              ),
            ],
          ),
          children: List.generate(subtitles.length, (i) {
            final item = subtitles[i];
            return DialogOption(
              onPressed: () async {
                Get.back();
                final url = item.subtitleUrl;
                if (url == null || url.isEmpty) return;
                try {
                  final result = await videoDetailCtr.subtitleSources.forExport(
                    url,
                    format,
                    index: i,
                    cached: cachedSubtitles[i],
                    isCurrent: currentMedia,
                  );
                  if (result == null) return;
                  if (result case Error()) {
                    unawaited(result.toast());
                    return;
                  }
                  final name =
                      '${videoDetail.title}-${videoDetail.owner?.name}(${videoDetail.owner?.mid})-$video-$part-${item.lanDoc}.${format.name}'
                          .replaceAll(
                            Platform.isWindows ? RegExp(r'[<>:/\\|?*"]') : '/',
                            '_',
                          );
                  // Reserved characters may not be used in file names. See: https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#naming-conventions
                  await saveExport(
                    name: name,
                    bytes: result.data,
                  );
                } catch (e, s) {
                  Error.fromException(e, s);
                  SmartDialog.showToast('字幕导出失败，请稍后重试');
                }
              },
              child: Text(item.lanDoc ?? item.lan),
            );
          }),
        );
      },
    );
  }

  double get subtitleFontScale => plPlayerController.subtitleFontScale;
  double get subtitleFontScaleFS => plPlayerController.subtitleFontScaleFS;
  int get subtitlePaddingH => plPlayerController.subtitlePaddingH;
  int get subtitlePaddingB => plPlayerController.subtitlePaddingB;
  double get subtitleBgOpacity => plPlayerController.subtitleBgOpacity;
  double get subtitleStrokeWidth => plPlayerController.subtitleStrokeWidth;
  int get subtitleFontWeight => plPlayerController.subtitleFontWeight;

  /// 字幕设置
  void showSetSubtitle() {
    showBottomSheet(
      padding: () => isFullScreen ? const .only(bottom: 70) : .zero,
      (context, setState) {
        final theme = Theme.of(context);
        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;

        const EdgeInsets sliderPadding = .symmetric(vertical: 16);

        final sliderTheme = SliderThemeData(
          trackHeight: 10,
          padding: const .symmetric(horizontal: 6),
          trackShape: const MSliderTrackShape(),
          thumbColor: theme.colorScheme.primary,
          activeTrackColor: theme.colorScheme.primary,
          inactiveTrackColor: theme.colorScheme.onInverseSurface,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        );

        void updateStrokeWidth(double val) {
          plPlayerController
            ..subtitleStrokeWidth = val
            ..updateSubtitleStyle();
          setState(() {});
        }

        void updateOpacity(double val) {
          plPlayerController
            ..subtitleBgOpacity = val.toPrecision(2)
            ..updateSubtitleStyle();
          setState(() {});
        }

        void updateBottomPadding(double val) {
          plPlayerController
            ..subtitlePaddingB = val.round()
            ..updateSubtitleStyle();
          setState(() {});
        }

        void updateHorizontalPadding(double val) {
          plPlayerController
            ..subtitlePaddingH = val.round()
            ..updateSubtitleStyle();
          setState(() {});
        }

        void updateFontScaleFS(double val) {
          plPlayerController
            ..subtitleFontScaleFS = val.toPrecision(2)
            ..updateSubtitleStyle();
          setState(() {});
        }

        void updateFontScale(double val) {
          plPlayerController
            ..subtitleFontScale = val.toPrecision(2)
            ..updateSubtitleStyle();
          setState(() {});
        }

        void updateFontWeight(double val) {
          plPlayerController
            ..subtitleFontWeight = val.toInt()
            ..updateSubtitleStyle();
          setState(() {});
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Material(
            clipBehavior: Clip.hardEdge,
            color: theme.colorScheme.surface,
            borderRadius: isPortrait
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SliderTheme(
                  data: sliderTheme,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      const SizedBox(
                        height: 45,
                        child: Center(child: Text('字幕设置', style: titleStyle)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '字体大小 ${(subtitleFontScale * 100).toStringAsFixed(1)}%',
                          ),
                          resetBtn(theme, '100.0%', () => updateFontScale(1.0)),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0.5,
                          max: 2.5,
                          value: subtitleFontScale,
                          divisions: 200,
                          label:
                              '${(subtitleFontScale * 100).toStringAsFixed(1)}%',
                          onChanged: updateFontScale,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '全屏字体大小 ${(subtitleFontScaleFS * 100).toStringAsFixed(1)}%',
                          ),
                          resetBtn(
                            theme,
                            '150.0%',
                            () => updateFontScaleFS(1.5),
                          ),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0.5,
                          max: 2.5,
                          value: subtitleFontScaleFS,
                          divisions: 200,
                          label:
                              '${(subtitleFontScaleFS * 100).toStringAsFixed(1)}%',
                          onChanged: updateFontScaleFS,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('字体粗细 ${subtitleFontWeight + 1}（可能无法精确调节）'),
                          resetBtn(theme, 6, () => updateFontWeight(5)),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0,
                          max: 8,
                          value: subtitleFontWeight.toDouble(),
                          divisions: 8,
                          label: '${subtitleFontWeight + 1}',
                          onChanged: updateFontWeight,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('描边粗细 $subtitleStrokeWidth'),
                          resetBtn(theme, 2.0, () => updateStrokeWidth(2.0)),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0,
                          max: 5,
                          value: subtitleStrokeWidth,
                          divisions: 10,
                          label: '$subtitleStrokeWidth',
                          onChanged: updateStrokeWidth,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('左右边距 $subtitlePaddingH'),
                          resetBtn(
                            theme,
                            24,
                            () => updateHorizontalPadding(24),
                          ),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0,
                          max: 100,
                          value: subtitlePaddingH.toDouble(),
                          divisions: 100,
                          label: '$subtitlePaddingH',
                          onChanged: updateHorizontalPadding,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('底部边距 $subtitlePaddingB'),
                          resetBtn(theme, 24, () => updateBottomPadding(24)),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0,
                          max: 200,
                          value: subtitlePaddingB.toDouble(),
                          divisions: 200,
                          label: '$subtitlePaddingB',
                          onChanged: updateBottomPadding,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '背景不透明度 ${(subtitleBgOpacity * 100).toStringAsFixed(1)}%',
                          ),
                          resetBtn(theme, '67%', () => updateOpacity(0.67)),
                        ],
                      ),
                      Padding(
                        padding: sliderPadding,
                        child: Slider(
                          min: 0,
                          max: 1,
                          divisions: 100,
                          value: subtitleBgOpacity,
                          onChanged: updateOpacity,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    )?.whenComplete(plPlayerController.putSubtitleSettings);
  }

  void showDanmakuPool() {
    final player = plPlayerController;
    final cid = player.cid;
    final display = player.danmakuDisplay;
    final mediaIsCurrent = player.captureDanmakuMedia();
    if (cid == null || display == null || player.danmakuInteraction == null) {
      return;
    }
    bool isCurrent() => mounted && mediaIsCurrent();
    showBottomSheet((context, setState) {
      final ctr = isCurrent() ? player.danmakuInteraction : null;
      final theme = Theme.of(context);
      final isPortrait =
          MediaQuery.orientationOf(context) == Orientation.portrait;
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: isPortrait
              ? const BorderRadius.vertical(top: Radius.circular(12))
              : BorderRadius.circular(12),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                height: 45,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('弹幕列表'),
                    iconButton(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Material(
                  type: .transparency,
                  clipBehavior: .hardEdge,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  child: CustomScrollView(
                    slivers: [
                      ?_buildDanmakuList(
                        ctr?.snapshot ?? const [],
                        cid: cid,
                        isCurrent: isCurrent,
                        remove: (id) => display.remove?.call(id),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget? _buildDanmakuList(
    List<DanmakuDisplaySnapshot<DanmakuExtra>> list, {
    required int cid,
    required bool Function() isCurrent,
    required void Function(int) remove,
  }) {
    if (list.isEmpty) return null;

    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final extra = item.extra! as VideoDanmaku;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          onLongPress: () => copyText(item.text),
          title: Text(
            item.text,
            style: const TextStyle(fontSize: 14),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DanmakuLikeControl(
                extra: extra,
                cid: cid,
                isCurrent: isCurrent,
                builder: (context, onLike) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    iconButton(
                      onPressed: onLike,
                      icon: extra.isLike
                          ? const Icon(CustomIcons.player_dm_tip_like_solid)
                          : const Icon(CustomIcons.player_dm_tip_like),
                    ),
                    if (extra.like > 0)
                      Positioned(
                        left: 24.5,
                        top: 1.5,
                        child: Text(
                          extra.like.toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0,
                            // fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (item.selfSend)
                iconButton(
                  onPressed: () => recallVideoDanmaku(
                    VideoDanmakuInteractions(cid, mediaIsCurrent: isCurrent),
                    extra.id,
                    onRecalled: () => remove(extra.id),
                  ),
                  icon: const Icon(CustomIcons.player_dm_tip_recall),
                )
              else
                iconButton(
                  onPressed: () => reportVideoDanmaku(
                    context,
                    VideoDanmakuInteractions(cid, mediaIsCurrent: isCurrent),
                    extra,
                    blockRules: (
                      read: () => plPlayerController.filters,
                      publish: (rules) => plPlayerController.filters = rules,
                    ),
                  ),
                  icon: const Icon(CustomIcons.player_dm_tip_back),
                ),
            ],
          ),
        );
      },
    );
  }

  late final isFileSource = videoDetailCtr.isFileSource;

  @override
  Widget build(BuildContext context) {
    final isFullScreen = this.isFullScreen;
    final isFSOrPip = isFullScreen || plPlayerController.isDesktopPip;
    final showFSActionItem =
        !isFileSource && plPlayerController.showFSActionItem && isFSOrPip;
    showCurrTimeIfNeeded(isFullScreen);
    final showTitle =
        isFullScreen ||
        ((!horizontalScreen || plPlayerController.isDesktopPip) && !isPortrait);
    final title = showTitle
        ? ValueListenableBuilder(
            valueListenable: introController.videoDetail,
            builder: (context, videoDetail, _) {
              final title = videoDetail.title;
              if (title == null) return const Spacer();
              Widget label = Padding(
                key: titleKey,
                padding: isPortrait
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(right: 10),
                child: ValueListenableBuilder(
                  valueListenable: videoDetailCtr.cid,
                  builder: (context, cid, _) => MarqueeText(
                    isFileSource || videoDetail.videos == 1
                        ? title
                        : videoDetail.pages
                                  ?.firstWhereOrNull((part) => part.cid == cid)
                                  ?.part ??
                              title,
                    spacing: 30,
                    velocity: 30,
                    strutStyle: const StrutStyle(fontSize: 16, leading: 0),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    provider: effectiveProvider,
                  ),
                ),
              );
              if (introController.isShowOnlineTotal) {
                label = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    ValueListenableBuilder(
                      valueListenable: introController.total,
                      builder: (context, total, _) => Text(
                        '$total人正在看',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Expanded(child: label);
            },
          )
        : const Spacer();

    final compactWindow =
        plPlayerController.isDesktopPip &&
        MediaQuery.sizeOf(context).width < 640;
    const btnWidth = 42.0;
    const btnHeight = 34.0;
    const btnStyle = ButtonStyle(padding: WidgetStatePropertyAll(.zero));

    return Padding(
      padding: const .symmetric(vertical: 12),
      child: Column(
        mainAxisSize: .min,
        children: [
          if (compactWindow)
            Row(
              children: [
                title,
                ...?timeBatteryWidgets,
                DesktopWindowControls(controller: plPlayerController),
              ],
            ),
          Row(
            children: [
              if (!plPlayerController.isDesktopPip)
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: '返回',
                    style: btnStyle,
                    icon: Icon(
                      FontAwesomeIcons.arrowLeft.data,
                      size: 15,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        plPlayerController.onPopInvokedWithResult(false, null),
                  ),
                ),
              if (!plPlayerController.isDesktopPip &&
                  (!isFullScreen || !isPortrait))
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: '返回主页',
                    style: btnStyle,
                    icon: Icon(
                      FontAwesomeIcons.house.data,
                      size: 15,
                      color: Colors.white,
                    ),
                    onPressed: plPlayerController.onCloseAll,
                  ),
                ),
              if (!compactWindow) ...[
                title,
                ...?timeBatteryWidgets,
              ] else
                const Spacer(),
              if (PlatformUtils.isDesktop)
                Obx(() {
                  final isAlwaysOnTop = plPlayerController.isAlwaysOnTop.value;
                  return SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: IconButton(
                      style: btnStyle,
                      tooltip: '${isAlwaysOnTop ? '取消' : ''}置顶',
                      onPressed: () =>
                          plPlayerController.setAlwaysOnTop(!isAlwaysOnTop),
                      icon: isAlwaysOnTop
                          ? const Icon(
                              size: 19,
                              Icons.push_pin,
                              color: Colors.white,
                            )
                          : const Icon(
                              size: 19,
                              Icons.push_pin_outlined,
                              color: Colors.white,
                            ),
                    ),
                  );
                }),
              if (!isFileSource) ...[
                if (!isFSOrPip) ...[
                  if (videoDetailCtr.isUgc)
                    SizedBox(
                      width: btnWidth,
                      height: btnHeight,
                      child: IconButton(
                        tooltip: '听音频',
                        style: btnStyle,
                        onPressed: videoDetailCtr.toAudioPage,
                        icon: const Icon(
                          Icons.headphones_outlined,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: IconButton(
                      tooltip: '投屏',
                      style: btnStyle,
                      onPressed: videoDetailCtr.onCast,
                      icon: const Icon(
                        Icons.cast,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (kDebugMode || plPlayerController.enableSponsorBlock)
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: IconButton(
                      tooltip: '提交片段',
                      style: btnStyle,
                      onPressed: () => videoDetailCtr.onBlock(context),
                      icon: const Icon(
                        CustomIcons.shield_play_arrow,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ValueListenableBuilder(
                  valueListenable: videoDetailCtr.segmentChanges,
                  builder: (context, segments, child) => segments.isNotEmpty
                      ? SizedBox(
                          width: btnWidth,
                          height: btnHeight,
                          child: IconButton(
                            tooltip: '片段信息',
                            style: btnStyle,
                            onPressed: videoDetailCtr.showSBDetail,
                            icon: const Icon(
                              MdiIcons.advertisements,
                              size: 19,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
              if (!isPortrait || isFullScreen || PlatformUtils.isDesktop) ...[
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: '发弹幕',
                    style: btnStyle,
                    onPressed: videoDetailCtr.showShootDanmakuSheet,
                    icon: const Icon(
                      Icons.comment_outlined,
                      size: 19,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: Obx(
                    () {
                      final enableShowDanmaku =
                          plPlayerController.enableShowDanmaku.value;
                      return IconButton(
                        tooltip: "${enableShowDanmaku ? '关闭' : '开启'}弹幕",
                        style: btnStyle,
                        onPressed: () => plPlayerController
                            .toggleDanmakuVisibility(live: false),
                        icon: enableShowDanmaku
                            ? const Icon(
                                size: 20,
                                CustomIcons.dm_on,
                                color: Colors.white,
                              )
                            : const Icon(
                                size: 20,
                                CustomIcons.dm_off,
                                color: Colors.white,
                              ),
                      );
                    },
                  ),
                ),
              ],
              SizedBox(
                width: btnWidth,
                height: btnHeight,
                child: IconButton(
                  tooltip: '弹幕设置',
                  style: btnStyle,
                  onPressed: showSetDanmaku,
                  icon: const Icon(
                    size: 20,
                    CustomIcons.dm_settings,
                    color: Colors.white,
                  ),
                ),
              ),
              if (PlatformUtils.isDesktop)
                DesktopPlaybackMenu(controller: plPlayerController),
              if (Platform.isAndroid)
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: IconButton(
                    tooltip: '画中画',
                    style: btnStyle,
                    onPressed: () {
                      if (PlatformUtils.isDesktop) {
                        plPlayerController.toggleDesktopPip();
                        return;
                      }
                      if (AndroidHelper.isPipAvailable) {
                        plPlayerController.enterPip();
                      }
                    },
                    icon: const Icon(
                      Icons.picture_in_picture_outlined,
                      size: 19,
                      color: Colors.white,
                    ),
                  ),
                ),
              SizedBox(
                width: btnWidth,
                height: btnHeight,
                child: IconButton(
                  tooltip: "更多设置",
                  style: btnStyle,
                  onPressed: showSettingSheet,
                  icon: const Icon(
                    Icons.more_vert_outlined,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ),
              if (plPlayerController.isDesktopPip && !compactWindow)
                DesktopWindowControls(controller: plPlayerController),
            ],
          ),
          if (showFSActionItem)
            Row(
              mainAxisAlignment: .end,
              crossAxisAlignment: .start,
              children: [
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: ValueListenableBuilder(
                    valueListenable: introController.hasLike,
                    builder: (context, liked, _) => ActionItem(
                      expand: false,
                      icon: Icon(
                        FontAwesomeIcons.thumbsUp.data,
                        color: Colors.white,
                      ),
                      selectIcon: Icon(FontAwesomeIcons.solidThumbsUp.data),
                      selectStatus: liked,
                      semanticsLabel: '点赞',
                      animation: introController.tripleAnimation,
                      onStartTriple: () {
                        plPlayerController.tripling = true;
                        introController.onStartTriple();
                      },
                      onCancelTriple: ([bool isTapUp = false]) {
                        plPlayerController
                          ..tripling = false
                          ..hideTaskControls();
                        introController.onCancelTriple(isTapUp);
                      },
                    ),
                  ),
                ),
                if (introController case final UgcIntroController ugc)
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: ValueListenableBuilder(
                      valueListenable: ugc.hasDislike,
                      builder: (context, disliked, _) => ActionItem(
                        expand: false,
                        icon: Icon(
                          FontAwesomeIcons.thumbsDown.data,
                          color: Colors.white,
                        ),
                        selectIcon: Icon(
                          FontAwesomeIcons.solidThumbsDown.data,
                        ),
                        onTap: () => ugc.handleAction(ugc.actionDislikeVideo),
                        selectStatus: disliked,
                        semanticsLabel: '点踩',
                      ),
                    ),
                  ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: ValueListenableBuilder(
                    valueListenable: introController.coinNum,
                    builder: (context, coins, _) => ActionItem(
                      expand: false,
                      animation: introController.tripleAnimation,
                      icon: Icon(
                        FontAwesomeIcons.b.data,
                        color: Colors.white,
                      ),
                      selectIcon: Icon(FontAwesomeIcons.b.data),
                      onTap: introController.actionCoinVideo,
                      selectStatus: coins != 0,
                      semanticsLabel: '投币',
                    ),
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: ValueListenableBuilder(
                    valueListenable: introController.hasFav,
                    builder: (context, favored, _) => ActionItem(
                      expand: false,
                      animation: introController.tripleAnimation,
                      icon: Icon(
                        FontAwesomeIcons.star.data,
                        color: Colors.white,
                      ),
                      selectIcon: Icon(FontAwesomeIcons.solidStar.data),
                      onTap: () => introController.showFavBottomSheet(context),
                      onLongPress: () => introController.showFavBottomSheet(
                        context,
                        isLongPress: true,
                      ),
                      selectStatus: favored,
                      semanticsLabel: '收藏',
                    ),
                  ),
                ),
                SizedBox(
                  width: btnWidth,
                  height: btnHeight,
                  child: ActionItem(
                    expand: false,
                    icon: Icon(
                      FontAwesomeIcons.shareFromSquare.data,
                      color: Colors.white,
                    ),
                    onTap: () => introController.actionShareVideo(context),
                    semanticsLabel: '分享',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
