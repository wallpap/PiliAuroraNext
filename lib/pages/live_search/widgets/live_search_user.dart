import 'package:pili_aurora_next/common/assets.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/image/image_type.dart';
import 'package:pili_aurora_next/features/search/domain/live/user_item.dart';
import 'package:pili_aurora_next/common/layout/num_ext.dart';
import 'package:pili_aurora_next/core/text/number_format.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:material_ui/material_ui.dart';

class LiveSearchUserItem extends StatelessWidget {
  const LiveSearchUserItem({
    super.key,
    required this.item,
  });

  final LiveSearchUserItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.outline,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => PageUtils.toLiveRoom(item.roomid),
        child: Row(
          children: [
            const SizedBox(width: 15),
            NetworkImgLayer(
              src: item.face,
              width: 42,
              height: 42,
              type: ImageType.avatar,
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      item.name!,
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                    ),
                    if (item.liveStatus == 1) ...[
                      const SizedBox(width: 10),
                      Image.asset(
                        height: 14,
                        cacheHeight: 14.cacheSize(context),
                        Assets.livingRect,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '分区: ${item.areaName ?? ''}    关注数: ${NumUtils.numFormat(item.fansNum ?? 0)}',
                  style: style,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
