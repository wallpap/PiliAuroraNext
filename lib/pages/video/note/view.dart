import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/skeleton/video_reply.dart';
import 'package:pili_aurora_next/common/sliver_single_child_delegate.dart';
import 'package:pili_aurora_next/common/widgets/feed_pagination.dart';
import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/mini_scaffold.dart';
import 'package:pili_aurora_next/features/community/application/video_notes.dart';
import 'package:pili_aurora_next/features/community/domain/video_note.dart';
import 'package:pili_aurora_next/models/common/image_type.dart';
import 'package:pili_aurora_next/pages/common/slide/common_slide_page.dart';
import 'package:pili_aurora_next/pages/webview/view.dart';
import 'package:pili_aurora_next/features/account/application/account_providers.dart';
import 'package:pili_aurora_next/utils/bili_utils.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class NoteListPage extends CommonSlidePage {
  const NoteListPage({
    super.key,
    super.enableSlide,
    required this.oid,
    required this.isStein,
    required this.title,
  });

  final int oid;
  final bool isStein;
  final String? title;

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage>
    with SingleTickerProviderStateMixin, CommonSlideMixin<NoteListPage> {
  final _owner = Object();
  VideoNotesQuery get _query => (owner: _owner, oid: widget.oid);

  @override
  Widget buildPage(ThemeData theme) {
    return Material(
      child: MiniScaffold(
        body: Column(
          children: [
            Container(
              height: 45,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final provider = videoNotesProvider(_query);
                        ref.watch(provider);
                        final count = ref
                            .read(provider.notifier)
                            .displayState
                            ?.metadata;
                        return Text(
                          '笔记${count == null ? '' : '($count)'}',
                          style: const TextStyle(fontSize: 16),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: Get.back,
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
            Expanded(child: enableSlide ? slideList(theme) : buildList(theme)),
          ],
        ),
      ),
    );
  }

  late Key _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _key = ObjectKey(PrimaryScrollController.maybeOf(context));
  }

  @override
  Widget buildList(ThemeData theme) => Consumer(
    builder: (context, ref, _) {
      final provider = videoNotesProvider(_query);
      final value = ref.watch(provider);
      final notes = ref.read(provider.notifier);
      final data = notes.displayState;
      final canWrite = ref.watch(
        mainAccountProvider.select((account) => account.isLogin),
      );
      Future<void> refresh() async {
        try {
          await notes.refresh();
        } catch (_) {
          // 失败由查询状态显示。
        }
      }

      final child = FeedPagination.notifications(
        dataSource: data?.source,
        dataRevision: data,
        canLoadMore: () =>
            !value.isLoading && !value.hasError && data?.canLoadMore == true,
        onLoadMore: notes.loadMore,
        child: refreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            key: _key,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildBody(
                theme,
                data?.items ?? const [],
                value.isLoading && data == null,
                data == null ? value.error?.toString() : null,
                refresh,
                canContinue: data?.error != null && !value.hasError,
              ),
              if (data != null && value.hasError)
                _retryFooter('${value.error}', refresh)
              else if (data?.error case final error?)
                _retryFooter('$error', () => notes.loadMore(retry: true)),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      );
      return canWrite ? _withEditorButton(context, theme, child) : child;
    },
  );

  Widget _retryFooter(String message, Future<void> Function() retry) =>
      SliverToBoxAdapter(
        child: TextButton(
          onPressed: retry,
          child: Text('$message，点击重试'),
        ),
      );

  Widget _withEditorButton(
    BuildContext context,
    ThemeData theme,
    Widget child,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        Container(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 6,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 6,
          ),
          decoration: BoxDecoration(
            color: theme.hoverColor,
            border: Border(
              top: BorderSide(
                width: 0.5,
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Builder(
            builder: (context) => FilledButton.tonal(
              style: FilledButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
              ),
              onPressed: () => _onTakeNote(context),
              child: const Text('开始记笔记'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    ThemeData theme,
    List<VideoNote> items,
    bool loading,
    String? error,
    Future<void> Function() refresh, {
    required bool canContinue,
  }) {
    if (loading) {
      return const SliverPrototypeExtentList(
        prototypeItem: VideoReplySkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 8,
          child: VideoReplySkeleton(),
        ),
      );
    }
    if (items.isEmpty && !canContinue) {
      return HttpError(errMsg: error, onReload: refresh);
    }
    final divider = Divider(
      height: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    );
    return SliverList.separated(
      itemBuilder: (context, index) => _itemWidget(theme, items[index]),
      itemCount: items.length,
      separatorBuilder: (context, index) => divider,
    );
  }

  Widget _itemWidget(ThemeData theme, VideoNote item) {
    final mid = item.authorId;
    void openAuthor() => Get.toNamed('/member?mid=$mid');
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => Get.toNamed(
          '/articlePage',
          parameters: {
            'id': item.id.toString(),
            'type': 'read',
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: mid == null ? null : openAuthor,
                child: NetworkImgLayer(
                  height: 34,
                  width: 34,
                  src: item.authorAvatar,
                  type: ImageType.avatar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: mid == null ? null : openAuthor,
                      child: Row(
                        children: [
                          Text(
                            item.authorName ?? '',
                            style: TextStyle(
                              color: item.vipAuthor
                                  ? theme.colorScheme.vipColor
                                  : theme.colorScheme.outline,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (item.authorLevel case final level?)
                            BiliUtils.levelPicture(
                              level,
                              isSeniorMember: item.seniorAuthor,
                              height: 11,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.publishedAt case final publishedAt?)
                      Text(
                        publishedAt,
                        style: TextStyle(
                          color: theme.colorScheme.outline,
                          fontSize: 12,
                        ),
                      ),
                    if (item.summary != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.summary!,
                        style: TextStyle(
                          height: 1.75,
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                        ),
                      ),
                      Text(
                        '查看全部',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          height: 1.75,
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTakeNote(BuildContext context) {
    final url =
        'https://www.bilibili.com/h5/note-app?oid=${widget.oid}&pagefrom=ugcvideo&is_stein_gate=${widget.isStein ? 1 : 0}';
    MiniScaffold.of(context).showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => WebviewPage(oid: widget.oid, title: widget.title, url: url),
    );
  }
}
