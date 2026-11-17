import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/features/content_library/presentation/feed_view.dart';
import 'package:pili_aurora_next/features/content_library/presentation/operation_dialog.dart';
import 'package:pili_aurora_next/features/watch_later/application/later_library.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/features/watch_later/domain/list.dart';
import 'package:pili_aurora_next/features/watch_later/presentation/video_card.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/features/content_library/application/library_preferences.dart';

class LaterPage extends ConsumerStatefulWidget {
  const LaterPage({super.key, this.search = false});
  final bool search;
  @override
  ConsumerState<LaterPage> createState() => _LaterPageState();
}

class _LaterPageState extends ConsumerState<LaterPage>
    with SingleTickerProviderStateMixin {
  final _owner = Object();
  final _input = TextEditingController();
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(_changed);
  final _ascending = [false, false];
  String _keyword = '';
  void _changed() {
    if (mounted) setState(() {});
  }

  LaterQuery query(int index) => (
    owner: _owner,
    viewed: index == 0 ? 0 : 2,
    keyword: _keyword,
    asc: _ascending[index],
  );
  @override
  void dispose() {
    _tabs.removeListener(_changed);
    _tabs.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.search ? 0 : _tabs.index;
    final values = [
      for (var i = 0; i < (widget.search ? 1 : 2); i++)
        ref.watch(laterFeedProvider(query(i))),
    ];
    final current = values[index];
    final playlist = ref.watch(
      laterFeedProvider((
        owner: _owner,
        viewed: 0,
        keyword: '',
        asc: _ascending[index],
      )),
    );
    final playlistCount = !playlist.isLoading && !playlist.hasError
        ? playlist.value?.metadata
        : null;
    return Scaffold(
      appBar: AppBar(
        title: widget.search
            ? TextField(
                controller: _input,
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜索稍后再看'),
                onSubmitted: (text) => setState(() => _keyword = text.trim()),
              )
            : const Text('稍后再看'),
        actions: [
          if (!widget.search)
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => Get.toNamed('/laterSearch'),
            ),
          PopupMenuButton<bool>(
            tooltip: '排序',
            initialValue: _ascending[index],
            onSelected: (value) => setState(() => _ascending[index] = value),
            itemBuilder: (_) => const [
              AppPopupMenuItem(value: false, child: Text('最近添加')),
              AppPopupMenuItem(value: true, child: Text('最早添加')),
            ],
          ),
          if (!widget.search)
            PopupMenuButton<int>(
              tooltip: '清空',
              onSelected: (type) async {
                if (current.isLoading ||
                    current.hasError ||
                    current.value == null) {
                  return;
                }
                final snapshot = current.value!;
                final notifier = ref.read(
                  laterFeedProvider(query(index)).notifier,
                );
                final library = ref.read(laterLibraryProvider);
                await libraryConfirm(
                  context,
                  title: switch (type) {
                    1 => '清空失效视频？',
                    2 => '清空已看完视频？',
                    _ => '清空稍后再看？',
                  },
                  isCurrent: () => mounted && notifier.isCurrent(snapshot),
                  ownsResult: () => mounted && library.owns(snapshot.account),
                  submit: () => library.clear(
                    type == 0 ? null : type,
                    account: snapshot.account,
                  ),
                );
              },
              itemBuilder: (_) => const [
                AppPopupMenuItem(value: 1, child: Text('清空失效')),
                AppPopupMenuItem(value: 2, child: Text('清空看完')),
                AppPopupMenuItem(value: 0, child: Text('清空全部')),
              ],
            ),
        ],
        bottom: widget.search
            ? null
            : TabBar(
                controller: _tabs,
                tabs: [
                  for (var i = 0; i < 2; i++)
                    Tab(
                      text:
                          '${i == 0 ? '全部' : '未看完'}${!values[i].isLoading && !values[i].hasError && values[i].value != null ? '(${values[i].value!.metadata})' : ''}',
                    ),
                ],
              ),
      ),
      body: SafeArea(
        top: false,
        child: widget.search
            ? LaterPanel(query: query(0), playlistCount: playlistCount)
            : TabBarView(
                controller: _tabs,
                children: [
                  for (var i = 0; i < 2; i++)
                    LaterPanel(
                      query: query(i),
                      active: i == index,
                      playlistCount: playlistCount,
                    ),
                ],
              ),
      ),
    );
  }
}

class LaterPanel extends ConsumerStatefulWidget {
  const LaterPanel({
    super.key,
    required this.query,
    this.active = true,
    this.playlistCount,
  });
  final LaterQuery query;
  final bool active;
  final int? playlistCount;
  @override
  ConsumerState<LaterPanel> createState() => _LaterPanelState();
}

class _LaterPanelState extends ConsumerState<LaterPanel> {
  final _selected = <int>{};
  Object? _source;
  bool _busy = false;
  void _toggle(LaterItemModel item) {
    if (_busy || item.aid == null) return;
    setState(() {
      if (!_selected.add(item.aid!)) _selected.remove(item.aid);
    });
  }

