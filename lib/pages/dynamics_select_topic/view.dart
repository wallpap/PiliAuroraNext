import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/features/community/application/topic_queries.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/features/community/presentation/community_search_field.dart';
import 'package:pili_aurora_next/features/community/presentation/community_picker_memory.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/discovery_footer.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/dynamics_select_topic/widgets/item.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/extension/scroll_controller_ext.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

class SelectTopicPanel extends ConsumerStatefulWidget {
  const SelectTopicPanel({
    super.key,
    this.scrollController,
    this.onCachePos,
    this.memory,
  });

  final ScrollController? scrollController;
  final ValueChanged<double>? onCachePos;
  final CommunityPickerMemory<void>? memory;

  static Future<TopicItem?> onSelectTopic(
    BuildContext context, {
    double offset = 0,
    ValueChanged<double>? onCachePos,
    CommunityPickerMemory<void>? memory,
  }) {
    return showModalBottomSheet<TopicItem?>(
      context: Get.context!,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(600, context.mediaQueryShortestSide),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        snap: true,
        minChildSize: 0,
        maxChildSize: 1,
        initialChildSize: offset == 0 ? 0.65 : 1,
        initialScrollOffset: offset,
        snapSizes: const [0.65],
        builder: (context, scrollController) => SelectTopicPanel(
          scrollController: scrollController,
          onCachePos: onCachePos,
          memory: memory,
        ),
      ),
    );
  }

  @override
  ConsumerState<SelectTopicPanel> createState() => _SelectTopicPanelState();
}

class _SelectTopicPanelState extends ConsumerState<SelectTopicPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  late final _fallbackScroll = ScrollController();
  ScrollController get _scroll => widget.scrollController ?? _fallbackScroll;
  CommunityLookup _query = (owner: Object(), keyword: '', debounce: false);
  bool _restorePosition = true;
  @override
  void initState() {
    super.initState();
    _text.text = widget.memory?.keyword ?? '';
    _query = (owner: Object(), keyword: _text.text, debounce: false);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _fallbackScroll.dispose();
    super.dispose();
  }

  void _search(String value, {bool debounce = true}) {
    widget.memory?.keyword = value;
    _restorePosition = false;
    setState(
      () => _query = (owner: Object(), keyword: value, debounce: debounce),
    );
    _scroll.jumpToTop();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final account = ref.watch(mainAccountProvider);
    final provider = topicSearchProvider(_query);
    final snapshot = ref.watch(provider);
    if (_restorePosition &&
        snapshot.loading is Success &&
        !snapshot.loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _query != query ||
            !_scroll.hasClients ||
            !_restorePosition) {
          return;
        }
        final target = _scroll.initialScrollOffset;
        final latest = ref.read(provider);
        // 深层缓存位置可能跨越多页；先补齐原位置所需内容，再恢复滚动。
        if (target > _scroll.position.maxScrollExtent && latest.hasMore) {
          if (latest.canLoadMore) ref.read(provider.notifier).onLoadMore();
          return;
        }
        _restorePosition = false;
        _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      });
    }
    return Column(
      children: [
        CommunitySearchField(
          controller: _text,
          focusNode: _focus,
          hint: '搜索话题',
          onChanged: _search,
          onClear: () {
            _text.clear();
            _search('', debounce: false);
          },
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification) _focus.unfocus();
              if (notification is ScrollEndNotification) {
                widget.onCachePos?.call(notification.metrics.pixels);
              }
              return false;
            },
            child: FeedPagination(
              controller: _scroll,
              dataSource: snapshot.source,
              dataRevision: snapshot,
              canLoadMore: () => ref.read(provider).canLoadMore,
              onLoadMore: ref.read(provider.notifier).onLoadMore,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  switch (snapshot.loading) {
                    Loading() => const SliverFillRemaining(
                      child: Center(child: m3eLoading),
                    ),
                    Success(:final response) when response.isNotEmpty =>
                      SliverList.builder(
                        itemCount: response.length,
                        itemBuilder: (context, index) => DynTopicItem(
                          item: response[index],
                          onTap: (item) {
                            if (_query == query &&
                                identical(
                                  account,
                                  ref.read(mainAccountProvider),
                                ) &&
                                identical(
                                  snapshot.source,
                                  ref.read(provider).source,
                                )) {
                              Navigator.of(context).pop(item);
                            }
                          },
                        ),
                      ),
                    _ => HttpError(
                      errMsg: snapshot.loading is Error
                          ? (snapshot.loading as Error).errMsg
                          : null,
                      onReload: ref.read(provider.notifier).onReload,
                    ),
                  },
                  DiscoveryFooter(
                    error: snapshot.error,
                    retry: ref.read(provider.notifier).retry,
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.viewPaddingOf(context).bottom + 100,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
