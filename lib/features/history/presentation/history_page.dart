import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/features/content_library/presentation/feed_view.dart';
import 'package:pili_aurora_next/features/content_library/presentation/operation_dialog.dart';
import 'package:pili_aurora_next/features/history/application/history_library.dart';
import 'package:pili_aurora_next/features/history/domain/list.dart';
import 'package:pili_aurora_next/features/history/presentation/history_item.dart';
import 'package:pili_aurora_next/services/account_providers.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.search = false, this.type});
  final bool search;
  final String? type;
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _owner = Object();
  final _input = TextEditingController();
  String _keyword = '';
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  HistoryQuery query(String type) =>
      (owner: _owner, type: type, keyword: _keyword, search: widget.search);
  @override
  Widget build(BuildContext context) {
    final provider = historyFeedProvider(query(widget.type ?? 'all'));
    final value = ref.watch(provider);
    final pause = ref.watch(historyPauseProvider);
    final account = ref.watch(historyAccountProvider);
    final library = ref.read(historyLibraryProvider);
    final tabs = identical(value.value?.account, account)
        ? value.value!.metadata
        : [];
    final types = [
      'all',
      for (final tab in tabs)
        if (tab.type != null && tab.type != 'all') tab.type!,
    ];
    final names = [
      '全部',
      for (final tab in tabs)
        if (tab.type != null && tab.type != 'all') tab.name ?? tab.type!,
    ];
    Widget panel(String type) => HistoryPanel(query: query(type));
    final showTabs = !widget.search && widget.type == null && types.length > 1;
    return DefaultTabController(
      key: ValueKey(types.join(',')),
      length: showTabs ? types.length : 1,
      child: Scaffold(
        appBar: AppBar(
          title: widget.search
              ? TextField(
                  controller: _input,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '搜索观看记录'),
                  onSubmitted: (value) =>
                      setState(() => _keyword = value.trim()),
                )
              : const Text('观看记录'),
          actions: [
            if (!widget.search)
              IconButton(
                tooltip: '搜索',
                onPressed: () => Get.toNamed('/historySearch'),
                icon: const Icon(Icons.search),
              ),
            PopupMenuButton<int>(
              onSelected: (action) async {
                if (action == 0) {
                  if (pause.isLoading ||
                      pause.hasError ||
                      pause.value == null) {
                    return;
                  }
                  final target = !pause.value!;
                  await libraryConfirm(
                    context,
                    title: target ? '暂停观看记录？' : '恢复观看记录？',
                    isCurrent: () => mounted && library.owns(account),
                    ownsResult: () => mounted && library.owns(account),
                    submit: () =>
                        ref.read(historyPauseProvider.notifier).set(target),
                  );
                } else {
                  await libraryConfirm(
                    context,
                    title: '清空观看记录？',
                    isCurrent: () => mounted && library.owns(account),
                    ownsResult: () => mounted && library.owns(account),
                    submit: () => library.clear(account),
                  );
                }
              },
              itemBuilder: (_) => [
                AppPopupMenuItem(
                  value: 0,
                  enabled: !pause.isLoading && !pause.hasError,
                  child: Text(pause.value == true ? '恢复观看记录' : '暂停观看记录'),
                ),
                const AppPopupMenuItem(value: 1, child: Text('清空观看记录')),
              ],
            ),
          ],
          bottom: showTabs
              ? TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final name in names) Tab(text: name)],
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (!pause.isLoading && !pause.hasError && pause.value == true)
                const MaterialBanner(
                  content: Text('历史记录功能已关闭'),
                  actions: [SizedBox.shrink()],
                ),
              if (pause.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(historyPauseProvider),
                  child: const Text('历史状态读取失败，点击重试'),
                ),
              Expanded(
                child: showTabs
                    ? TabBarView(
                        children: [for (final type in types) panel(type)],
                      )
                    : panel(widget.type ?? 'all'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryPanel extends ConsumerStatefulWidget {
  const HistoryPanel({super.key, required this.query});
  final HistoryQuery query;
  @override
  ConsumerState<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends ConsumerState<HistoryPanel> {
  final _selected = <Object>{};
  Object? _source;
  Object keyOf(HistoryItemModel item) => (item.history.business, item.kid);
  void _toggle(HistoryItemModel item) => setState(() {
    final key = keyOf(item);
    if (!_selected.add(key)) _selected.remove(key);
  });
  Future<void> _remove(
    HistoryState data,
    Iterable<HistoryItemModel> items,
  ) async {
    final selected = items.toList();
    final notifier = ref.read(historyFeedProvider(widget.query).notifier);
    final library = ref.read(historyLibraryProvider);
    await libraryConfirm(
      context,
      title: '删除所选观看记录？',
      isCurrent: () => mounted && notifier.isCurrent(data),
      ownsResult: () => mounted && library.owns(data.account),
      submit: () => notifier.remove(data, selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = historyFeedProvider(widget.query);
    final value = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final data = !value.isLoading && !value.hasError ? value.value : null;
    if (!identical(_source, data?.source)) {
      _source = data?.source;
      _selected.clear();
    }
    final items = data?.items ?? <HistoryItemModel>[];
    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Column(
        children: [
          Row(
            children: [
              if (_selected.isNotEmpty) ...[
                IconButton(
                  tooltip: '取消选择',
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                ),
                Text('已选 ${_selected.length}'),
                TextButton(
                  onPressed: () =>
                      setState(() => _selected.addAll(items.map(keyOf))),
                  child: const Text('全选'),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: () => _remove(
                    data!,
                    items.where((item) => _selected.contains(keyOf(item))),
                  ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ] else
                TextButton(
                  onPressed:
                      data == null || !items.any((item) => item.progress == -1)
                      ? null
                      : () => _remove(
                          data,
                          items.where((item) => item.progress == -1),
                        ),
                  child: const Text('删除已看记录'),
                ),
            ],
          ),
          Expanded(
            child: LibraryFeedView(
              value: value,
              refresh: notifier.refresh,
              loadMore: notifier.loadMore,
              itemBuilder: (context, item, _) => HistoryItem(
                item: item,
                selecting: _selected.isNotEmpty,
                selected: _selected.contains(keyOf(item)),
                onSelect: () => _toggle(item),
                isCurrent: () =>
                    mounted &&
                    _selected.isEmpty &&
                    data != null &&
                    notifier.isCurrent(data),
                onDelete: (_, _) => _remove(data!, [item]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
