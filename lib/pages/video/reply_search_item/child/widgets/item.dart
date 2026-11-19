import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/badge.dart';
import 'package:pili_aurora_next/common/widgets/image/image_save.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/features/community/domain/reply_search.dart';
import 'package:pili_aurora_next/models/common/badge_type.dart';
import 'package:pili_aurora_next/utils/duration_utils.dart';
import 'package:pili_aurora_next/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class ReplySearchItem extends StatelessWidget {
  const ReplySearchItem({super.key, required this.item});

  final ReplySearchEntry item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () =>
            Navigator.of(context).pop((title: item.title, url: item.url)),
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: Style.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    return Stack(
                      children: [
                        NetworkImgLayer(
                          src: item.cover,
                          width: boxConstraints.maxWidth,
                          height: boxConstraints.maxHeight,
                        ),
                        if (item.category case final category?)
                          PBadge(
                            right: 6,
                            top: 6,
                            text: category,
                          ),
                        if (item.duration case final duration?)
                          PBadge(
                            right: 6,
                            bottom: 6,
                            text: DurationUtils.formatDuration(duration),
                            type: PBadgeType.gray,
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.author case final author?)
                      Text(
                        'UP: $author',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
