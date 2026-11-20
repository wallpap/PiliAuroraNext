import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/image/cached_image.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/emote/emote.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/emote_repository.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/pages/emote/view.dart';
import 'package:pili_aurora_next/pages/emote/manage.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/features/community/application/emote_panel.dart';

import '../../support/memory_box.dart';
import '../../support/controlled_interceptor.dart';

class _Repository extends EmoteRepository {
  _Repository(Package package) : current = [package];
  List<Package> current;
  @override
  Future<LoadingState<List<Package>?>> packages(Account account) async =>
      Success(current);
}

void main() {
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
  });
  setUp(() {
    (GStorage.localCache as MemoryBox).data.clear();
    Get.testMode = true;
  });
  tearDown(Get.reset);

  testWidgets(
    'ordinary image emotes mount only viewport and bounded neighbors',
    (tester) async {
      final emotes = List.generate(
        600,
        (index) => Emote(
          text: '[synthetic-$index]',
          url: 'https://example.test/emote-$index.webp',
        ),
      );
      final repository = _Repository(
        Package(type: 1, text: 'synthetic', emote: emotes),
      );
      Emote? chosen;
      await tester.pumpWidget(
        ImageLoadingScope(
          enabled: false,
          child: ProviderScope(
            overrides: [emoteRepositoryProvider.overrideWithValue(repository)],
            child: MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    height: 300,
                    child: EmotePanel(
                      onChoose: (emote, _, _) => chosen = emote,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final visible = find.byWidgetPredicate(
        (widget) =>
            widget is NetworkImgLayer &&
            widget.src?.startsWith('https://example.test/emote-') == true,
      );
      expect(visible.evaluate().length, greaterThan(0));
      expect(visible.evaluate().length, lessThan(100));
      final last = find.byWidgetPredicate(
        (widget) => widget is NetworkImgLayer && widget.src == emotes.last.url,
      );
      final packageGrid = find.byWidgetPredicate(
        (widget) =>
            widget is GridView &&
            widget.childrenDelegate.estimatedChildCount == emotes.length,
      );
      final scrollable = find
          .descendant(
            of: packageGrid,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(last, findsOneWidget);
      expect(visible.evaluate().length, lessThan(100));
      final selectable = find
          .ancestor(of: last, matching: find.byType(InkWell))
          .hitTestable();
      await tester.tap(selectable.first);
      expect(chosen?.url, emotes.last.url);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('text emotes remain text and preserve chosen value', (
    tester,
  ) async {
    final emote = Emote(text: '(synthetic text)');
    final repository = _Repository(
      Package(type: 4, text: 'text', emote: [emote]),
    );
    Emote? chosen;
    double? chosenWidth = 1;
    await tester.pumpWidget(
      ImageLoadingScope(
        enabled: false,
        child: ProviderScope(
          overrides: [emoteRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 300,
                child: EmotePanel(
                  onChoose: (value, width, _) {
                    chosen = value;
                    chosenWidth = width;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('(synthetic text)'));
    expect(chosen, same(emote));
    expect(chosenWidth, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('多个表情面板拥有独立 Tab，共享历史，单面板卸载不销毁其他面板', (tester) async {
    final repository = _Repository(
      Package(type: 4, emote: [Emote(text: '共享历史')]),
    );
    final container = ProviderContainer(
      overrides: [emoteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    Widget panels(bool second) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: EmotePanel(
                key: const ValueKey('first'),
                onChoose: (_, _, _) {},
              ),
            ),
            if (second)
              Expanded(
                child: EmotePanel(
                  key: const ValueKey('second'),
                  onChoose: (_, _, _) {},
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(panels(true));
    await tester.pumpAndSettle();
    final tabs = tester
        .widgetList<TabBar>(find.byType(TabBar))
        .map((tab) => tab.controller!)
        .toList();
    expect(tabs, hasLength(2));
    expect(identical(tabs[0], tabs[1]), isFalse);
    await tester.tap(find.text('共享历史').first);
    await tester.pumpAndSettle();
    expect(container.read(recentEmotesProvider).single.emote.text, '共享历史');
    tabs[1].animateTo(0);
    await tester.pump();
    await tester.pumpWidget(panels(false));
    await tester.pumpAndSettle();
    expect(tabs[1].animation, isNull);
    expect(tabs[0].animation, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tabs[0].animation, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从表情管理返回后按包 ID 恢复，删除当前包后回退到有效位置', (tester) async {
    final interceptor = ControlledInterceptor();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
    addTearDown(() async {
      Request.dio.close(force: true);
      await interceptor.close();
    });
    Package pack(int id) => Package(
      id: id,
      type: 4,
      url: 'https://example.test/pack-$id.png',
      emote: [Emote(text: '表情 $id')],
    );
    final repository = _Repository(pack(1))
      ..current = [pack(1), pack(2), pack(3)];
    await tester.pumpWidget(
      ImageLoadingScope(
        enabled: false,
        child: ProviderScope(
          overrides: [emoteRepositoryProvider.overrideWithValue(repository)],
          child: GetMaterialApp(
            home: Scaffold(body: EmotePanel(onChoose: (_, _, _) {})),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tab = tester.widget<TabBar>(find.byType(TabBar)).tabs.last;
    await tester.tapAt(tester.getCenter(find.byWidget(tab)));
    await tester.pumpAndSettle();
    expect(find.text('表情 3'), findsOneWidget);

    Future<void> returnFromManage(List<Package> next) async {
      final expected = interceptor.requests.length + 1;
      await tester.tap(find.byIcon(Icons.settings));
      final deadline = tester.binding.clock.now().add(
        const Duration(seconds: 1),
      );
      while (interceptor.requests.length < expected &&
          tester.binding.clock.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(interceptor.requests, hasLength(expected));
      final request = interceptor.requests.last;
      expect(request.options.path, Api.emoteSettingPanel);
      request.reply.complete({'code': -42, 'message': '测试管理页'});
      await tester.pumpAndSettle();
      expect(find.byType(EmoteManagePage), findsOneWidget);
      repository.current = next;
      Get.back();
      await tester.pumpAndSettle();
    }

    await returnFromManage([pack(1), pack(3), pack(2)]);
    expect(find.text('表情 3'), findsOneWidget);
    await returnFromManage([pack(1)]);
    expect(find.text('表情 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
