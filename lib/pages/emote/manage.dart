import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/community/application/emote_management.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/image_type.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';
import 'package:pili_aurora_next/pages/emote/preview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/utils/page_utils.dart';

/// 原生管理评论区表情包。
class EmoteManagePage extends ConsumerStatefulWidget {
  const EmoteManagePage({super.key});

  @override
  ConsumerState<EmoteManagePage> createState() => _EmoteManagePageState();
}

class _EmoteManagePageState extends ConsumerState<EmoteManagePage> {
  final _owner = Object();
  final _searchController = TextEditingController();
  String _keyword = '';
  static const _categories = ['全部表情', '装扮商城', '会员专属', '包月充电'];
  static const _webUrl =
      'https://www.bilibili.com/h5/mall/emoji-package/home?navhide=1';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _changePackage(Package package, {required bool add}) async {
    final result = await ref
        .read(emoteManagementProvider(_owner).notifier)
        .changePackage(package, add: add);
    if (!mounted || result == null) return;
    if (result.isSuccess) {
      SmartDialog.showToast(add ? '添加成功' : '移除成功');
    } else {
      result.toast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = emoteManagementProvider(_owner);
    final snapshot = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final added = snapshot.added;
    final available = snapshot.available;

    return DefaultTabController(
      length: 2,
      child: SimpleScaffold(
        appBar: AppBar(
          title: const Text('表情包管理'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed:
                  snapshot.panel is Loading || snapshot.busyIds.isNotEmpty
                  ? null
                  : notifier.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '在浏览器中打开',
              onPressed: () => PageUtils.launchURL(_webUrl),
              icon: const Icon(Icons.open_in_browser),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: true,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _keyword = value.trim()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '搜索表情包',
                    suffixIcon: _keyword.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _keyword = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: '已添加 (${added.length})'),
                  Tab(text: '未添加 (${available.length})'),
                ],
              ),
              Expanded(
                child: switch (snapshot.panel) {
                  Loading() => m3eLoading,
                  Error error => Center(
                    child: TextButton.icon(
                      onPressed: notifier.refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(error.toString()),
                    ),
                  ),
                  Success() => TabBarView(
                    children: [
                      _buildPackageList(added, snapshot.busyIds, add: false),
                      _buildAvailablePackages(snapshot, available, notifier),
                    ],
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailablePackages(
    EmoteManagementState snapshot,
    List<Package> packages,
    EmoteManagement notifier,
  ) => Column(
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var category = 0; category < _categories.length; category++)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(_categories[category]),
                  selected: snapshot.category == category,
                  onSelected: (_) => notifier.selectCategory(category),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: switch (snapshot.selected) {
          Loading() => m3eLoading,
          Error error => Center(
            child: TextButton(
              onPressed: () => notifier.selectCategory(snapshot.category),
              child: Text('$error，点击重试'),
            ),
          ),
          _ => _buildPackageList(packages, snapshot.busyIds, add: true),
        },
      ),
    ],
  );

  Widget _buildPackageList(
    List<Package> packages,
    Set<int> busyIds, {
    required bool add,
  }) {
    final keyword = _keyword.toLowerCase();
    final filtered = packages
        .where(
          (package) =>
              keyword.isEmpty ||
              (package.text?.toLowerCase().contains(keyword) ?? false),
        )
        .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(_keyword.isEmpty ? '暂无表情包' : '没有匹配的表情包'),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final package = filtered[index];
        final id = package.id;
        final busy = busyIds.contains(id);
        return ListTile(
          onTap: id == null
              ? null
              : () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => EmotePackagePreviewPage(package: package),
                  ),
                ),
          leading: NetworkImgLayer(
            src: package.url,
            width: 44,
            height: 44,
            type: ImageType.emote,
            fit: BoxFit.contain,
          ),
          title: Text(package.text ?? '未命名表情包'),
          subtitle: Text(
            [
              if (package.emote != null) '${package.emote!.length} 个表情',
            ].join(' · '),
          ),
          trailing: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: add ? '添加' : '移除',
                  onPressed: id == null
                      ? null
                      : () => _changePackage(package, add: add),
                  icon: Icon(add ? Icons.add_circle_outline : Icons.remove),
                ),
        );
      },
    );
  }
}
