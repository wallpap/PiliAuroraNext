import 'dart:math';

import 'package:pili_aurora_next/common/widgets/emote_tooltip.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show tabBarView, platformClampingPhysics;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/common/widgets/image/image_type.dart';
import 'package:pili_aurora_next/features/community/domain/live_emote/datum.dart';
import 'package:pili_aurora_next/features/community/domain/live_emote/emoticon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/live_emote_panel.dart';
import 'package:material_ui/material_ui.dart';

class LiveEmotePanel extends ConsumerStatefulWidget {
  final int roomId;
  final Function(Emoticon emote, double? width, double? height) onChoose;
  final ValueChanged<Emoticon> onSendEmoticonUnique;
  const LiveEmotePanel({
    super.key,
    required this.roomId,
    required this.onChoose,
    required this.onSendEmoticonUnique,
  });

  @override
  ConsumerState<LiveEmotePanel> createState() => _LiveEmotePanelState();
}

class _LiveEmotePanelState extends ConsumerState<LiveEmotePanel>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  LiveEmoteQuery get _query => (owner: _owner, roomId: widget.roomId);
  Future<void> _reload() =>
      ref.read(liveEmotePackagesProvider(_query).notifier).onRefresh();
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(liveEmotePackagesProvider(_query));
    final packages = state.loading.dataOrNull;
    if (packages == null || packages.isEmpty) return _buildBody(state.loading);
    return DefaultTabController(
      key: ObjectKey(packages),
      length: packages.length,
      child: _buildBody(state.loading),
    );
  }

  Widget _buildBody(LoadingState<List<LiveEmoteDatum>> loadingState) {
    late final theme = Theme.of(context);
    return switch (loadingState) {
      Loading() => m3eLoading,
      Success(:final response) =>
        response.isNotEmpty
            ? Column(
                children: [
                  Expanded(
                    child: tabBarView(
                      children: response.map(
                        (item) {
                          final emote = item.emoticons;
                          if (emote == null || emote.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final first = emote.first;
                          final widthFac = first.width == null
                              ? 1.0
                              : max(1.0, first.width! / 80);
                          final heightFac = first.height == null
                              ? 1.0
                              : max(1.0, first.height! / 80);
                          final width = widthFac * 38;
                          final height = heightFac * 38;
                          return GridView.builder(
                            physics: platformClampingPhysics,
                            padding: const .all(12),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: widthFac * 40,
                                  mainAxisExtent: heightFac * 40,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: emote.length,
                            itemBuilder: (context, index) {
                              final e = emote[index];
                              return Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(6),
                                  ),
                                  onTap: () {
                                    if (item.pkgType == 3) {
                                      widget.onChoose(e, width, height);
                                    } else {
                                      widget.onSendEmoticonUnique(e);
                                    }
                                  },
                                  child: emoteTooltipBuilder(
                                    enable: true,
                                    size: 70,
                                    colorScheme: theme.colorScheme,
                                    url: e.url,
                                    emote: e.emoji,
                                    triggerMode: kTriggerMode,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: NetworkImgLayer(
                                        fit: BoxFit.contain,
                                        src: e.url,
                                        width: width,
                                        height: height,
                                        type: ImageType.emote,
                                        quality: item.pkgType == 3 ? 1 : 80,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ).toList(),
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                  TabBar(
                    padding: const EdgeInsets.only(right: 60),
                    dividerColor: Colors.transparent,
                    dividerHeight: 0,
                    isScrollable: true,
                    tabs: response
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.all(8),
                            child: NetworkImgLayer(
                              width: 24,
                              height: 24,
                              type: ImageType.emote,
                              src: item.currentCover,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
                ],
              )
            : _errorWidget(),
      Error(:final errMsg) => _errorWidget(errMsg),
    };
  }

  Widget _errorWidget([String? errMsg]) => Center(
    child: TextButton.icon(
      onPressed: _reload,
      icon: const Icon(Icons.refresh),
      label: Text(errMsg ?? '没有数据'),
    ),
  );
}
