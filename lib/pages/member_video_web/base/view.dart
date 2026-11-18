import 'package:pili_aurora_next/common/widgets/button/icon_button.dart';
import 'package:pili_aurora_next/common/widgets/dialog/dialog.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show ReloadMixin, ReloadScrollPhysics;
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/common/widgets/video_card/video_card_h.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/enum_with_label.dart';
import 'package:pili_aurora_next/models/horizontal_video_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/features/member_space/application/space_web.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/pages/search/widgets/search_text.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';

abstract class BaseVideoWebState<
  S extends ConsumerStatefulWidget,
  V extends EnumWithLabel
>
    extends ConsumerState<S>
    with GridMixin, ReloadMixin {
  final _owner = Object();
  late final String name;
  late final SpaceWebQuery query;
  SpaceWeb get controller => ref.read(spaceWebProvider(query).notifier);
  SpaceWebState get snapshot => ref.read(spaceWebProvider(query));

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map;
    name = args['name'];
    query = (
      owner: _owner,
      mid: args['mid'],
      type: args['type'],
      id: args['id'],
    );
  }

  List<V> get values;
  V get selectedOrder;

  Future<void> _retry() {
    reload = true;
    return controller.refresh(clear: true);
  }

  void _jump(int page) {
    reload = true;
    controller.jump(page);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final state = ref.watch(spaceWebProvider(query));
    ref.listen(mainAccountProvider, (_, _) => reload = true);
    return SimpleScaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          PopupMenuButton<V>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            initialValue: selectedOrder,
            onSelected: (value) {
              if (snapshot.busy) return;
              reload = true;
              controller.selectOrder(value);
            },
            itemBuilder: (_) => values
                .map((e) => AppPopupMenuItem(value: e, child: Text(e.label)))
                .toList(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: refreshIndicator(
        onRefresh: controller.refresh,
        child: FeedPagination.notifications(
          dataSource: state.source,
          dataRevision: state,
          canLoadMore: () => state.canLoadMore,
          onLoadMore: controller.more,
          child: CustomScrollView(
            physics: ReloadScrollPhysics(controller: this),
            slivers: [
              SliverPadding(
                padding: .only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
                ),
                sliver: buildBody(colorScheme, state.loading),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBody(
    ColorScheme colorScheme,
    LoadingState<List<HorizontalVideoModel>> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response.isNotEmpty
            ? SliverMainAxisGroup(
                slivers: [
                  buildHeader(colorScheme),
                  ?buildTags(colorScheme),
                  SliverGrid.builder(
                    gridDelegate: gridDelegate,
                    itemCount: response.length,
                    itemBuilder: (context, index) {
                      return VideoCardH(videoItem: response[index]);
                    },
                  ),
                  if (snapshot.pageError case final error?)
                    HttpError(
                      errMsg: error.errMsg,
                      onReload: () => controller.more(retry: true),
                    ),
                ],
              )
            : HttpError(onReload: _retry),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _retry,
      ),
    };
  }

  Widget? buildTags(ColorScheme colorScheme) => null;

  Widget buildHeader(ColorScheme colorScheme) {
    return SliverPinnedHeader(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(14, 0, 8, 4),
        child: Stack(
          clipBehavior: .none,
          alignment: .centerLeft,
          children: [
            ?buildCount(),
            Center(child: buildPageBtn(colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget? buildCount() {
    final count = snapshot.count;
    if (count == null) return null;
    return Text(
      '共 $count 视频',
      style: const TextStyle(height: 1),
      strutStyle: const StrutStyle(leading: 0, height: 1),
    );
  }

  Widget? buildPageBtn(ColorScheme colorScheme) {
    final totalPage = snapshot.totalPage;
    if (totalPage == null) return null;
    final page = snapshot.page;
    final canBackward = page > 1;
    final canForward = page < totalPage;
    const size = 30.0;
    const iconSize = 24.0;

    final backwardBtn = iconButton(
      size: size,
      iconSize: iconSize,
      tooltip: canBackward ? '上一页' : null,
      icon: const Icon(Icons.keyboard_arrow_left),
      onPressed: canBackward ? () => _jump(page - 1) : null,
    );

    final forwardBtn = iconButton(
      size: size,
      iconSize: iconSize,
      tooltip: canForward ? '下一页' : null,
      icon: const Icon(Icons.keyboard_arrow_right),
      onPressed: canForward ? () => _jump(page + 1) : null,
    );

    final pageIndicator = SearchText(
      height: 1,
      text: '$page / $totalPage',
      borderRadius: const .all(.circular(4)),
      padding: const .symmetric(horizontal: 10, vertical: 5),
      onTap: (_) => showJumpDialog(page),
    );

    return Row(
      spacing: 6,
      mainAxisSize: .min,
      children: [
        backwardBtn,
        pageIndicator,
        forwardBtn,
      ],
    );
  }

  void showJumpDialog(int page) {
    var pageStr = page.toString();
    final current = controller.capture();

    void onSubmit([_]) {
      if (!mounted || !current()) {
        SmartDialog.showToast('列表已更新，请重新选择页数');
        return;
      }
      final target = int.tryParse(pageStr);
      final total = snapshot.totalPage;
      if (target == null || total == null || total < 1) {
        SmartDialog.showToast('请输入有效页数');
        return;
      }
      _jump(target.clamp(1, total));
    }

    showConfirmDialog(
      context: context,
      title: const Text('跳至: '),
      content: TextFormField(
        autofocus: true,
        initialValue: pageStr,
        onChanged: (value) => pageStr = value,
        decoration: const InputDecoration(
          labelText: '页数',
          border: OutlineInputBorder(),
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onFieldSubmitted: (_) {
          Get.back();
          onSubmit();
        },
      ),
      onConfirm: onSubmit,
    );
  }
}
