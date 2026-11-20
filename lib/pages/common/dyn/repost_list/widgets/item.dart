import 'package:pili_aurora_next/common/widgets/emote_tooltip.dart';
import 'package:pili_aurora_next/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/image_grid/image_grid_view.dart';
import 'package:pili_aurora_next/common/widgets/pendant_avatar.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_item.dart';
import 'package:pili_aurora_next/pages/dynamics/widgets/vote.dart';
import 'package:pili_aurora_next/router/app_scheme.dart';
import 'package:pili_aurora_next/common/widgets/svg/level_icon.dart';
import 'package:pili_aurora_next/common/appearance/theme_ext.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

class DynRepostItem extends StatelessWidget {
  const DynRepostItem({
    super.key,
    required this.item,
  });

  final DynamicRepostEntry item;

  @override
  Widget build(BuildContext context) {
    final author = item.author;
    if (author == null) {
      return const SizedBox.shrink();
    }
    final content = item.content;
    final colorScheme = ColorScheme.of(context);
    void pushMember() => Get.toNamed('/member?mid=${author.mid}');

    return Material(
      type: .transparency,
      child: InkWell(
        onTap: () => PageUtils.pushDynFromId(id: item.id),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: const .symmetric(horizontal: 12, vertical: 10),
              child: Row(
                spacing: 12,
                crossAxisAlignment: .start,
                children: [
                  PendantAvatar(
                    author.face,
                    size: 34,
                    badgeSize: 14,
                    pendantImage: author.pendantImage,
                    vipStatus: author.vipStatus,
                    officialType: author.officialType,
                    onTap: pushMember,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        GestureDetector(
                          behavior: .translucent,
                          onTap: pushMember,
                          child: Row(
                            mainAxisSize: .min,
                            spacing: 6,
                            children: [
                              Flexible(
                                child: Text(
                                  author.name,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: TextStyle(
                                    color: author.hasAnnualVip
                                        ? colorScheme.vipColor
                                        : colorScheme.outline,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              memberLevelPicture(
                                author.level,
                                isSeniorMember: author.isSeniorMember,
                                height: 11,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item.timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                          ),
                        ),
                        if (content != null) ...[
                          const SizedBox(height: 6),
                          Text.rich(
                            style: const TextStyle(height: 1.75),
                            TextSpan(
                              children: _buildContent(
                                context,
                                colorScheme,
                                content,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              indent: 60,
              endIndent: 15,
              height: 0.3,
              color: colorScheme.outline.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }
}

List<InlineSpan> _buildContent(
  BuildContext context,
  ColorScheme colorScheme,
  List<RepostContent> content,
) => [
  for (final entry in content)
    ...switch (entry) {
      RepostText(:final text) => [TextSpan(text: text)],
      RepostEmote(:final text, :final url, :final scale) => [
        WidgetSpan(
          child: emoteTooltipBuilder(
            triggerMode: .tap,
            url: url,
            emote: text,
            colorScheme: colorScheme,
            child: NetworkImgLayer(
              src: url,
              width: scale * 20.0,
              height: scale * 20.0,
              type: .emote,
            ),
          ),
        ),
      ],
      RepostImages(:final images) => [
        const TextSpan(text: '\n'),
        WidgetSpan(
          child: ImageGridView(
            picArr: [
              for (final image in images)
                ImageModel(
                  url: image.url,
                  width: image.width,
                  height: image.height,
                ),
            ],
          ),
        ),
      ],
      RepostVote(:final title, :final id) => [
        WidgetSpan(
          alignment: .middle,
          child: Icon(
            Icons.bar_chart_rounded,
            size: 20,
            color: colorScheme.primary,
          ),
        ),
        TextSpan(
          text: '投票：$title',
          style: TextStyle(color: colorScheme.primary),
          recognizer: (NoDeadlineTapGestureRecognizer()
            ..onTap = () => showVoteDialog(context, id)),
        ),
      ],
      RepostLink(:final text, :final url, :final kind) => [
        if (kind != .plain)
          WidgetSpan(
            alignment: .middle,
            child: Icon(
              kind == .external
                  ? Icons.link
                  : Icons.play_circle_outline_outlined,
              size: kind == .external ? 20 : 16,
              color: colorScheme.primary,
            ),
          ),
        TextSpan(
          text: text,
          style: TextStyle(color: colorScheme.primary),
          recognizer: (NoDeadlineTapGestureRecognizer()
            ..onTap = () => PiliScheme.routePushFromUrl(url)),
        ),
      ],
    },
];
