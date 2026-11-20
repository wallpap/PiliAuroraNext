import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView;
import 'package:pili_aurora_next/common/widgets/tab_activity.dart';
import 'package:pili_aurora_next/common/widgets/view_safe_area.dart';
import 'package:pili_aurora_next/features/community/application/comments/reply_search.dart';
import 'package:pili_aurora_next/features/community/domain/reply_search.dart';
import 'package:pili_aurora_next/pages/video/reply_search_item/child/view.dart';
import 'package:pili_aurora_next/common/widgets/extensions/scroll_controller_ext.dart';
import 'package:material_ui/material_ui.dart';

class ReplySearchPage extends ConsumerStatefulWidget {
  const ReplySearchPage({
    super.key,
    required this.type,
    required this.oid,
  });

  final int type;
  final int oid;

  @override
  ConsumerState<ReplySearchPage> createState() => _ReplySearchPageState();
}

class _ReplySearchPageState extends ConsumerState<ReplySearchPage>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  final _input = TextEditingController();
  final _scrolls = [ScrollController(), ScrollController()];
  Object _submission = Object();
  String _keyword = '';
  late final _tabs = TabController(length: _scrolls.length, vsync: this);

  void _submit() {
    for (final scroll in _scrolls) {
      scroll.jumpToTop();
    }
    setState(() {
      _keyword = _input.text;
      _submission = Object();
    });
  }

  void _clear() {
    if (_input.text.isEmpty) {
      Navigator.of(context).pop();
    } else {
      _input.clear();
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _focus.dispose();
    _input.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queries = [
      for (final kind in ReplySearchType.values)
        (
          submission: _submission,
          type: widget.type,
          oid: widget.oid,
          kind: kind,
          keyword: _keyword,
        ),
    ];
    for (final query in queries) {
      ref.watch(replySearchProvider(query).notifier);
    }
    return SimpleScaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: _submit,
            icon: const Icon(Icons.search, size: 22),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          focusNode: _focus,
          controller: _input,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: '搜索',
            visualDensity: .standard,
            border: InputBorder.none,
            suffixIcon: IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.clear, size: 22),
              onPressed: _clear,
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      body: ViewSafeArea(
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: '视频'),
                Tab(text: '专栏'),
              ],
              onTap: (index) {
                if (!_tabs.indexIsChanging) {
                  _scrolls[index].animToTop();
                }
              },
            ),
            Expanded(
              child: tabBarView(
                controller: _tabs,
                children: [
                  for (final (index, query) in queries.indexed)
                    TabActivity(
                      controller: _tabs,
                      index: index,
                      child: ReplySearchChildPage(
                        query: query,
                        scroll: _scrolls[index],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