  Future<void> _remove(LaterState data, Iterable<LaterItemModel> items) async {
    final selected = items.toList();
    final notifier = ref.read(laterFeedProvider(widget.query).notifier);
    await libraryConfirm(
      context,
      title: '移除所选稍后再看？',
      isCurrent: () => mounted && notifier.isCurrent(data),
      ownsResult: () =>
          mounted && ref.read(laterLibraryProvider).owns(data.account),
      submit: () => notifier.remove(data, selected),
    );
  }

  Future<void> _transfer(LaterState data, bool copy) async {
    final notifier = ref.read(laterFeedProvider(widget.query).notifier);
    final library = ref.read(laterLibraryProvider);
    final ids = _selected.toList();
    setState(() => _busy = true);
    try {
      final folders = await library.destinations(data.account);
      if (!mounted || !notifier.isCurrent(data)) return;
      if (folders.isEmpty) {
        SmartDialog.showToast('暂无可用收藏夹，请先创建');
        return;
      }
      final folder = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('${copy ? '复制' : '移动'}到'),
          children: [
            for (final folder in folders)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(folder.id),
                child: Text(folder.title),
              ),
          ],
        ),
      );
      if (!mounted || folder == null || !notifier.isCurrent(data)) return;
      final success = await libraryConfirm(
        context,
        title: '确认${copy ? '复制' : '移动'}？',
        isCurrent: () => mounted && notifier.isCurrent(data),
        ownsResult: () =>
            mounted && ref.read(laterLibraryProvider).owns(data.account),
        submit: () =>
            library.transfer(ids, folder, copy, account: data.account),
      );
      if (mounted && success) setState(_selected.clear);
    } catch (error) {
      if (mounted && notifier.isCurrent(data)) {
        SmartDialog.showToast(error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(LaterState data, LaterItemModel item, int cid, int index) =>
      PageUtils.toVideoPage(
        bvid: item.bvid,
        cid: cid,
        cover: item.pic,
        title: item.title,
        dimension: item.dimension,
        extraArguments: ref.read(playAllProvider)
            ? {
                'oid': item.aid,
                'sourceType': SourceType.watchLater,
                'count': widget.playlistCount ?? data.metadata,
                'favTitle': '稍后再看',
                'mediaId': data.account.mid,
                'desc': widget.query.asc,
                'isContinuePlaying': index != 0,
              }
            : const {'viewLater': true},
      );
  @override
  Widget build(BuildContext context) {
    final provider = laterFeedProvider(widget.query);
    final value = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final data = notifier.displayState;
    if (!identical(_source, data?.source) || !widget.active) {
      _selected.clear();
      _source = data?.source;
    }
    final items = data?.items ?? <LaterItemModel>[];
    return PopScope(
      canPop: _selected.isEmpty || !widget.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Column(
        children: [
          if (_selected.isNotEmpty)
            Row(
              children: [
                IconButton(
                  tooltip: '取消选择',
                  onPressed: _busy ? null : () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                ),
                Text('已选 ${_selected.length}'),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _selected.addAll(
                            items.map((item) => item.aid).whereType<int>(),
                          ),
                        ),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _transfer(data!, true),
                  child: const Text('复制'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _transfer(data!, false),
                  child: const Text('移动'),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: _busy
                      ? null
                      : () => _remove(
                          data!,
                          items.where((item) => _selected.contains(item.aid)),
                        ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          else
            Row(
              children: [
                TextButton.icon(
                  onPressed: data == null
                      ? null
                      : () {
                          for (var i = 0; i < items.length; i++) {
                            final item = items[i];
                            if (item.cid != null &&
                                item.pgcLabel?.isNotEmpty != true) {
                              _open(data, item, item.cid!, i);
                              break;
                            }
                          }
                        },
                  icon: const Icon(Icons.playlist_play),
                  label: const Text('播放全部'),
                ),
                const Spacer(),
                const Text('连续播放'),
                Switch(
                  value: ref.watch(playAllProvider),
                  onChanged: (value) async {
                    final result = await ref
                        .read(playAllProvider.notifier)
                        .set(value);
                    if (mounted && !result.isSuccess) result.toast();
                  },
                ),
              ],
            ),
          Expanded(
            child: LibraryFeedView(
              value: value,
              feed: notifier,
              itemBuilder: (context, item, index) => VideoCardHLater(
                index: index,
                videoItem: item,
                selecting: _selected.isNotEmpty,
                selected: _selected.contains(item.aid),
                onSelect: () => _toggle(item),
                onRemove: () => _remove(data!, [item]),
                isCurrent: () =>
                    mounted &&
                    _selected.isEmpty &&
                    data != null &&
                    notifier.isCurrent(data),
                onViewLater: (cid) => _open(data!, item, cid, index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
