import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/community/application/pgc_reviews.dart';
import 'package:pili_aurora_next/features/community/domain/pgc_review.dart';
import 'package:pili_aurora_next/pages/pgc_review/child/view.dart';
import 'package:pili_aurora_next/pages/pgc_review/post/view.dart';
import 'package:pili_aurora_next/common/widgets/extensions/scroll_controller_ext.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PgcReviewPage extends ConsumerStatefulWidget {
  const PgcReviewPage({
    super.key,
    required this.name,
    required this.mediaId,
  });

  final String name;
  final Object? mediaId;

  @override
  ConsumerState<PgcReviewPage> createState() => _PgcReviewPageState();
}

class _PgcReviewPageState extends ConsumerState<PgcReviewPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  final _owner = Object();
  final _scrollControllers = [
    for (final _ in PgcReviewType.values) ScrollController(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: PgcReviewType.values.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final scroll in _scrollControllers) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return SimpleScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerHeight: 0,
            indicatorWeight: 0,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            padding: const EdgeInsets.only(left: 6),
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 8,
            ),
            indicator: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: theme.colorScheme.onSecondaryContainer,
            unselectedLabelColor: theme.colorScheme.outline,
            labelStyle:
                TabBarTheme.of(
                  context,
                ).labelStyle?.copyWith(fontSize: 13) ??
                const TextStyle(fontSize: 13),
            dividerColor: Colors.transparent,
            tabs: PgcReviewType.values.map((e) => Tab(text: e.label)).toList(),
            onTap: (index) {
              if (!_tabController.indexIsChanging) {
                _scrollControllers[index].animToTop();
              }
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: PgcReviewType.values
                  .map(
                    (e) => PgcReviewChildPage(
                      type: e,
                      key: ValueKey((widget.mediaId, e)),
                      owner: _owner,
                      scrollController: _scrollControllers[e.index],
                      name: widget.name,
                      mediaId: widget.mediaId,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      fab: Padding(
        padding: .only(
          right: kFloatingActionButtonMargin,
          bottom:
              MediaQuery.viewPaddingOf(context).bottom +
              kFloatingActionButtonMargin,
        ),
        child: FloatingActionButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => SimpleDialog(
              clipBehavior: Clip.hardEdge,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                DialogOption(
                  child: const Text('写短评', style: TextStyle(fontSize: 14)),
                  onPressed: () {
                    final mediaId = widget.mediaId;
                    Get.back();
                    showModalBottomSheet(
                      context: context,
                      useSafeArea: true,
                      isScrollControlled: true,
                      builder: (context) {
                        return PgcReviewPostPanel(
                          name: widget.name,
                          mediaId: mediaId,
                          onSubmitted: () {
                            if (!mounted || widget.mediaId != mediaId) return;
                            ref.invalidate(
                              pgcReviewsProvider((
                                owner: _owner,
                                mediaId: mediaId,
                                type: .short,
                              )),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                DialogOption(
                  child: const Text('写长评', style: TextStyle(fontSize: 14)),
                  onPressed: () => Get
                    ..back()
                    ..toNamed(
                      '/webview',
                      parameters: {
                        'url':
                            'https://member.bilibili.com/article-text/mobile?theme=${theme.isDark ? 1 : 0}&media_id=${widget.mediaId}',
                      },
                    ),
                ),
              ],
            ),
          ),
          child: const Icon(Icons.edit),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
