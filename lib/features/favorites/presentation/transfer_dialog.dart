import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/favorites/application/favorite_library.dart';

Future<void> transferFavorites(
  BuildContext context,
  WidgetRef ref,
  FavoriteQuery query,
  FavoriteState source,
  List<Object> selected,
  bool copy,
) async {
  final library = ref.read(favoriteLibraryProvider);
  final feed = ref.read(favoriteFeedProvider(query).notifier);
  if (!feed.isCurrent(source)) return;
  List<FavFolderInfo> folders;
  try {
    folders = await library.destinations(source.account);
  } catch (error) {
    if (context.mounted && feed.isCurrent(source)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
    return;
  }
  if (!context.mounted || !feed.isCurrent(source)) return;
  folders = folders.where((folder) => folder.id != query.mediaId).toList();
  int? destination;
  bool saving = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${copy ? '复制' : '移动'}到'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (folders.isEmpty) const Text('暂无可用的目标收藏夹'),
              RadioGroup<int>(
                groupValue: destination,
                onChanged: (value) {
                  if (!saving) setState(() => destination = value);
                },
                child: Column(
                  children: [
                    for (final folder in folders)
                      RadioListTile<int>(
                        value: folder.id,
                        title: Text(folder.title),
                      ),
                  ],
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: saving || destination == null
                ? null
                : () async {
                    if (!feed.isCurrent(source)) {
                      setState(() => error = '收藏列表已更新，请重新打开');
                      return;
                    }
                    setState(() => saving = true);
                    final result = await feed.transfer(
                      source,
                      selected,
                      destination!,
                      copy,
                    );
                    if (!context.mounted) return;
                    setState(() {
                      saving = false;
                      if (!result.isSuccess) error = '$result';
                    });
                    if (ModalRoute.of(context)?.isCurrent != true ||
                        !library.owns(source.account)) {
                      return;
                    }
                    if (result.isSuccess) {
                      Navigator.of(context).pop();
                    }
                  },
            child: Text(saving ? '提交中' : '确认'),
          ),
        ],
      ),
    ),
  );
}
