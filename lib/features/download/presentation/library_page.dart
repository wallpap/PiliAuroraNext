import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;
import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/dialog/dialog.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/flutter/pop_scope.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/select_mask.dart';
import 'package:pili_aurora_next/features/download/application/download_providers.dart';
import 'package:pili_aurora_next/features/download/domain/download_snapshot.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/badge_type.dart';
import 'package:pili_aurora_next/models/remote/download/bili_download_entry_info.dart';
import 'package:pili_aurora_next/pages/download/deletion.dart';
import 'package:pili_aurora_next/pages/download/detail/view.dart';
import 'package:pili_aurora_next/pages/download/detail/widgets/item.dart';
import 'package:pili_aurora_next/pages/download/search/view.dart';
import 'package:pili_aurora_next/services/download/download_service.dart';
import 'package:pili_aurora_next/utils/cache_manager.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';

enum DownloadViewMode { library, queued, detail, search }

class DownloadLibraryPage extends ConsumerStatefulWidget {
  const DownloadLibraryPage({
    super.key,
    this.mode = DownloadViewMode.library,
    this.pageId,
    this.title,
    this.progress,
  });

  final DownloadViewMode mode;
  final String? pageId;
  final String? title;
  final ChangeNotifier? progress;

  @override
  ConsumerState<DownloadLibraryPage> createState() =>
      _DownloadLibraryPageState();
}

