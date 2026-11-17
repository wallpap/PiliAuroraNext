import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:pili_aurora_next/common/widgets/view_insets_safe_area.dart';
import 'package:pili_aurora_next/features/community/application/topic_queries.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_mention/group.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_mention/item.dart';
import 'package:pili_aurora_next/features/community/presentation/community_search_field.dart';
import 'package:pili_aurora_next/features/community/presentation/community_picker_memory.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/dynamics_mention/widgets/item.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/extension/context_ext.dart';
import 'package:pili_aurora_next/utils/extension/scroll_controller_ext.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

class DynMentionPanel extends ConsumerStatefulWidget {
  const DynMentionPanel({
    super.key,
    this.scrollController,
    this.onCachePos,
    this.memory,
  });

  final ScrollController? scrollController;
  final ValueChanged<double>? onCachePos;
  final CommunityPickerMemory<MentionItem>? memory;

  static Future<Object? /* ListOr<MentionItem> */> onDynMention(
    BuildContext context, {
    double offset = 0,
    ValueChanged<double>? onCachePos,
    CommunityPickerMemory<MentionItem>? memory,
  }) {
    return showModalBottomSheet(
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
        builder: (context, scrollController) => DynMentionPanel(
          scrollController: scrollController,
          onCachePos: onCachePos,
          memory: memory,
        ),
      ),
    );
  }

  @override
  ConsumerState<DynMentionPanel> createState() => _DynMentionPanelState();
}

class _DynMentionPanelState extends ConsumerState<DynMentionPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _fallbackScroll = ScrollController();
  ScrollController get _scroll => widget.scrollController ?? _fallbackScroll;
  CommunityLookup _query = (owner: Object(), keyword: '', debounce: false);
  final _selected = <String, MentionItem>{};
  bool _restorePosition = true;
  @override
  void initState() {
    super.initState();
    final memory = widget.memory;
    final account = ref.read(mainAccountProvider);
    if (memory != null) {
      if (!identical(memory.account, account)) memory.selected.clear();
      memory.account = account;
      _text.text = memory.keyword;
      for (final item in memory.selected) {
        if (item.uid != null) _selected[item.uid!] = item;
      }
    }
    _query = (owner: Object(), keyword: _text.text, debounce: false);
  }

  void _rememberSelection() {
    final memory = widget.memory;
    if (memory != null) {
      memory.selected
        ..clear()
        ..addAll(_selected.values);
    }
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
    widget.memory?.selected.clear();
    _restorePosition = false;
    setState(() {
      _selected.clear();
      _query = (owner: Object(), keyword: value, debounce: debounce);
    });
    _scroll.jumpToTop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mainAccountProvider, (previous, next) {
      if (!identical(previous, next)) {
        widget.memory?.account = next;
        widget.memory?.selected.clear();
        setState(_selected.clear);
      }
    });
    final provider = mentionSearchProvider(_query);
    final snapshot = ref.watch(provider);
    if (_restorePosition && snapshot.loading is Success) {
      _restorePosition = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            _scroll.initialScrollOffset.clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        CommunitySearchField(
          controller: _text,
          focusNode: _focus,
          hint: '输入你想@的人',
          onChanged: _search,
          onClear: () {
            _text.clear();
            _search('', debounce: false);
          },
        ),
        Expanded(
          child: ScaffoldLayout(
            body: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) _focus.unfocus();
                if (notification is ScrollEndNotification) {
                  widget.onCachePos?.call(notification.metrics.pixels);
                }
                return false;
              },
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  _body(theme, snapshot.loading, snapshot.source),
                  SliverToBoxAdapter(child: SizedBox(height: padding + 100)),
                ],
              ),
            ),
            fab: Padding(
              padding: EdgeInsets.only(
                right: kFloatingActionButtonMargin,
                bottom: kFloatingActionButtonMargin + padding,
              ),
              child: ViewInsetsSafeArea(
                child: AnimatedSlide(
                  offset: _selected.isNotEmpty
                      ? Offset.zero
                      : const Offset(0, 3),
                  duration: const Duration(milliseconds: 120),
                  child: FloatingActionButton(
                    onPressed: () {
                      if (_selected.isNotEmpty) {
                        final selected = Set<MentionItem>.of(_selected.values);
                        widget.memory?.selected.clear();
                        Navigator.of(context).pop(selected);
                      }
                    },
                    child: const Icon(Icons.check),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(
    ThemeData theme,
    LoadingState<List<MentionGroup>> loading,
    Object source,
  ) {
    final query = _query;
    final account = ref.read(mainAccountProvider);
    bool current() =>
        _query == query &&
        identical(account, ref.read(mainAccountProvider)) &&
        identical(source, ref.read(mentionSearchProvider(query)).source);
    return switch (loading) {
      Loading() => const SliverPadding(
        padding: EdgeInsets.only(top: 8),
        sliver: linearLoading,
      ),
      Success(:final response) when response.isNotEmpty => SliverMainAxisGroup(
        slivers: [
          for (final group in response)
            if (group.items?.isNotEmpty == true)
              SliverMainAxisGroup(
                slivers: [
                  SliverPinnedHeader(
                    backgroundColor: theme.bottomSheetTheme.backgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(group.groupName ?? ''),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: group.items!.length,
                    itemBuilder: (context, index) {
                      final item = group.items![index];
                      return DynMentionItem(
                        item: item,
                        selected: _selected.containsKey(item.uid),
                        onTap: () {
                          if (current()) Navigator.of(context).pop(item);
                        },
                        onCheck: (value) {
                          if (item.uid == null || !current()) return;
                          setState(() {
                            if (value == true) {
                              _selected[item.uid!] = item;
                            } else {
                              _selected.remove(item.uid);
                            }
                          });
                          _rememberSelection();
                        },
                      );
                    },
                  ),
                ],
              ),
        ],
      ),
      _ => HttpError(
        errMsg: loading is Error ? loading.errMsg : null,
        onReload: ref.read(mentionSearchProvider(_query).notifier).onReload,
      ),
    };
  }
}
