import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/data/topic_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_mention/group.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_mention/item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/all_sort_by.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/fold_card_item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/item.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_feed/topic_sort_by_conf.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/top_details.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/features/community/domain/topic_cursor.dart';
import 'package:pili_aurora_next/features/community/presentation/community_picker_memory.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/pages/dynamics_mention/view.dart';
import 'package:pili_aurora_next/pages/dynamics_create/view.dart';
import 'package:pili_aurora_next/pages/dynamics_select_topic/view.dart';
import 'package:pili_aurora_next/pages/dynamics_topic/view.dart';
import 'package:pili_aurora_next/pages/dynamics_topic_rcmd/view.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

import '../../support/memory_box.dart';

TopicItem topic(int id, String name) => TopicItem(
  id: id,
  name: name,
  view: 10,
  discuss: 2,
  fav: 2,
  like: 3,
  description: '话题说明',
);

class _Repository extends TopicRepository {
  final searches = <(String, int)>[];
  final mentionsRead = <String>[];
  final sorts = <int>[];
  int likes = 0, favorites = 0, unfolds = 0;
  int topicCount = 1;
  int searchPageSize = 100;
  bool favoriteValue = false, likeValue = false;
  Completer<LoadingState<void>>? pendingLike;
  Completer<LoadingState<DiscoveryPage<TopicItem, void>>>? pendingSearch;
  Completer<LoadingState<DiscoveryPage<TopicCardItem, TopicCursor>>>?
  pendingFeed;
  @override
  Future<LoadingState<TopDetails?>> top(Account account, String id) async =>
      Success(
        TopDetails(
          topicItem: topic(int.parse(id), '话题$id')
            ..isFav = favoriteValue
            ..isLike = likeValue,
        ),
      );
  @override
  Future<LoadingState<DiscoveryPage<TopicCardItem, TopicCursor>>> feed(
    Account account,
    String id,
    int sort,
    TopicCursor? cursor,
  ) async {
    sorts.add(sort);
    return pendingFeed == null
        ? Success(
            DiscoveryPage(
              [
                TopicCardItem(topicType: '排序$sort的内容'),
                TopicCardItem(
                  foldCardItem: FoldCardItem(foldCount: 1, foldDesc: '展开更多'),
                ),
              ],
              metadata: TopicCursor(
                '',
                {},
                TopicSortByConf(
                  showSortBy: sort,
                  allSortBy: [
                    AllSortBy(sortBy: 0, sortName: '热门'),
                    AllSortBy(sortBy: 1, sortName: '最新'),
                  ],
                ),
              ),
              hasMore: false,
            ),
          )
        : pendingFeed!.future;
  }

  @override
  Future<LoadingState<List<TopicCardItem>>> fold(
    Account account,
    String id,
    int sort,
  ) async {
    unfolds++;
    return unfolds == 1
        ? const Error('展开失败')
        : Success([TopicCardItem(topicType: '展开的内容')]);
  }

  @override
  Future<LoadingState<DiscoveryPage<TopicItem, void>>> recommended(
    Account account,
  ) async => Success(
    DiscoveryPage([topic(12, '推荐话题')], metadata: null, hasMore: false),
  );
  @override
  Future<LoadingState<DiscoveryPage<TopicItem, void>>> search(
    Account account,
    String keyword,
    int page,
  ) async {
    searches.add((keyword, page));
    return pendingSearch == null
        ? Success(
            DiscoveryPage(
              [
                for (
                  var index = (page - 1) * searchPageSize;
                  index < topicCount && index < page * searchPageSize;
                  index++
                )
                  topic(
                    12 + index,
                    keyword.isEmpty ? '默认话题$index' : '$keyword$index',
                  ),
              ],
              metadata: null,
              hasMore: page * searchPageSize < topicCount,
            ),
          )
        : pendingSearch!.future;
  }

  @override
  Future<LoadingState<DiscoveryPage<MentionGroup, void>>> mentions(
    Account account,
    String keyword,
  ) async {
    mentionsRead.add(keyword);
    return Success(
      DiscoveryPage(
        [
          MentionGroup(
            groupName: '相关用户',
            items: [
              MentionItem(uid: '1', name: '用户甲', face: '', fans: 10),
              MentionItem(uid: '2', name: '用户乙', face: '', fans: 20),
            ],
          ),
        ],
        metadata: null,
        hasMore: false,
      ),
    );
  }

  @override
  Future<LoadingState<void>> favorite(
    Account account,
    String id,
    bool wasFavorite,
  ) async {
    favorites++;
    favoriteValue = !wasFavorite;
    return const Success(null);
  }

  @override
  Future<LoadingState<void>> like(
    Account account,
    String id,
    bool wasLiked,
  ) async {
    likes++;
    likeValue = !wasLiked;
    return pendingLike == null ? const Success(null) : pendingLike!.future;
  }
}

