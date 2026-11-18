import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/data/favorite_repository.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_detail/ugc.dart';
import 'package:pili_aurora_next/features/favorites/domain/fav_folder/data.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_detail_page.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_panel.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_sort_page.dart';
import 'package:pili_aurora_next/features/favorites/presentation/selection_panel.dart';
import 'package:pili_aurora_next/features/favorites/presentation/transfer_dialog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/id_utils.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../../support/memory_box.dart';

FavDetailItemModel favoriteVideo(int id) => FavDetailItemModel(
  id: id,
  type: 2,
  title: '视频 $id',
  cover: '',
  duration: 10,
);

class FakeFavorites extends FavoriteRepository {
  Future<FeedPage<Object, FavoriteMetadata>> Function(FavoriteQuery, Object?)?
  read;
  Future<LoadingState<void>> Function()? mutation;
  Future<LoadingState<FavFolderData>> Function()? readMembership;
  final requests = <({Account account, FavoriteQuery query, Object? cursor})>[];
  final writes = <String>[];
  final removals = <List<Object>>[];
  List<FavFolderInfo> get available => [
    for (var i = 1; i <= 3; i++)
      FavFolderInfo(
        id: i,
        title: '收藏夹 $i',
        mid: 1,
        attr: 2,
        favState: i == 1 ? 1 : 0,
        mediaCount: i == 1 ? 1 : 0,
      ),
  ];
  Future<LoadingState<void>> send(String action) {
    writes.add(action);
    return mutation?.call() ?? Future.value(const Success(null));
  }

  @override
  Future<FeedPage<Object, FavoriteMetadata>> page(
    Account account,
    FavoriteQuery query,
    Object? cursor, {
    bool Function()? isCurrent,
  }) {
    requests.add((account: account, query: query, cursor: cursor));
    return read?.call(query, cursor) ??
        Future.value(
          FeedPage(
            query.kind == FavoriteKind.folders
                ? available
                : [favoriteVideo(1), favoriteVideo(2)],
            metadata: FavoriteMetadata(
              folder: FavFolderInfo(
                id: query.mediaId,
                mid: 1,
                title: '测试收藏夹',
                mediaCount: 2,
              ),
            ),
          ),
        );
  }

  @override
  Future<LoadingState<void>> remove(
    Account account,
    FavoriteQuery query,
    List<Object> items,
  ) {
    removals.add(items);
    return send('remove:${query.kind.name}');
  }

