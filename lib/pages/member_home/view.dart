import 'dart:math';

import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/button/more_btn.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scroll_physics.dart'
    show platformAlwaysClampingPhysics;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/data.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/setting.dart';
import 'package:pili_aurora_next/pages/member_article/widget/item.dart';
import 'package:pili_aurora_next/pages/member_audio/widgets/item.dart';
import 'package:pili_aurora_next/pages/member_coin_arc/view.dart';
import 'package:pili_aurora_next/pages/member_comic/widgets/item.dart';
import 'package:pili_aurora_next/pages/member_home/widgets/fav_item.dart';
import 'package:pili_aurora_next/pages/member_home/widgets/video_card_v_member_home.dart';
import 'package:pili_aurora_next/pages/member_like_arc/view.dart';
import 'package:pili_aurora_next/pages/member_pgc/widgets/pgc_card_v_member_pgc.dart';
import 'package:pili_aurora_next/common/widgets/extensions/context_ext.dart';
import 'package:pili_aurora_next/common/layout/grid.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MemberHome extends StatefulWidget {
  const MemberHome({
    super.key,
    required this.data,
    required this.mid,
    required this.name,
    required this.setting,
    required this.openSection,
  });

  final SpaceData? data;
  final int mid;
  final String? name;
  final SpaceSetting? setting;
  final bool Function(String section, String? contribution) openSection;

  @override
  State<MemberHome> createState() => _MemberHomeState();
}

class _MemberHomeState extends State<MemberHome>
    with AutomaticKeepAliveClientMixin, GridMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildBody(Success(widget.data));
  }

  late final gridDelegateV = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Grid.smallCardWidth,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(55),
  );

  late final gridDelegateAudio = Grid.videoCardHDelegate();

  late final gridDelegatePgc = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Grid.smallCardWidth * 0.6,
    childAspectRatio: 0.75,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(52),
  );

  Widget _buildBody(LoadingState<SpaceData?> loadingState) {
    final isVertical = context.width < 600;
    final setting = widget.setting;
    final isOwner = setting != null;
    final color = Theme.of(context).colorScheme.outline;
    return switch (loadingState) {
      Loading() => m3eLoading,
      Success(response: final res) =>
        res != null
            ? CustomScrollView(
                physics: platformAlwaysClampingPhysics,
                slivers: [
                  if (res.archive?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '视频',
                      param: 'contribute',
                      param1: 'video',
                      count: res.archive!.count!,
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Style.safeSpace,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate: gridDelegateV,
                        itemBuilder: (context, index) {
                          return VideoCardVMemberHome(
                            videoItem: res.archive!.item![index],
                          );
                        },
                        itemCount: min(
                          isVertical ? 4 : 8,
                          res.archive!.item!.length,
                        ),
                      ),
                    ),
                  ],
                  if (res.favourite2?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '收藏',
                      param: 'favorite',
                      count: res.favourite2!.count!,
                      visible: isOwner ? setting.favVideo == 1 : null,
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 110,
                        child: MemberFavItem(
                          item: res.favourite2!.item!.first,
                        ),
                      ),
                    ),
                  ],
                  if (res.coinArchive?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '最近投币的视频',
                      param: 'coinArchive',
                      count: res.coinArchive!.count!,
                      visible: isOwner ? setting.coinsVideo == 1 : null,
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Style.safeSpace,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate: gridDelegateV,
                        itemBuilder: (context, index) {
                          return VideoCardVMemberHome(
                            videoItem: res.coinArchive!.item![index],
                          );
                        },
                        itemCount: min(
                          isVertical ? 2 : 4,
                          res.coinArchive!.item!.length,
                        ),
                      ),
                    ),
                  ],
                  if (res.likeArchive?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '最近点赞的视频',
                      param: 'likeArchive',
                      count: res.likeArchive!.count!,
                      visible: isOwner ? setting.likesVideo == 1 : null,
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Style.safeSpace,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate: gridDelegateV,
                        itemBuilder: (context, index) {
                          return VideoCardVMemberHome(
                            videoItem: res.likeArchive!.item![index],
                          );
                        },
                        itemCount: min(
                          isVertical ? 2 : 4,
                          res.likeArchive!.item!.length,
                        ),
                      ),
                    ),
                  ],
                  if (res.article?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '图文',
                      param: 'contribute',
                      param1: 'opus',
                      count: res.article!.count!,
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 110,
                        child: MemberArticleItem(
                          item: res.article!.item!.first,
                        ),
                      ),
                    ),
                  ],
                  if (res.audios?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '音频',
                      param: 'contribute',
                      param1: 'audio',
                      count: res.audios!.count!,
                    ),
                    SliverGrid.builder(
                      gridDelegate: gridDelegateAudio,
                      itemBuilder: (context, index) {
                        return MemberAudioItem(
                          item: res.audios!.item![index],
                        );
                      },
                      itemCount: isVertical ? 1 : min(3, res.audios!.count!),
                    ),
                  ],
                  if (res.comic?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '漫画',
                      param: 'contribute',
                      param1: 'comic',
                      count: res.comic!.count!,
                    ),
                    SliverGrid.builder(
                      gridDelegate: gridDelegate,
                      itemBuilder: (context, index) {
                        return MemberComicItem(item: res.comic!.item![index]);
                      },
                      itemCount: isVertical ? 1 : min(3, res.comic!.count!),
                    ),
                  ],
                  if (res.season?.item?.isNotEmpty == true) ...[
                    _header(
                      color,
                      title: '追番',
                      param: 'bangumi',
                      count: res.season!.count!,
                      visible: isOwner ? setting.bangumi == 1 : null,
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Style.safeSpace,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate: gridDelegatePgc,
                        itemBuilder: (context, index) {
                          return PgcCardVMemberPgc(
                            item: res.season!.item![index],
                          );
                        },
                        itemCount: min(
                          isVertical ? 3 : 6,
                          res.season!.item!.length,
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 100 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                  ),
                ],
              )
            : scrollableError,
      Error(:final errMsg) => scrollErrorWidget(errMsg: errMsg),
    };
  }

  Widget _header(
    Color color, {
    required String title,
    required String param,
    String? param1,
    required int count,
    bool? visible,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$title '),
                  TextSpan(
                    text: count.toString(),
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                  if (visible != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Icon(
                          visible ? Icons.visibility : Icons.visibility_off,
                          size: 17,
                          color: color,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            moreTextButton(
              onTap: () {
                if (!widget.openSection(param, param1)) {
                  if (param == 'coinArchive') {
                    Get.to(
                      MemberCoinArcPage(
                        mid: widget.mid,
                        name: widget.name,
                      ),
                    );
                    return;
                  }

                  if (param == 'likeArchive') {
                    Get.to(
                      MemberLikeArcPage(
                        mid: widget.mid,
                        name: widget.name,
                      ),
                    );
                    return;
                  }

                  // else
                  SmartDialog.showToast('view $param');
                }
              },
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