void main() {
  late _Repository repository;
  LoginAccount account([String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  setUpAll(() {
    GStorage.setting = MemoryBox({SettingBoxKey.filterBlockedAuthors: false});
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    GStorage.userInfo = MemoryBox();
  });
  setUp(() {
    repository = _Repository();
    Accounts.accountMode[AccountType.main.index] = account();
  });
  tearDown(Get.reset);
  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [topicRepositoryProvider.overrideWithValue(repository)],
        child: GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          home: child,
          getPages: [
            GetPage(
              name: '/dynTopic',
              page: () => DynTopicPage(
                topicId: Get.parameters['id']!,
                name: Get.parameters['name'] ?? '',
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('选话题搜索立即隐藏旧结果，清空取消防抖，返回单个话题并保留搜索记忆', (tester) async {
    final memory = CommunityPickerMemory<void>();
    TopicItem? selected;
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await SelectTopicPanel.onSelectTopic(
                context,
                memory: memory,
              );
            },
            child: const Text('选择话题'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择话题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('默认话题', findRichText: true), findsOneWidget);
    final stale = repository.pendingSearch = Completer();
    await tester.enterText(find.byType(TextField), '旧搜索');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新搜索');
    await tester.pump();
    stale.complete(
      Success(
        DiscoveryPage([topic(1, '过期话题')], metadata: null, hasMore: false),
      ),
    );
    repository.pendingSearch = null;
    await tester.pump();
    expect(find.textContaining('过期话题', findRichText: true), findsNothing);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(repository.searches.last.$1, '');
    await tester.enterText(find.byType(TextField), '保留搜索');
    await tester.pumpAndSettle();
    expect(repository.searches.last.$1, '保留搜索');
    await tester.tap(find.textContaining('保留搜索', findRichText: true).last);
    await tester.pumpAndSettle();
    expect(selected?.id, 12);
    await tester.tap(find.text('选择话题'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留搜索',
    );
    await finish(tester);
  });

  testWidgets('选择面板恢复缓存滚动，搜索回顶，多个面板输入互不影响', (tester) async {
    repository.topicCount = 40;
    final scroll = ScrollController(initialScrollOffset: 240);
    double? cached;
    await mount(
      tester,
      Scaffold(
        body: Row(
          children: [
            Expanded(
              child: SelectTopicPanel(
                scrollController: scroll,
                onCachePos: (value) => cached = value,
              ),
            ),
            const Expanded(child: SelectTopicPanel()),
          ],
        ),
      ),
    );
    expect(scroll.offset, 240);
    await tester.enterText(find.byType(TextField).first, '左侧');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.textContaining('左侧0', findRichText: true), findsOneWidget);
    expect(scroll.position.maxScrollExtent, greaterThan(220));
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '',
    );
    unawaited(
      scroll.animateTo(
        220,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(cached, greaterThan(0));
    expect(repository.searches, contains(('左侧', 1)));
    await finish(tester);
    scroll.dispose();
  });

  testWidgets('重开面板恢复深层滚动时补齐需要的分页', (tester) async {
    repository
      ..topicCount = 48
      ..searchPageSize = 12;
    final scroll = ScrollController(initialScrollOffset: 1600);
    await mount(
      tester,
      Scaffold(body: SelectTopicPanel(scrollController: scroll)),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, 1600);
    expect(
      repository.searches.map((request) => request.$2),
      containsAllInOrder([1, 2, 3]),
    );
    await finish(tester);
    scroll.dispose();
  });

  testWidgets('@用户单选与多选返回独立结果，取消后重开保留选择，切号清空选择', (tester) async {
    final memory = CommunityPickerMemory<MentionItem>();
    Object? selected;
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await DynMentionPanel.onDynMention(
                context,
                memory: memory,
              );
            },
            child: const Text('提及用户'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('提及用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DynMentionPanel))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('提及用户'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, true);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect((selected as Set<MentionItem>).map((item) => item.uid), ['1', '2']);
    expect(memory.selected, isEmpty);
    await tester.tap(find.text('提及用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户乙'));
    await tester.pumpAndSettle();
    expect((selected as MentionItem).uid, '2');
    await tester.tap(find.text('提及用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    Accounts.replaceCredentials(account('replacement'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, false);
    expect(memory.selected, isEmpty);
    await tester.enterText(find.byType(TextField), '新用户');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(repository.mentionsRead.last, '');
    await finish(tester);
  });

  testWidgets('推荐跳转话题，排序、点赞取消、收藏取消与展开重试保留操作语义', (tester) async {
    await mount(tester, const DynTopicRcmdPage());
    await tester.tap(find.textContaining('推荐话题', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('话题12'), findsWidgets);
    expect(find.text('排序0的内容'), findsOneWidget);
    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();
    expect(repository.sorts.last, 1);
    expect(find.text('排序1的内容'), findsOneWidget);
    final buttons = find.byType(OutlinedButton);
    repository.pendingLike = Completer();
    await tester.tap(buttons.first);
    await tester.pump();
    await tester.tap(buttons.first);
    await tester.pump();
    expect(repository.likes, 1);
    repository.pendingLike!.complete(const Success(null));
    repository.pendingLike = null;
    await tester.pumpAndSettle();
    await tester.tap(buttons.first);
    await tester.pumpAndSettle();
    expect(repository.likeValue, false);
    await tester.tap(buttons.last);
    await tester.pumpAndSettle();
    expect(repository.favoriteValue, true);
    await tester.tap(buttons.last);
    await tester.pumpAndSettle();
    expect(repository.favoriteValue, false);
    await tester.tap(find.text('展开更多'));
    await tester.pump();
    expect(find.text('展开失败'), findsOneWidget);
    await tester.tap(find.text('展开更多'));
    await tester.pumpAndSettle();
    expect(find.text('展开的内容'), findsOneWidget);
    expect(find.text('展开更多'), findsNothing);
    expect(find.text('参与话题'), findsOneWidget);
    await tester.tap(find.text('参与话题'));
    await tester.pumpAndSettle();
    final editor = tester.widget<CreateDynPanel>(find.byType(CreateDynPanel));
    expect(editor.topic?.first, 12);
    expect(editor.topic?.second, '话题12');
    await finish(tester);
  });
}