  @override
  Future<LoadingState<void>> transfer(
    Account account, {
    required int source,
    required int destination,
    required bool copy,
    required String resources,
  }) => send('transfer:$source:$destination:$copy:$resources');
  @override
  Future<LoadingState<void>> sort(
    Account account, {
    int? folder,
    required String order,
  }) => send('sort:$folder:$order');
  @override
  Future<LoadingState<void>> folderAction(
    Account account,
    int id,
    FolderAction action,
  ) => send('folder:$id:${action.name}');
  @override
  Future<LoadingState<void>> pgc(Account account, List<int> ids, int? status) =>
      send('pgc:${ids.join(',')}:$status');
  @override
  Future<List<FavFolderInfo>> folders(Account account) =>
      Future.value(available);
  @override
  Future<LoadingState<FavFolderData>> membership(
    Account account,
    (Object, int) target,
  ) =>
      readMembership?.call() ??
      Future.value(Success(FavFolderData(list: available)));
  @override
  Future<LoadingState<void>> video(
    Account account,
    String resources, {
    String? add,
    String? remove,
  }) => send('video:$resources:$add:$remove');
  @override
  Future<LoadingState<void>> unfavorite(
    Account account,
    (Object, int) target,
  ) => send('unfavorite:${target.$1}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LoginAccount account(String csrf) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  late ProviderContainer container;
  late FakeFavorites repository;
  late FavoriteLibrary library;
  late Account original;
  const query = FavoriteQuery(
    owner: Object(),
    kind: FavoriteKind.detail,
    mediaId: 7,
  );
  const folders = FavoriteQuery(owner: Object(), kind: FavoriteKind.folders);
  setUpAll(() async {
    GStorage.setting = await Hive.openBox(
      'favorite-library-settings',
      bytes: Uint8List(0),
    );
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
  });
  tearDownAll(() => GStorage.setting.close());
  setUp(() {
    original = account('first');
    Accounts.accountMode[AccountType.main.index] = original;
    repository = FakeFavorites();
    library = FavoriteLibrary(repository);
    container = ProviderContainer(
      overrides: [favoriteLibraryProvider.overrideWithValue(library)],
    );
  });
  tearDown(() async {
    container.dispose();
    await library.close();
  });
  Future<FavoriteState> keep(FavoriteQuery query) {
    container.listen(favoriteFeedProvider(query), (_, _) {});
    return container.read(favoriteFeedProvider(query).future);
  }

  test('同 UID 新凭据重建查询，旧响应不覆盖新账号；释放移除订阅', () async {
    final pending = Completer<FeedPage<Object, FavoriteMetadata>>();
    repository.read = (_, _) => pending.future;
    container.listen(favoriteFeedProvider(query), (_, _) {});
    final old = container.read(favoriteFeedProvider(query).future);
    repository.read = (_, _) async =>
        FeedPage([favoriteVideo(9)], metadata: const FavoriteMetadata());
    final replacement = account('replacement');
    Accounts.replaceCredentials(replacement);
    final current = await container.read(favoriteFeedProvider(query).future);
    expect(current.account, same(replacement));
    pending.complete(
      FeedPage([favoriteVideo(1)], metadata: const FavoriteMetadata()),
    );
    await old;
    expect(
      (container.read(favoriteFeedProvider(query)).value!.items.single
              as FavDetailItemModel)
          .id,
      9,
    );
    expect(repository.requests.map((value) => value.account), [
      original,
      replacement,
    ]);
    container.dispose();
    Accounts.replaceCredentials(account('closed'));
    expect(repository.requests, hasLength(2));
    container = ProviderContainer();
  });
  test('关键词、排序和页面身份生成独立查询', () async {
    final a = FavoriteQuery(
      owner: query.owner,
      kind: FavoriteKind.detail,
      mediaId: 7,
      keyword: '旧',
    );
    final b = FavoriteQuery(
      owner: query.owner,
      kind: FavoriteKind.detail,
      mediaId: 7,
      keyword: '新',
    );
    final first = await keep(a), second = await keep(b);
    expect(first.source, isNot(same(second.source)));
    expect(repository.requests.map((value) => value.query.keyword), ['旧', '新']);
  });
  test('分页互斥、去重、失败保留游标，刷新淘汰旧分页', () async {
    repository.read = (_, cursor) async => FeedPage(
      [favoriteVideo(1)],
      metadata: const FavoriteMetadata(),
      next: 2,
    );
    await keep(query);
    final feed = container.read(favoriteFeedProvider(query).notifier);
    repository.read = (_, _) => Future.error(const Error('失败'));
    await feed.loadMore();
    expect(container.read(favoriteFeedProvider(query)).value!.next, 2);
    final pending = Completer<FeedPage<Object, FavoriteMetadata>>();
    repository.read = (_, cursor) => cursor == null
        ? Future.value(
            FeedPage([favoriteVideo(8)], metadata: const FavoriteMetadata()),
          )
        : pending.future;
    final more = feed.loadMore(retry: true);
    await feed.loadMore(retry: true);
    expect(repository.requests, hasLength(3));
    await feed.refresh();
    pending.complete(
      FeedPage([favoriteVideo(2)], metadata: const FavoriteMetadata()),
    );
    await more;
    expect(
      (container.read(favoriteFeedProvider(query)).value!.items.single
              as FavDetailItemModel)
          .id,
      8,
    );
  });
  test('首屏过滤空页继续补位，重复游标有界结束', () async {
    repository.read = (_, cursor) async => FeedPage(
      cursor == null ? [] : [favoriteVideo(2)],
      metadata: const FavoriteMetadata(),
      next: cursor == null ? 2 : null,
    );
    expect((await keep(query)).items, hasLength(1));
    repository.read = (_, _) async =>
        FeedPage([], metadata: const FavoriteMetadata(), next: 2);
    final result = await container.refresh(favoriteFeedProvider(query).future);
    expect(result.items, isEmpty);
    expect(result.next, isNull);
    expect(repository.requests, hasLength(4));
  });
  test('待确认不重读；确认后同步列表、详情、搜索和面板并拒绝旧选择', () async {
    final detail = await keep(query);
    await keep(folders);
    const search = FavoriteQuery(
      owner: Object(),
      kind: FavoriteKind.detail,
      mediaId: 7,
      keyword: 'test',
    );
    await keep(search);
    final membershipQuery = (owner: Object(), target: (42 as Object, 2));
    var membershipReads = 0;
    repository.readMembership = () async {
      membershipReads++;
      return Success(FavFolderData(list: repository.available));
    };
    container.listen(favoriteMembershipProvider(membershipQuery), (_, _) {});
    final membership = await container.read(
      favoriteMembershipProvider(membershipQuery).future,
    );
    repository.mutation = () async => const UnknownResult();
    expect(
      await library.folderAction(original, 7, FolderAction.clean),
      isA<UnknownResult>(),
    );
    await container.read(favoriteFeedProvider(query).future);
    expect(repository.requests, hasLength(3));
    expect(membershipReads, 1);
    repository.requests.clear();
    repository
      ..read = (query, _) async =>
          FeedPage(
              switch (query.kind) {
                FavoriteKind.folders => [FavFolderInfo(id: 2)],
                _ => [favoriteVideo(query.keyword.isEmpty ? 8 : 9)],
              },
              metadata: const FavoriteMetadata(),
            )
            ..readMembership = () async {
              membershipReads++;
              return Success(
                FavFolderData(list: [FavFolderInfo(id: 2, favState: 1)]),
              );
            };
    repository.mutation = null;
    expect(
      await library.folderAction(original, 7, FolderAction.clean),
      isA<Success>(),
    );
    expect(
      (await container.read(favoriteFeedProvider(query).future)).items.single,
      isA<FavDetailItemModel>().having((item) => item.id, 'id', 8),
    );
    expect(
      (await container.read(favoriteFeedProvider(folders).future)).items.single,
      isA<FavFolderInfo>().having((item) => item.id, 'id', 2),
    );
    expect(
      (await container.read(favoriteFeedProvider(search).future)).items.single,
      isA<FavDetailItemModel>().having((item) => item.id, 'id', 9),
    );
    expect(
      (await container.read(favoriteMembershipProvider(membershipQuery).future))
          .selected,
      {2},
    );
    expect(
      repository.requests.map((request) => request.query),
      unorderedEquals([query, folders, search]),
    );
    expect(membershipReads, 2);
    expect(
      await container.read(favoriteFeedProvider(query).notifier).remove(
        detail,
        [detail.items.first],
      ),
      isA<Error>(),
    );
    expect(await library.select(membership, {2}), isA<Error>());
    expect(repository.writes, ['folder:7:clean', 'folder:7:clean']);
  });
  test('删除与编辑共用账号锁；刷新和换凭据拒绝旧选择', () async {
    final source = await keep(query);
    final feed = container.read(favoriteFeedProvider(query).notifier);
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    final remove = feed.remove(source, [source.items.first]);
    expect(
      await library.folderAction(original, 7, FolderAction.delete),
      isA<Error>(),
    );
    expect(repository.writes, hasLength(1));
    pending.complete(const UnknownResult());
    await remove;
    await feed.refresh();
    expect(await feed.remove(source, source.items), isA<Error>());
    expect(repository.writes, hasLength(1));
    final latest = container.read(favoriteFeedProvider(query)).value!;
    Accounts.replaceCredentials(account('new'));
    expect(await feed.remove(latest, latest.items), isA<Error>());
  });
  test('移动与复制固定本次选择，倒序资源并统一刷新计数；同源目标不发送', () async {
    final source = await keep(query);
    final feed = container.read(favoriteFeedProvider(query).notifier);
    expect(await feed.transfer(source, source.items, 7, false), isA<Error>());
    expect(await feed.transfer(source, source.items, 8, false), isA<Success>());
    expect(repository.writes.single, 'transfer:7:8:false:2:2,1:2');
    expect(source.metadata.folder!.mediaCount, 2);
    expect(source.items, hasLength(2));
    expect(feed.isCurrent(source), isFalse);
  });
  test('笔记标识缺失和非所有者收藏夹不发删除请求', () async {
    const notes = FavoriteQuery(owner: Object(), kind: FavoriteKind.note);
    repository.read = (_, _) async => FeedPage([
      FavNoteItemModel(title: '无标识'),
    ], metadata: const FavoriteMetadata());
    final note = await keep(notes);
    expect(
      await container
          .read(favoriteFeedProvider(notes).notifier)
          .remove(note, note.items),
      isA<Error>(),
    );
    repository.read = (_, _) async => FeedPage([
      favoriteVideo(1),
    ], metadata: FavoriteMetadata(folder: FavFolderInfo(mid: 8)));
    final detail = await keep(query);
    expect(
      await container
          .read(favoriteFeedProvider(query).notifier)
          .remove(detail, detail.items),
      isA<Error>(),
    );
    expect(repository.writes, isEmpty);
  });
  test('追番迁移使所有分组失效，待确认不清空来源', () async {
    const a = FavoriteQuery(
          owner: Object(),
          kind: FavoriteKind.pgc,
          type: 1,
          status: 1,
        ),
        b = FavoriteQuery(
          owner: Object(),
          kind: FavoriteKind.pgc,
          type: 1,
          status: 3,
        );
    repository.read = (_, _) async => FeedPage([
      FavPgcItemModel(seasonId: 1),
    ], metadata: const FavoriteMetadata());
    final first = await keep(a), second = await keep(b);
    final feed = container.read(favoriteFeedProvider(a).notifier);
    repository.mutation = () async => const UnknownResult();
    expect(await feed.pgc(first, first.items, 3), isA<UnknownResult>());
    expect(container.read(favoriteFeedProvider(a)).value, same(first));
    repository.mutation = null;
    expect(await feed.pgc(first, first.items, 3), isA<Success>());
    expect(
      (await container.read(favoriteFeedProvider(b).future)).source,
      isNot(same(second.source)),
    );
  });
  test('快速收藏在查询期间换目标停止后续写入，查询失败释放账号锁', () async {
    final pending = Completer<LoadingState<FavFolderData>>();
    repository.readMembership = () => pending.future;
    var current = true;
    final operation = library.quick(original, (
      42,
      2,
    ), isCurrent: () => current);
    current = false;
    pending.complete(Success(FavFolderData(list: repository.available)));
    expect(await operation, isA<Error>());
    expect(repository.writes, isEmpty);
    repository.readMembership = () async => const Error('查询失败');
    expect(
      await library.quick(original, (42, 2), isCurrent: () => true),
      isA<Error>(),
    );
    repository.readMembership = null;
    expect(
      await library.quick(original, (42, 2), isCurrent: () => true),
      isA<Success>(),
    );
    expect(repository.writes, ['unfavorite:42']);
  });
  test('收藏面板只提交勾选差量，不修改确认模型；失败可重试', () async {
    final source = await library.membership(original, (42, 2));
    repository.mutation = () async => const UnknownResult();
    expect(await library.select(source, {2}), isA<UnknownResult>());
    expect(source.selected, {1});
    expect(source.folders.first.mediaCount, 1);
    expect(repository.writes.single, 'video:42:2:2:1');
    repository.mutation = null;
    expect((await library.select(source, {2})).data, isTrue);
    expect(source.selected, {1});
  });
  test('删除后从新偏移边界重读并去重，数量来自确认查询', () async {
    var removed = false;
    repository.read = (_, cursor) async => FeedPage(
      [
        if (cursor == null) ...[
          favoriteVideo(removed ? 2 : 1),
          favoriteVideo(removed ? 3 : 2),
        ] else ...[
          favoriteVideo(3),
          favoriteVideo(4),
        ],
      ],
      metadata: FavoriteMetadata(
        folder: FavFolderInfo(mid: 1, mediaCount: removed ? 3 : 4),
      ),
      next: cursor == null ? 2 : null,
    );
    final source = await keep(query);
    final feed = container.read(favoriteFeedProvider(query).notifier);
    repository.mutation = () async {
      removed = true;
      return const Success(null);
    };
    expect(await feed.remove(source, [source.items.first]), isA<Success>());
    final current = await container.read(favoriteFeedProvider(query).future);
    expect(current.metadata.folder!.mediaCount, 3);
    await feed.loadMore();
    expect(
      container.read(favoriteFeedProvider(query)).value!.items.map(favoriteKey),
      [(2, 2), (2, 3), (2, 4)],
    );
    expect(source.metadata.folder!.mediaCount, 4);
  });
  Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  for (final playAll in [false, true]) {
    testWidgets('搜索首个命中项从自身继续播放，连续播放偏好为 $playAll', (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await GStorage.setting.put(SettingBoxKey.enablePlayAll, playAll);
      repository.read = (query, _) async => FeedPage(
        query.keyword == '命中'
            ? [
                favoriteVideo(75)
                  ..ugc = Ugc(firstCid: 125)
                  ..bvid = IdUtils.av2bv(75),
              ]
            : [favoriteVideo(1)],
        metadata: FavoriteMetadata(
          folder: FavFolderInfo(mid: 1, title: '收藏夹', mediaCount: 100),
        ),
      );
      Map? played;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: GetMaterialApp(
            home: Scaffold(
              body: TextButton(
                onPressed: () =>
                    Get.toNamed('/favSearch', arguments: {'mediaId': 7}),
                child: const Text('打开搜索'),
              ),
            ),
            getPages: [
              GetPage(
                name: '/favSearch',
                page: () => const FavoriteDetailPage(search: true),
              ),
              GetPage(
                name: '/videoV',
                page: () {
                  played = Get.arguments as Map;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('打开搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '命中');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频 75'));
      await tester.pumpAndSettle();
      expect(played, containsPair('cid', 125));
      expect(played, containsPair('sourceType', SourceType.fav));
      expect(played, containsPair('mediaId', 7));
      expect(played, containsPair('oid', 75));
      expect(played, containsPair('isContinuePlaying', true));
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('收藏详情待确认保留选择，确认成功刷新清除选择', (tester) async {
    await keep(query);
    await mount(tester, const FavoritePanel(query: query));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('视频 1'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    repository.mutation = () async => const UnknownResult();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.textContaining('操作结果待确认'), findsOneWidget);
    repository.mutation = null;
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsNothing);
    expect(repository.removals.last, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('排序保护默认收藏夹，失败保留草稿，成功仅关闭所属页面', (tester) async {
    final source = await keep(folders);
    await mount(tester, FavoriteSortPage(query: folders, source: source));
    await tester.pumpAndSettle();
    final reorder = tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!;
    reorder(0, 1);
    reorder(1, 2);
    await tester.pump();
    repository.mutation = () async => const UnknownResult();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(repository.writes.single, 'sort:null:1,3,2');
    expect(source.items.map(favoriteKey), [1, 2, 3]);
    expect(find.textContaining('操作结果待确认'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('面板勾选保留本地草稿，确认成功向播放器回调一次', (tester) async {
    final query = (owner: Object(), target: (42 as Object, 2));
    container.listen(favoriteMembershipProvider(query), (_, _) {});
    await container.read(favoriteMembershipProvider(query).future);
    final saved = <bool>[];
    await mount(
      tester,
      FavoriteSelectionPanel(
        target: (42, 2),
        isCurrent: () => true,
        onSaved: saved.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏夹 2'));
    await tester.pump();
    repository.mutation = () async => const UnknownResult();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.textContaining('操作结果待确认'), findsOneWidget);
    repository.mutation = null;
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(saved, [true]);
    expect(repository.writes, ['video:42:2:2:', 'video:42:2:2:']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('移动待确认保留选择与原数量，重试成功关闭自己的弹窗', (tester) async {
    final source = await keep(query);
    await mount(
      tester,
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => transferFavorites(context, ref, query, source, [
            source.items.first,
          ], false),
          child: const Text('移动'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏夹 2'));
    await tester.pump();
    repository.mutation = () async => const UnknownResult();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.textContaining('操作结果待确认'), findsOneWidget);
    expect(source.items, hasLength(2));
    expect(source.metadata.folder!.mediaCount, 2);
    repository.mutation = null;
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.writes, [
      'transfer:7:2:false:1:2',
      'transfer:7:2:false:1:2',
    ]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('排序被新页面覆盖时保留失败结果，返回后可重试', (tester) async {
    final source = await keep(folders);
    await mount(tester, FavoriteSortPage(query: folders, source: source));
    await tester.pumpAndSettle();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(1, 2);
    await tester.pump();
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    await tester.tap(find.text('完成'));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator))
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('新页面')),
        ),
      );
    await tester.pumpAndSettle();
    pending.complete(const UnknownResult());
    await tester.pumpAndSettle();
    expect(find.text('新页面'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('提交中'), findsNothing);
    expect(find.textContaining('操作结果待确认'), findsOneWidget);
    repository.mutation = null;
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(repository.writes, ['sort:null:1,3,2', 'sort:null:1,3,2']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('离开排序后的迟到成功刷新查询，保留新页面与原草稿', (tester) async {
    final source = await keep(query);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('根页面')),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => FavoriteSortPage(query: query, source: source),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 1);
    await tester.pump();
    final pending = Completer<LoadingState<void>>();
    repository.mutation = () => pending.future;
    await tester.tap(find.text('完成'));
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('新页面')),
      ),
    );
    await tester.pumpAndSettle();
    pending.complete(const Success(null));
    await tester.pumpAndSettle();
    expect(find.text('新页面'), findsOneWidget);
    expect(source.items.map(favoriteKey), [(2, 1), (2, 2)]);
    expect(
      (await container.read(favoriteFeedProvider(query).future)).source,
      isNot(same(source.source)),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
