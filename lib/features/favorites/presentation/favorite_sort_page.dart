import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/reorder_mixin.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/folder_card.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/video_card.dart';

class FavoriteSortPage extends ConsumerStatefulWidget {
  const FavoriteSortPage({
    super.key,
    required this.query,
    required this.source,
  });
  final FavoriteQuery query;
  final FavoriteState source;
  @override
  ConsumerState<FavoriteSortPage> createState() => _FavoriteSortPageState();
}

class _FavoriteSortPageState extends ConsumerState<FavoriteSortPage>
    with ReorderMixin {
  late var _original = List<Object>.of(widget.source.items);
  late final _draft = List<Object>.of(_original);
  final _moves = <String>[];
  bool _saving = false, _loading = false;
  String? _error;
  bool get _folders => widget.query.kind == FavoriteKind.folders;
  FavoriteFeed get _feed =>
      ref.read(favoriteFeedProvider(widget.query).notifier);
  bool get _current => mounted && _feed.isCurrent(widget.source);
  Future<void> _loadMore() async {
    if (!_current || _saving || _loading) return;
    setState(() => _loading = true);
    await _feed.loadMore(retry: true);
    if (!mounted) return;
    final data = ref.read(favoriteFeedProvider(widget.query)).value;
    if (_current &&
        data != null &&
        listEquals(_original, data.items.take(_original.length).toList())) {
      _draft.addAll(data.items.skip(_original.length));
      _original = List.of(data.items);
      _error = data.error?.toString();
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    if (!_current) {
      setState(() => _error = '收藏列表已更新，请重新打开排序');
      return;
    }
    if (listEquals(_draft, _original)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final library = ref.read(favoriteLibraryProvider);
    final result = await _feed.sort(
      widget.source,
      _original,
      _folders
          ? _draft.cast<FavFolderInfo>().map((item) => item.id).join(',')
          : _moves.join(','),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!result.isSuccess) _error = '$result';
    });
    if (ModalRoute.of(context)?.isCurrent != true ||
        !library.owns(widget.source.account)) {
      return;
    }
    if (result.isSuccess) {
      Navigator.of(context).pop();
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_saving ||
        _loading ||
        !_current ||
        (_folders && (oldIndex == 0 || newIndex == 0))) {
      return;
    }
    if (!_folders) {
      final item = _draft[oldIndex] as FavDetailItemModel;
      final before = oldIndex > newIndex ? newIndex - 1 : newIndex;
      final previous = before < 0 || before >= _draft.length
          ? null
          : _draft[before] as FavDetailItemModel;
      _moves.add(
        '${previous == null ? '0:0' : '${previous.id}:${previous.type}'}:${item.id}:${item.type}',
      );
    }
    setState(() => _draft.insert(newIndex, _draft.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(favoriteFeedProvider(widget.query));
    final data = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _folders
              ? '收藏夹排序'
              : '排序: ${widget.source.metadata.folder?.title ?? ''}',
        ),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(_saving ? '提交中' : '完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null) Text(_error!),
          Expanded(
            child: ReorderableListView.builder(
              onReorderItem: _reorder,
              proxyDecorator: proxyDecorator,
              itemCount: _draft.length,
              itemBuilder: (context, index) {
                final item = _draft[index];
                return SizedBox(
                  key: ValueKey(favoriteKey(item)),
                  height: 110,
                  child: item is FavFolderInfo
                      ? FavVideoItem(heroTag: 'sort:${item.id}', item: item)
                      : FavVideoCardH(item: item as FavDetailItemModel),
                );
              },
            ),
          ),
          if (!_folders &&
              !value.isLoading &&
              !value.hasError &&
              data?.next != null)
            TextButton(
              onPressed: _saving || _loading ? null : _loadMore,
              child: Text(_loading ? '加载中' : '加载更多'),
            ),
        ],
      ),
    );
  }
}
