import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/pages/danmaku/window_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const option = DanmakuOption(fontSize: 20, safeArea: false);
  DanmakuWindowRenderer<void> create() {
    final renderer = DanmakuWindowRenderer<void>(
      option: option,
      size: const Size(640, 360),
    );
    renderer.prepare(
      [
        for (var i = 0; i < 3; i++)
          DanmakuWindowContent('$i', 0, DanmakuContentItem<void>('item$i')),
      ],
      generation: renderer.generation,
      preparedUntilUs: 10000000,
    );
    renderer.present(1000000);
    addTearDown(renderer.dispose);
    return renderer;
  }

  test('横屏全屏后固定弹幕按新视口居中并贴合底部轨道', () {
    const portrait = Size(360, 202);
    const landscape = Size(800, 360);
    final renderer = DanmakuWindowRenderer<void>(
      option: option,
      size: portrait,
    );
    addTearDown(renderer.dispose);
    renderer.prepare(
      [
        for (final type in [DanmakuItemType.top, DanmakuItemType.bottom])
          DanmakuWindowContent(
            type,
            0,
            DanmakuContentItem<void>(type.name, type: type),
          ),
      ],
      generation: renderer.generation,
      preparedUntilUs: 5000000,
    );
    renderer.present(1000000);
    Rect bounds(DanmakuItemType type) => renderer.interaction.snapshot
        .singleWhere((item) => item.identity == type)
        .bounds;
    final portraitBottom = bounds(DanmakuItemType.bottom).bottom;
    expect(bounds(DanmakuItemType.top).center.dx, portrait.width / 2);

    renderer.requestConfiguration(
      option: option,
      size: landscape,
      devicePixelRatio: 1,
    );
    expect(renderer.prepareConfiguration(), isTrue);
    renderer.present(1000000, allowUnprepared: true);

    expect(bounds(DanmakuItemType.top).center.dx, landscape.width / 2);
    final bottom = bounds(DanmakuItemType.bottom);
    expect(bottom.center.dx, landscape.width / 2);
    expect(bottom.bottom, greaterThan(portraitBottom));
    expect(bottom.bottom, lessThanOrEqualTo(landscape.height));
    expect(renderer.hitTest(bottom.center)?.identity, DanmakuItemType.bottom);

    renderer.prepare(
      [
        DanmakuWindowContent(
          'new-bottom',
          1200000,
          DanmakuContentItem<void>('new', type: DanmakuItemType.bottom),
        ),
      ],
      generation: renderer.generation,
      preparedUntilUs: 2000000,
    );
    renderer.present(1200000);
    final incoming = renderer.interaction.snapshot
        .singleWhere((item) => item.identity == 'new-bottom')
        .bounds;
    expect(incoming.bottom, lessThanOrEqualTo(bottom.top));
  });

  test('轨道收缩时优先保留选中弹幕并重排滚动弹幕', () {
    final renderer = create();
    final handle = renderer.interaction..select('2');
    final before = handle.snapshot.singleWhere((item) => item.selected).bounds;
    final trackHeight = renderer.rasters.measureTrackHeight();
    final size = Size(640, trackHeight * 2 + .01);

    renderer.requestConfiguration(
      option: option,
      size: size,
      devicePixelRatio: 1,
    );
    expect(renderer.prepareConfiguration(), isTrue);
    renderer.present(1000000, allowUnprepared: true);

    expect(handle.snapshot, hasLength(2));
    final selected = handle.snapshot.singleWhere((item) => item.selected);
    expect(selected.identity, '2');
    expect(selected.bounds.left, before.left);
    expect(selected.bounds.top, trackHeight);
    expect(selected.bounds.bottom, lessThanOrEqualTo(size.height));
    expect(handle.hitTest(selected.bounds.center)?.identity, '2');
    final moving = handle.snapshot.singleWhere((item) => !item.selected);
    expect(moving.bounds.overlaps(selected.bounds), isFalse);
    renderer.present(1100000, allowUnprepared: true);
    expect(
      handle.snapshot.singleWhere((item) => item.selected).bounds,
      selected.bounds,
    );
    expect(
      handle.snapshot.singleWhere((item) => !item.selected).bounds.left,
      lessThan(moving.bounds.left),
    );
  });

  test('缩小视口和缩小显示区域得到相同排布并复用图片', () {
    final resized = create();
    final changedArea = create();
    final trackHeight = resized.rasters.measureTrackHeight();
    final height = trackHeight * 2 + .01;
    final size = Size(640, height);
    final resizedCache = resized.rasters;
    final areaCache = changedArea.rasters;
    final images = resizedCache.rasterizations;

    resized
      ..requestConfiguration(option: option, size: size, devicePixelRatio: 1)
      ..present(1000000);
    changedArea
      ..requestConfiguration(
        option: option.copyWith(area: height / 360),
        size: const Size(640, 360),
        devicePixelRatio: 1,
      )
      ..present(1000000);

    Map<Object, Rect> placements(DanmakuWindowRenderer<void> renderer) => {
      for (final item in renderer.interaction.snapshot)
        item.identity: item.bounds,
    };
    expect(placements(resized), hasLength(2));
    expect(placements(changedArea), placements(resized));
    expect(resized.rasters, same(resizedCache));
    expect(changedArea.rasters, same(areaCache));
    expect(resized.rasters.rasterizations, images);
    expect(changedArea.rasters.rasterizations, images);
  });

  test('待应用的视口配置不会恢复已撤回的弹幕', () {
    final renderer = create()
      ..requestConfiguration(
        option: option,
        size: const Size(800, 360),
        devicePixelRatio: 1,
      )
      ..invalidateRange(0, endUs: 1);
    expect(renderer.hasPendingConfiguration, isTrue);
    expect(renderer.interaction.snapshot, isEmpty);
    renderer.present(1000000);
    expect(renderer.hasPendingConfiguration, isFalse);
    expect(renderer.interaction.snapshot, isEmpty);
  });

  test('configuration preparation is bounded, coalesced and committed with hit geometry', () {
    final renderer = create();
    final handle = renderer.interaction..select('0');
    final before = handle.snapshot.firstWhere((item) => item.identity == '0');
    final generation = renderer.generation;
    renderer.requestConfiguration(
      option: option.copyWith(fontSize: 30),
      size: const Size(640, 360),
      devicePixelRatio: 2,
    );
    expect(renderer.prepareConfiguration(maxItems: 1), isFalse);
    renderer.present(1000000, allowUnprepared: true);
    expect(renderer.generation, generation);
    expect(
      handle.snapshot.firstWhere((item) => item.identity == '0').bounds,
      before.bounds,
    );
    renderer.requestConfiguration(
      option: option.copyWith(fontSize: 40),
      size: const Size(800, 360),
      devicePixelRatio: 1.5,
      fontFamily: 'sans-serif',
    );
    // 新配置包含三项；每次只准备一项，必须在第三次结束。
    expect(renderer.prepareConfiguration(maxItems: 1), isFalse);
    expect(renderer.prepareConfiguration(maxItems: 1), isFalse);
    expect(renderer.prepareConfiguration(maxItems: 1), isTrue);
    expect(renderer.rasters.option.fontSize, 20);
    renderer.present(1500000, allowUnprepared: true);
    expect(renderer.rasters.option.fontSize, 40);
    expect(renderer.rasters.devicePixelRatio, 1.5);
    expect(renderer.validFromUs, 1500000);
    expect(renderer.generation, greaterThan(generation));
    final after = handle.snapshot.firstWhere((item) => item.identity == '0');
    expect(after.selected, isTrue);
    expect(after.bounds.topLeft, before.bounds.topLeft);
    expect(after.bounds.width, greaterThan(before.bounds.width));
    expect(handle.hitTest(after.bounds.center)?.identity, '0');
    expect(handle.clearSelection(), isTrue);
  });

  test('area shrink clips hits immediately and reset releases prepared resources and keeps latest settings', () {
    final renderer = create()
      ..requestConfiguration(
        option: option.copyWith(area: 0.1),
        size: const Size(640, 360),
        devicePixelRatio: 1,
      );
    expect(renderer.hitTest(const Offset(600, 100)), isNull);
    renderer
      ..prepareConfiguration(maxItems: 1)
      ..reset(5000000);
    expect(renderer.hasPendingConfiguration, isTrue);
    renderer.present(5000000, allowUnprepared: true);
    expect(renderer.rasters.option.area, 0.1);
    expect(renderer.activeBytes, 0);
  });
  test('identical targets preserve preparation and shared backing stays within peak budget', () {
    final renderer = create();
    final optionNext = option.copyWith(fontSize: 28);
    renderer.requestConfiguration(
      option: optionNext,
      size: const Size(640, 360),
      devicePixelRatio: 1,
    );
    expect(renderer.prepareConfiguration(maxItems: 1), isFalse);
    renderer.requestConfiguration(
      option: optionNext.copyWith(),
      size: const Size(640, 360),
      devicePixelRatio: 1,
    );
    expect(renderer.prepareConfiguration(maxItems: 1), isFalse);
    expect(renderer.prepareConfiguration(maxItems: 1), isTrue);
    expect(
      renderer.workingSetBytes,
      lessThanOrEqualTo(renderer.maxWorkingSetBytes),
    );
    renderer.present(1000000, allowUnprepared: true);
    final generation = renderer.generation;
    renderer.requestConfiguration(
      option: optionNext.copyWith(),
      size: const Size(640, 360),
      devicePixelRatio: 1,
    );
    expect(renderer.hasPendingConfiguration, isFalse);
    expect(renderer.generation, generation);
  });
}
