import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_panel.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_sort_page.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});
  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage>
    with SingleTickerProviderStateMixin {
  final _owner = Object();
  late final _tabs = TabController(
    length: 7,
    vsync: this,
    initialIndex: (Get.arguments is int ? Get.arguments as int : 0).clamp(0, 6),
  )..addListener(_changed);
  FavoriteQuery get _folders =>
      FavoriteQuery(owner: _owner, kind: FavoriteKind.folders);
  void _changed() => setState(() {});
  @override
  void dispose() {
    _tabs
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(favoriteFeedProvider(_folders));
    final data = !value.isLoading && !value.hasError ? value.value : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: _tabs.index == 0
            ? [
                IconButton(
                  tooltip: '新建收藏夹',
                  icon: const Icon(Icons.add),
                  onPressed: () => Get.toNamed('/createFav'),
                ),
                IconButton(
                  tooltip: '收藏夹排序',
                  icon: const Icon(Icons.sort),
                  onPressed:
                      data == null || data.next != null || data.items.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                FavoriteSortPage(query: _folders, source: data),
                          ),
                        ),
                ),
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: data == null || data.items.isEmpty
                      ? null
                      : () {
                          final folder = data.items.first as FavFolderInfo;
                          Get.toNamed(
                            '/favSearch',
                            arguments: {'mediaId': folder.id, 'type': 1},
                          );
                        },
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final name in ['视频', '追番', '追剧', '专栏', '笔记', '话题', '课堂'])
              Tab(text: name),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: [
            FavoritePanel(query: _folders),
            const FavoriteCategoryTabs(kind: FavoriteKind.pgc, type: 1),
            const FavoriteCategoryTabs(kind: FavoriteKind.pgc, type: 2),
            FavoritePanel(
              query: FavoriteQuery(owner: _owner, kind: FavoriteKind.article),
            ),
            const FavoriteCategoryTabs(kind: FavoriteKind.note),
            FavoritePanel(
              query: FavoriteQuery(owner: _owner, kind: FavoriteKind.topic),
            ),
            FavoritePanel(
              query: FavoriteQuery(owner: _owner, kind: FavoriteKind.cheese),
            ),
          ],
        ),
      ),
    );
  }
}

class FavoriteCategoryTabs extends StatefulWidget {
  const FavoriteCategoryTabs({super.key, required this.kind, this.type = 0});
  final FavoriteKind kind;
  final int type;
  @override
  State<FavoriteCategoryTabs> createState() => _FavoriteCategoryTabsState();
}

class _FavoriteCategoryTabsState extends State<FavoriteCategoryTabs>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pgc = widget.kind == FavoriteKind.pgc;
    final labels = pgc ? ['想看', '在看', '看过'] : ['未发布笔记', '公开笔记'];
    return DefaultTabController(
      length: labels.length,
      initialIndex: pgc ? 1 : 0,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final label in labels) Tab(text: label)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (var i = 0; i < labels.length; i++)
                  FavoritePanel(
                    query: FavoriteQuery(
                      owner: _owner,
                      kind: widget.kind,
                      type: widget.type,
                      status: i + 1,
                      published: i == 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
