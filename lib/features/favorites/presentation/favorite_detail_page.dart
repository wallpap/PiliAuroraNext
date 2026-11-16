import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/features/content_library/presentation/operation_dialog.dart';
import 'package:pili_aurora_next/features/content_library/application/library_preferences.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_panel.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_sort_page.dart';
import 'package:pili_aurora_next/models/common/fav_order_type.dart';
import 'package:pili_aurora_next/models/common/video/source_type.dart';
import 'package:pili_aurora_next/pages/dynamics_repost/view.dart';
import 'package:pili_aurora_next/utils/bili_utils.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';
import 'package:pili_aurora_next/utils/share_utils.dart';

class FavoriteDetailPage extends ConsumerStatefulWidget {
  const FavoriteDetailPage({super.key, this.search = false});
  final bool search;
  @override
  ConsumerState<FavoriteDetailPage> createState() => _FavoriteDetailPageState();
}

class _FavoriteDetailPageState extends ConsumerState<FavoriteDetailPage> {
  final _owner = Object();
  final _input = TextEditingController();
  late final _arguments = Get.arguments is Map
      ? Get.arguments as Map
      : const {};
  late final int _mediaId = widget.search
      ? int.tryParse('${_arguments['mediaId']}') ?? 0
      : int.tryParse(Get.parameters['mediaId'] ?? '') ?? 0;
  String _keyword = '';
  FavOrderType _order = FavOrderType.mtime;
  bool _reverse = false;
  bool get _playAll => ref.read(playAllProvider);
  bool _savingPreference = false;
  FavoriteQuery get _query => FavoriteQuery(
    owner: _owner,
    kind: FavoriteKind.detail,
    mediaId: _mediaId,
    keyword: _keyword,
    order: _order,
    reverse: _reverse,
    type: widget.search ? (_arguments['type'] as int? ?? 0) : 0,
  );
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _setPlayAll() async {
    if (_savingPreference) return;
    _savingPreference = true;
    final next = !_playAll;
    try {
      final result = await ref.read(playAllProvider.notifier).set(next);
      if (mounted && !result.isSuccess) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$result')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('播放偏好保存失败，请重试')));
      }
    } finally {
      _savingPreference = false;
    }
  }

  Future<void> _folderAction(
    FavoriteFeed feed,
    FavoriteState data,
    FolderAction action,
  ) async {
    final library = ref.read(favoriteLibraryProvider);
    final ok = await libraryConfirm(
      context,
      title: switch (action) {
        FolderAction.delete => '删除该收藏夹？',
        FolderAction.clean => '清除失效内容？',
        FolderAction.follow => '收藏此收藏夹？',
        FolderAction.unfollow => '取消收藏此收藏夹？',
      },
      isCurrent: () => mounted && feed.isCurrent(data),
      ownsResult: () => mounted && library.owns(data.account),
      submit: () => library.folderAction(data.account, _mediaId, action),
    );
    if (ok &&
        mounted &&
        action == FolderAction.delete &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(true);
    }
  }

  void _play(FavoriteState data) {
    final items = data.items.whereType<FavDetailItemModel>().where(
      (item) => item.ugc?.firstCid != null,
    );
    if (items.isEmpty) return;
    final item = items.first, folder = data.metadata.folder;
    PageUtils.toVideoPage(
      bvid: item.bvid,
      cid: item.ugc!.firstCid!,
      cover: item.cover,
      title: item.title,
      extraArguments: {
        'sourceType': SourceType.fav,
        'mediaId': _mediaId,
        'oid': item.id,
        'favTitle': folder?.title,
        'count': folder?.mediaCount,
        'desc': !_reverse,
        'isOwner': folder?.mid == data.account.mid,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(playAllProvider);
    final query = _query;
    final value = ref.watch(favoriteFeedProvider(query));
    final feed = ref.read(favoriteFeedProvider(query).notifier);
    final data = !value.isLoading && !value.hasError ? value.value : null;
    final folder = data?.metadata.folder;
    final owner = data != null && folder?.mid == data.account.mid;
    return Scaffold(
      appBar: AppBar(
        title: widget.search
            ? TextField(
                controller: _input,
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜索收藏'),
                onSubmitted: (value) => setState(() => _keyword = value.trim()),
              )
            : Text(folder?.title ?? '收藏夹'),
        actions: [
          if (!widget.search)
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: data == null
                  ? null
                  : () => Get.toNamed(
                      '/favSearch',
                      arguments: {'mediaId': _mediaId, 'type': 0},
                    ),
            ),
          PopupMenuButton<FavOrderType>(
            tooltip: '排序方式',
            initialValue: _order,
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => _order = value),
            itemBuilder: (_) => [
              for (final order in FavOrderType.values)
                AppPopupMenuItem(value: order, child: Text(order.label)),
            ],
          ),
          if (!widget.search)
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (action) async {
                if (data == null || folder == null || !feed.isCurrent(data)) {
                  return;
                }
                switch (action) {
                  case 'reverse':
                    setState(() => _reverse = !_reverse);
                  case 'playAll':
                    await _setPlayAll();
                  case 'edit':
                    await Get.toNamed(
                      '/createFav',
                      parameters: {'mediaId': '$_mediaId'},
                    );
                  case 'sort':
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            FavoriteSortPage(query: query, source: data),
                      ),
                    );
                  case 'share':
                    await ShareUtils.shareText(
                      'https://www.bilibili.com/medialist/detail/ml$_mediaId',
                    );
                  case 'repost':
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => RepostPanel(
                        rid: _mediaId,
                        dynType: 4300,
                        pic: folder.cover,
                        title: folder.title,
                        uname: folder.upper?.name,
                      ),
                    );
                  case 'follow':
                    await _folderAction(
                      feed,
                      data,
                      folder.favState == 1
                          ? FolderAction.unfollow
                          : FolderAction.follow,
                    );
                  case 'clean':
                    await _folderAction(feed, data, FolderAction.clean);
                  case 'delete':
                    await _folderAction(feed, data, FolderAction.delete);
                }
              },
              itemBuilder: (_) => [
                AppPopupMenuItem(
                  value: 'reverse',
                  child: Text(_reverse ? '页码正序' : '页码倒序'),
                ),
                AppPopupMenuItem(
                  value: 'playAll',
                  child: Text(_playAll ? '关闭连续播放' : '开启连续播放'),
                ),
                if (owner) ...[
                  const AppPopupMenuItem(value: 'edit', child: Text('编辑信息')),
                  AppPopupMenuItem(
                    value: 'sort',
                    enabled:
                        data.items.isNotEmpty &&
                        (folder?.mediaCount ?? 0) <= 1000,
                    child: const Text('排序'),
                  ),
                  const AppPopupMenuItem(value: 'clean', child: Text('清除失效内容')),
                  if (folder != null && !BiliUtils.isDefaultFav(folder.attr))
                    const AppPopupMenuItem(
                      value: 'delete',
                      child: Text('删除收藏夹'),
                    ),
                ] else if (folder != null)
                  AppPopupMenuItem(
                    value: 'follow',
                    child: Text(folder.favState == 1 ? '取消收藏' : '收藏'),
                  ),
                if (folder != null && BiliUtils.isPublicFav(folder.attr)) ...[
                  const AppPopupMenuItem(value: 'share', child: Text('分享')),
                  const AppPopupMenuItem(value: 'repost', child: Text('分享至动态')),
                ],
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (!widget.search && folder != null)
              ListTile(
                leading: SizedBox(
                  width: 100,
                  child: NetworkImgLayer(
                    src: folder.cover,
                    width: 100,
                    height: 62,
                  ),
                ),
                title: Text(folder.title),
                subtitle: Text(
                  '${folder.mediaCount}个内容 · ${BiliUtils.isPublicFavText(folder.attr)}${folder.intro?.isNotEmpty == true ? '\n${folder.intro}' : ''}',
                ),
                trailing: folder.upper?.name == null
                    ? null
                    : TextButton(
                        onPressed: () =>
                            Get.toNamed('/member?mid=${folder.upper!.mid}'),
                        child: Text(folder.upper!.name!),
                      ),
              ),
            Expanded(
              child: FavoritePanel(query: query, playAll: _playAll),
            ),
          ],
        ),
      ),
      floatingActionButton:
          !widget.search && data != null && data.items.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_playAll) {
                  _play(data);
                } else {
                  _setPlayAll();
                }
              },
              icon: const Icon(Icons.playlist_play),
              label: Text(_playAll ? '播放全部' : '开启连续播放'),
            )
          : null,
    );
  }
}
