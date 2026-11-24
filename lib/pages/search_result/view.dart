import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/search/domain/filters/search_type.dart';
import 'package:pili_aurora_next/pages/search_panel/all/view.dart';
import 'package:pili_aurora_next/pages/search_panel/article/view.dart';
import 'package:pili_aurora_next/pages/search_panel/live/view.dart';
import 'package:pili_aurora_next/pages/search_panel/pgc/view.dart';
import 'package:pili_aurora_next/pages/search_panel/user/view.dart';
import 'package:pili_aurora_next/pages/search_panel/video/view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage>
    with SingleTickerProviderStateMixin {
  static const _overflowCount = 100;

  final String _keyword = Get.parameters['keyword'] ?? '';
  final _visibleCounts = List<int?>.filled(SearchType.values.length, null);
  final _countsRevision = ValueNotifier(0);
  final _topSignals = List.generate(
    SearchType.values.length,
    (_) => ValueNotifier(0),
  );
  late TabController _tabController;
  final Object _tag = Object();
  final bool _isFromSearch = Get.arguments?['fromSearch'] ?? false;
  final void Function(int)? _onIndexChanged = Get.arguments?['onIndexChanged'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      vsync: this,
      initialIndex: Get.arguments?['initIndex'] ?? 0,
      length: SearchType.values.length,
    );

    if (_isFromSearch) _tabController.addListener(listener);
  }

  void listener() => _onIndexChanged?.call(_tabController.index);

  @override
  void dispose() {
    _tabController
      ..removeListener(listener)
      ..dispose();
    _countsRevision.dispose();
    for (final signal in _topSignals) {
      signal.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        shape: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        title: GestureDetector(
          onTap: () {
            if (_isFromSearch) {
              Get.back(result: true);
            } else {
              Get.offNamed(
                '/search',
                parameters: {'text': _keyword},
              );
            }
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: double.infinity,
            child: Text(
              _keyword,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
            ),
          ),
        ),
      ),
      body: ViewSafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder(
              valueListenable: _countsRevision,
              builder: (context, _, _) => TabBar(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                controller: _tabController,
                tabs: [
                  for (final item in SearchType.values)
                    Tab(text: _tabLabel(item)),
                ],
                isScrollable: true,
                indicatorWeight: 0,
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 8,
                ),
                indicator: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: theme.colorScheme.onSecondaryContainer,
                labelStyle:
                    TabBarTheme.of(
                      context,
                    ).labelStyle?.copyWith(fontSize: 13) ??
                    const TextStyle(fontSize: 13),
                dividerColor: Colors.transparent,
                dividerHeight: 0,
                unselectedLabelColor: theme.colorScheme.outline,
                tabAlignment: TabAlignment.start,
                onTap: (index) {
                  if (!_tabController.indexIsChanging) {
                    _topSignals[index].value++;
                  }
                },
              ),
            ),
            Expanded(
              child: tabBarView(
                controller: _tabController,
                children: SearchType.values.map(_buildPanel).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(SearchType item) {
    final count = _visibleCounts[item.index];
    if (count == null) return item.label;
    return '${item.label} ${count == _overflowCount ? '99+' : count}';
  }

  Widget _buildPanel(SearchType item) {
    final index = item.index;
    final toTop = _topSignals[index];
    void onCount(int? count) {
      final visibleCount = count != null && count > _overflowCount
          ? _overflowCount
          : count;
      if (!mounted || _visibleCounts[index] == visibleCount) return;
      _visibleCounts[index] = visibleCount;
      _countsRevision.value++;
    }

    return switch (item) {
      .all => SearchAllPanel(
        tag: _tag,
        toTop: toTop,
        onCount: onCount,
        searchType: item,
        keyword: _keyword,
      ),
      .video => SearchVideoPanel(
        tag: _tag,
        toTop: toTop,
        onCount: onCount,
        searchType: item,
        keyword: _keyword,
      ),
      .media_bangumi || .media_ft => SearchPgcPanel(
        tag: _tag,
        toTop: toTop,
        onCount: onCount,
        searchType: item,
        keyword: _keyword,
      ),
      .live_room => SearchLivePanel(
        tag: _tag,
        toTop: toTop,
        onCount: onCount,
        searchType: item,
        keyword: _keyword,
      ),
      .bili_user => SearchUserPanel(
        tag: _tag,
        toTop: toTop,
        onCount: onCount,
        searchType: item,
        keyword: _keyword,
      ),
      .article => SearchArticlePanel(
        tag: _tag,
        toTop: toTop,
        onCount: onCount,
        searchType: item,
        keyword: _keyword,
      ),
    };
  }
}
