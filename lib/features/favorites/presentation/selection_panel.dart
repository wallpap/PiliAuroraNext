import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/utils/bili_utils.dart';

/// 播放器只提供固定目标、归属判断和确认回调，收藏草稿归面板持有。
class FavoriteSelectionPanel extends ConsumerStatefulWidget {
  const FavoriteSelectionPanel({
    super.key,
    required this.target,
    required this.isCurrent,
    required this.onSaved,
    this.scrollController,
  });
  final FavoriteTarget target;
  final bool Function() isCurrent;
  final ValueChanged<bool> onSaved;
  final ScrollController? scrollController;
  @override
  ConsumerState<FavoriteSelectionPanel> createState() =>
      _FavoriteSelectionPanelState();
}

class _FavoriteSelectionPanelState
    extends ConsumerState<FavoriteSelectionPanel> {
  final _owner = Object();
  FavoriteMembership? _source;
  final _selected = <int>{};
  bool _saving = false;
  String? _error;
  MembershipQuery get _query => (owner: _owner, target: widget.target);
  Future<void> _save(FavoriteMembership data) async {
    final library = ref.read(favoriteLibraryProvider);
    if (_saving) return;
    final value = ref.read(favoriteMembershipProvider(_query));
    if (!widget.isCurrent() ||
        value.isLoading ||
        value.hasError ||
        !identical(value.value, data) ||
        !library.ownsMembership(data)) {
      setState(() => _error = '视频或账号已更新，请重新打开');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await library.select(data, _selected);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!result.isSuccess) _error = '$result';
    });
    if (ModalRoute.of(context)?.isCurrent != true ||
        !widget.isCurrent() ||
        !library.owns(data.account)) {
      return;
    }
    if (result.isSuccess) {
      widget.onSaved(result.data);
      Navigator.of(context).pop();
    }
  }

  void _accept(FavoriteMembership data) {
    if (identical(_source, data)) return;
    final previous = _source;
    final added = previous == null
        ? <int>{}
        : _selected.difference(previous.selected);
    final removed = previous == null
        ? <int>{}
        : previous.selected.difference(_selected);
    final keepDraft =
        previous != null &&
        identical(previous.account, data.account) &&
        previous.target == data.target;
    _selected
      ..clear()
      ..addAll(data.selected);
    if (keepDraft) {
      _selected
        ..addAll(added)
        ..removeAll(removed);
    }
    _selected.removeWhere(
      (id) => !data.folders.any((folder) => folder.id == id),
    );
    _source = data;
  }

  @override
  Widget build(BuildContext context) {
    final provider = favoriteMembershipProvider(_query);
    final value = ref.watch(provider);
    final data = !value.isLoading && !value.hasError ? value.value : null;
    if (data != null) _accept(data);
    return Column(
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          title: const Text('添加到收藏夹'),
          leading: IconButton(
            tooltip: '关闭',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          actions: [
            TextButton.icon(
              onPressed: _saving || data == null
                  ? null
                  : () async {
                      final library = ref.read(favoriteLibraryProvider);
                      final created = await Get.toNamed('/createFav');
                      if (!mounted ||
                          !widget.isCurrent() ||
                          !library.owns(data.account)) {
                        return;
                      }
                      if (created is FavFolderInfo) {
                        setState(() => _selected.add(created.id));
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('新建收藏夹'),
            ),
          ],
        ),
        Expanded(
          child: value.isLoading
              ? const Center(child: CircularProgressIndicator())
              : value.hasError
              ? Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text('${value.error}，点击重试'),
                  ),
                )
              : data == null || data.folders.isEmpty
              ? const Center(child: Text('暂无收藏夹，请先创建'))
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: data.folders.length,
                  itemBuilder: (context, index) {
                    final folder = data.folders[index];
                    final checked = _selected.contains(folder.id);
                    final full =
                        !data.selected.contains(folder.id) &&
                        BiliUtils.isFavFolderFull(
                          folder.attr,
                          folder.mediaCount,
                        );
                    final count =
                        folder.mediaCount +
                        (checked ? 1 : 0) -
                        (data.selected.contains(folder.id) ? 1 : 0);
                    void toggle() => setState(() {
                      if (!_selected.add(folder.id)) {
                        _selected.remove(folder.id);
                      }
                    });
                    return CheckboxListTile(
                      value: checked,
                      onChanged: _saving || (full && !checked)
                          ? null
                          : (_) => toggle(),
                      title: Text(folder.title),
                      subtitle: Text(
                        '$count个内容${full ? '(已满)' : ''} · ${BiliUtils.isPublicFavText(folder.attr)}',
                      ),
                    );
                  },
                ),
        ),
        if (_error != null) Text(_error!),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: _saving || data == null ? null : () => _save(data),
                  child: Text(_saving ? '提交中' : '完成'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
