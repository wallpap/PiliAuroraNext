import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_library/presentation/feed_view.dart';
import 'package:pili_aurora_next/features/content_library/presentation/operation_dialog.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/article_card.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/folder_card.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/note_card.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/pgc_card.dart';
import 'package:pili_aurora_next/features/favorites/presentation/cards/video_card.dart';
import 'package:pili_aurora_next/features/favorites/presentation/transfer_dialog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/pages/member_cheese/widgets/item.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';

class FavoritePanel extends ConsumerStatefulWidget {
  const FavoritePanel({
    super.key,
    required this.query,
    this.playAll = false,
    this.search = false,
  });
  final FavoriteQuery query;
  final bool playAll;
  final bool search;
  @override
  ConsumerState<FavoritePanel> createState() => _FavoritePanelState();
}

class _FavoritePanelState extends ConsumerState<FavoritePanel>
    with AutomaticKeepAliveClientMixin {
  final _selected = <Object>{};
  Object? _source;
  @override
  bool get wantKeepAlive => true;
  void _select(Object item) => setState(() {
    final key = favoriteKey(item);
    if (!_selected.add(key)) _selected.remove(key);
  });
  Future<void> _remove(
    FavoriteFeed feed,
    FavoriteState data,
    List<Object> items, {
    int? pgcStatus,
    bool pgc = false,
  }) async {
    final library = ref.read(favoriteLibraryProvider);
    await libraryConfirm(
      context,
      title: pgc && pgcStatus != null ? '更新所选追番状态？' : '删除所选收藏？',
      isCurrent: () => mounted && feed.isCurrent(data),
      ownsResult: () => mounted && library.owns(data.account),
      submit: () =>
          pgc ? feed.pgc(data, items, pgcStatus) : feed.remove(data, items),
    );
  }

  void _openVideo(FavDetailItemModel item, int index, FavoriteState data) {
    if (item.ugc?.firstCid == null) return;
    final folder = data.metadata.folder;
    PageUtils.toVideoPage(
      bvid: item.bvid,
      cid: item.ugc!.firstCid!,
      cover: item.cover,
      title: item.title,
      extraArguments: widget.search || widget.playAll
          ? {
              'sourceType': SourceType.fav,
              'mediaId': widget.query.mediaId,
              'oid': item.id,
              'favTitle': folder?.title,
              'count': folder?.mediaCount,
              'desc': !widget.query.reverse,
              'isContinuePlaying': widget.search || index != 0,
              'isOwner': folder?.mid == data.account.mid,
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = favoriteFeedProvider(widget.query);
    final value = ref.watch(provider);
    final feed = ref.read(provider.notifier);
    final data = feed.displayState;
    if (!identical(_source, data?.source)) {
      _source = data?.source;
      _selected.clear();
    }
    final items = data?.items ?? [];
    final selected = items
        .where((item) => _selected.contains(favoriteKey(item)))
        .toList();
    final owner = data?.metadata.folder?.mid == data?.account.mid;
    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Column(
        children: [
          if (_selected.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '取消选择',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_selected.clear),
                  ),
                  Text('已选 ${_selected.length}'),
                  TextButton(
                    onPressed: () => setState(
                      () => _selected.addAll(items.map(favoriteKey)),
                    ),
                    child: const Text('全选'),
                  ),
                  if (widget.query.kind == FavoriteKind.pgc) ...[
                    for (final status in [1, 2, 3])
                      if (status != widget.query.status)
                        TextButton(
                          onPressed: () => _remove(
                            feed,
                            data!,
                            selected,
                            pgc: true,
                            pgcStatus: status,
                          ),
                          child: Text('标记为${['想看', '在看', '看过'][status - 1]}'),
                        ),
                  ] else ...[
                    if (widget.query.kind == FavoriteKind.detail && owner) ...[
                      TextButton(
                        onPressed: () => transferFavorites(
                          context,
                          ref,
                          widget.query,
                          data!,
                          selected,
                          true,
                        ),
                        child: const Text('复制'),
                      ),
                      TextButton(
                        onPressed: () => transferFavorites(
                          context,
                          ref,
                          widget.query,
                          data!,
                          selected,
                          false,
                        ),
                        child: const Text('移动'),
                      ),
                    ],
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(feed, data!, selected),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: LibraryFeedView(
              value: value,
              feed: feed,
              itemBuilder: (context, item, index) {
                final selecting = _selected.isNotEmpty;
                final checked = _selected.contains(favoriteKey(item));
                return switch (item) {
                  FavFolderInfo() => FavVideoItem(
                    heroTag:
                        'fav:${identityHashCode(widget.query.owner)}:${item.id}',
                    item: item,
                    onTap: () => Get.toNamed(
                      '/favDetail',
                      parameters: {'mediaId': '${item.id}'},
                    ),
                  ),
                  FavDetailItemModel() => FavVideoCardH(
                    item: item,
                    index: index,
                    isOwner: owner,
                    selecting: selecting,
                    selected: checked,
                    onSelect: owner ? () => _select(item) : null,
                    onOpen: () => _openVideo(item, index, data!),
                    onRemove: () => _remove(feed, data!, [item]),
                  ),
                  FavArticleItemModel() => FavArticleItem(
                    item: item,
                    onDelete: () => _remove(feed, data!, [item]),
                  ),
                  SpaceCheeseItem() => MemberCheeseItem(
                    item: item,
                    onRemove: () => _remove(feed, data!, [item]),
                  ),
                  FavPgcItemModel() => FavPgcItem(
                    item: item,
                    selecting: selecting,
                    selected: checked,
                    onSelect: () => _select(item),
                    onUpdateStatus: () => _pgcMenu(feed, data!, item),
                  ),
                  FavNoteItemModel() => FavNoteItem(
                    item: item,
                    selecting: selecting,
                    selected: checked,
                    onSelect: () => _select(item),
                  ),
                  FavTopicItem() => Card(
                    child: ListTile(
                      title: Text('# ${item.name ?? ''}'),
                      onTap: () => Get.toNamed(
                        '/dynTopic',
                        parameters: {
                          'id': '${item.id}',
                          'name': item.name ?? '',
                        },
                      ),
                      onLongPress: () => _remove(feed, data!, [item]),
                    ),
                  ),
                  _ => const SizedBox.shrink(),
                };
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pgcMenu(
    FavoriteFeed feed,
    FavoriteState data,
    FavPgcItemModel item,
  ) async {
    final status = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('追番状态'),
        children: [
          for (final status in [1, 2, 3, -1])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(status),
              child: Text(
                status == -1 ? '取消追番' : ['想看', '在看', '看过'][status - 1],
              ),
            ),
        ],
      ),
    );
    if (!mounted || status == null || !feed.isCurrent(data)) return;
    final library = ref.read(favoriteLibraryProvider);
    final route = ModalRoute.of(context);
    final result = await feed.pgc(data, [item], status == -1 ? null : status);
    if (mounted &&
        route?.isCurrent == true &&
        library.owns(data.account) &&
        !result.isSuccess) {
      await _showError(result);
    }
  }

  Future<void> _showError(LoadingState<void> result) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text('$result'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