class _DownloadLibraryPageState extends ConsumerState<DownloadLibraryPage>
    with GridMixin {
  final _selected = <String>{};
  final _search = TextEditingController();
  final _deletion = DownloadDeletion();
  late final _progress = widget.progress ?? ChangeNotifier();
  bool _selecting = false;
  bool _updating = false;
  int? _generation;

  DownloadLibrary get _commands => ref.read(downloadLibraryProvider.notifier);
  DownloadSnapshot? get _snapshot =>
      ref.read(downloadLibraryProvider).dataOrNull;

  @override
  void dispose() {
    _search.dispose();
    if (widget.progress == null) _progress.dispose();
    super.dispose();
  }

  void _toggleSelection(String key) => setState(() {
    if (!_selected.add(key)) _selected.remove(key);
  });

  void _cancelSelection() => setState(() {
    _selected.clear();
    _selecting = false;
  });

  List<DownloadTask> _tasks(DownloadSnapshot snapshot) => switch (widget.mode) {
    DownloadViewMode.queued => snapshot.queued,
    DownloadViewMode.detail => snapshot.entriesFor(widget.pageId!),
    DownloadViewMode.search => snapshot.search(_search.text),
    DownloadViewMode.library => snapshot.completed,
  };

  List<_DownloadGroup> _groups(List<DownloadTask> tasks) => [
    for (final entries in groupBy(tasks, (task) => task.pageDirPath).values)
      _DownloadGroup(entries),
  ];

  Future<void> _updateDanmaku(Iterable<DownloadTask> tasks) async {
    if (_updating || !mounted) return;
    _updating = true;
    final generation = _snapshot?.generation;
    final commands = _commands;
    final selected = tasks.toList();
    final updated = <String>{};
    Error? failure;
    bool current() => mounted && _snapshot?.generation == generation;
    try {
      for (final task in selected) {
        if (!current()) break;
        final result = await commands.updateDanmaku(task);
        if (result.isSuccess) {
          updated.add(task.key);
        } else if (result is Error && result is! DownloadCancelled) {
          failure ??= result;
        }
      }
      if (!current()) return;
      setState(() {
        if (widget.mode == DownloadViewMode.library) {
          for (final group in _groups(_tasks(_snapshot!))) {
            if (group.tasks.every((task) => updated.contains(task.key))) {
              _selected.remove(group.dirPath);
            }
          }
        } else {
          _selected.removeAll(updated);
        }
        if (_selected.isEmpty) _selecting = false;
      });
      if (failure != null) {
        failure.toast();
      } else if (selected.isNotEmpty && updated.length == selected.length) {
        SmartDialog.showToast('更新成功');
      }
    } finally {
      _updating = false;
    }
  }

  Future<void> _removeTasks(List<DownloadTask> tasks) async {
    final generation = _snapshot?.generation;
    final commands = _commands;
    final removed = await _deletion.run(
      items: tasks,
      delete: commands.remove,
      entries: (task) => [task.toEntry()],
      isCurrent: () => mounted && _snapshot?.generation == generation,
      showLoading: tasks.length > 1,
    );
    if (!mounted) return;
    setState(() {
      _selected.removeAll(removed.map((task) => task.key));
      if (_selected.isEmpty) _selecting = false;
    });
    if (widget.mode == DownloadViewMode.detail &&
        removed.isNotEmpty &&
        _snapshot?.entriesFor(widget.pageId!).isEmpty == true &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _removeGroups(List<_DownloadGroup> groups) async {
    final generation = _snapshot?.generation;
    final commands = _commands;
    final removed = await _deletion.run(
      items: groups,
      delete: (group) => commands.removeGroup(group.tasks),
      entries: (group) => group.entries,
      isCurrent: () => mounted && _snapshot?.generation == generation,
      showLoading: groups.length > 1,
    );
    if (!mounted) return;
    setState(() {
      _selected.removeAll(removed.map((group) => group.dirPath));
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _confirmRemove(List<DownloadTask> tasks, List<_DownloadGroup> groups) {
    if (_deletion.busy || _selected.isEmpty) return;
    final selectedTasks = tasks
        .where((task) => _selected.contains(task.key))
        .toList();
    final selectedGroups = groups
        .where((group) => _selected.contains(group.dirPath))
        .toList();
    showConfirmDialog(
      context: context,
      title: const Text('确定删除选中视频？'),
      onConfirm: () => widget.mode == DownloadViewMode.library
          ? _removeGroups(selectedGroups)
          : _removeTasks(selectedTasks),
    );
  }

  Widget _item(
    DownloadTask task, {
    bool preview = false,
    String? selectionKey,
  }) => DetailItem(
    key: ValueKey(task.key),
    entry: task.toEntry(),
    playlist: [
      for (final group in _groups(_snapshot?.completed ?? [])) ...group.entries,
    ],
    progress: widget.mode == DownloadViewMode.queued ? null : _progress,
    showTitle: widget.mode != DownloadViewMode.detail,
    isCurr: identical(_snapshot?.current?.identity, task.identity),
    enableMultiSelect: _selecting,
    checked: _selected.contains(selectionKey ?? task.key),
    onSelect: (_) => _toggleSelection(selectionKey ?? task.key),
    onDelete: preview ? null : () => _removeTasks([task]),
    onUpdate: () => _updateDanmaku([task]),
    onToggle: () async {
      final result = await _commands.toggle(task);
      if (mounted && !result.isSuccess && result is! DownloadCancelled) {
        result.toast();
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(downloadLibraryProvider);
    final snapshot = state.dataOrNull;
    final tasks = snapshot == null ? <DownloadTask>[] : _tasks(snapshot);
    final groups = _groups(tasks);
    final keys = widget.mode == DownloadViewMode.library
        ? groups.map((group) => group.dirPath).toSet()
        : tasks.map((task) => task.key).toSet();
    if (_generation != snapshot?.generation) {
      _selected.clear();
      _selecting = false;
      _generation = snapshot?.generation;
    }
    final hadSelection = _selected.isNotEmpty;
    _selected.retainAll(keys);
    if (hadSelection && _selected.isEmpty) _selecting = false;
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final current = snapshot?.current ?? snapshot?.queued.firstOrNull;
    final title = switch (widget.mode) {
      DownloadViewMode.library => '离线缓存',
      DownloadViewMode.queued => '正在缓存',
      DownloadViewMode.detail => widget.title ?? '已缓存视频',
      DownloadViewMode.search => '搜索缓存',
    };
    return popScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (_selecting) _cancelSelection();
      },
      child: SimpleScaffold(
        appBar: AppBar(
          leading: _selecting
              ? IconButton(
                  tooltip: '取消',
                  icon: const Icon(Icons.close_outlined),
                  onPressed: _cancelSelection,
                )
              : null,
          title: _selecting
              ? Text('已选: ${_selected.length}')
              : widget.mode == DownloadViewMode.search
              ? TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜索标题或作者',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {
                    _selected.clear();
                    _selecting = false;
                  }),
                )
              : Text(title),
          actions: _selecting
              ? [
                  TextButton(
                    onPressed: () => setState(() {
                      _selected.addAll(keys);
                    }),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => _updateDanmaku(
                      widget.mode == DownloadViewMode.library
                          ? groups
                                .where(
                                  (group) => _selected.contains(group.dirPath),
                                )
                                .expand((group) => group.tasks)
                          : tasks.where((task) => _selected.contains(task.key)),
                    ),
                    child: const Text('更新'),
                  ),
                  TextButton(
                    onPressed: () => _confirmRemove(tasks, groups),
                    child: Text(
                      '移除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ]
              : [
                  if (widget.mode == DownloadViewMode.library)
                    IconButton(
                      tooltip: '搜索',
                      icon: const Icon(Icons.search),
                      onPressed: snapshot == null
                          ? null
                          : () =>
                                Get.to(DownloadSearchPage(progress: _progress)),
                    ),
                  IconButton(
                    tooltip: '多选',
                    icon: const Icon(Icons.edit_note),
                    onPressed: snapshot == null
                        ? null
                        : () => setState(() {
                            _selecting = true;
                          }),
                  ),
                ],
        ),
        body: Padding(
          padding: EdgeInsets.only(left: padding.left, right: padding.right),
          child: CustomScrollView(
            slivers: [
              if (state is Error)
                HttpError(errMsg: state.toString(), onReload: _commands.refresh)
              else if (snapshot == null)
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (widget.mode == DownloadViewMode.library &&
                    current != null) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('正在缓存 (${snapshot.queued.length})'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 110,
                      child: _item(current, preview: true),
                    ),
                  ),
                ],
                if (tasks.isNotEmpty) ...[
                  if (widget.mode == DownloadViewMode.library)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('已缓存视频'),
                      ),
                    ),
                  SliverGrid.builder(
                    gridDelegate: gridDelegate,
                    itemCount: widget.mode == DownloadViewMode.library
                        ? groups.length
                        : tasks.length,
                    itemBuilder: (context, index) {
                      if (widget.mode != DownloadViewMode.library) {
                        return _item(tasks[index]);
                      }
                      final group = groups[index];
                      return group.tasks.length == 1
                          ? _item(
                              group.tasks.single,
                              selectionKey: group.dirPath,
                            )
                          : _buildItem(theme, group, _selecting);
                    },
                  ),
                ] else if (widget.mode != DownloadViewMode.library ||
                    snapshot.queued.isEmpty)
                  const HttpError(),
              ],
              SliverToBoxAdapter(child: SizedBox(height: padding.bottom + 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    ThemeData theme,
    _DownloadGroup pageInfo,
    bool enableMultiSelect,
  ) {
    void onLongPress() => enableMultiSelect
        ? null
        : showDialog(
            context: context,
            builder: (context) => SimpleDialog(
              clipBehavior: Clip.hardEdge,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                DialogOption(
                  onPressed: () {
                    Get.back();
                    showConfirmDialog(
                      context: context,
                      title: const Text('确定删除？'),
                      onConfirm: () => _removeGroups([pageInfo]),
                    );
                  },
                  child: const Text('删除', style: TextStyle(fontSize: 14)),
                ),
                DialogOption(
                  onPressed: () async {
                    Get.back();
                    await _updateDanmaku(pageInfo.tasks);
                  },
                  child: const Text('更新弹幕', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          );
    final first = pageInfo.entries.first;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          if (_selecting) {
            _toggleSelection(pageInfo.dirPath);
            return;
          }
          Get.to(
            DownloadDetailPage(
              pageId: pageInfo.pageId,
              title: pageInfo.title,
              progress: _progress,
            ),
          );
        },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
            spacing: 10,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) => NetworkImgLayer(
                        src: pageInfo.cover,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                    ),
                  ),
                  PBadge(
                    text: '${pageInfo.entries.length}个视频',
                    right: 6.0,
                    bottom: 6.0,
                    isBold: false,
                    type: PBadgeType.gray,
                  ),
                  if (pageInfo.seasonType case final pgcType?)
                    PBadge(
                      text: switch (pgcType) {
                        -1 => '课程',
                        1 => '番剧',
                        2 => '电影',
                        3 => '纪录片',
                        4 => '国创',
                        5 => '电视剧',
                        7 => '综艺',
                        _ => null,
                      },
                      right: 6.0,
                      top: 6.0,
                    ),
                  Positioned.fill(
                    child: selectMask(
                      theme.colorScheme,
                      _selected.contains(pageInfo.dirPath),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        pageInfo.title,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                          height: 1.42,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: .end,
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Text(
                          '${CacheManager.formatSize(pageInfo.entries.fold(0, (p, n) => p + n.totalBytes))}  ${first.ownerName ?? ""}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        pageInfo.entries.first.moreBtn(theme.colorScheme),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadGroup {
  _DownloadGroup(List<DownloadTask> tasks)
    : tasks = List.unmodifiable(
        tasks.toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
      );
  final List<DownloadTask> tasks;
  List<BiliDownloadEntryInfo> get entries =>
      tasks.map((task) => task.toEntry()).toList();
  BiliDownloadEntryInfo get _first => tasks.first.toEntry();
  String get pageId => tasks.first.pageId;
  String get dirPath => tasks.first.pageDirPath;
  String get title => _first.title;
  String get cover => _first.cover;
  int? get seasonType => _first.ep?.seasonType;
}
