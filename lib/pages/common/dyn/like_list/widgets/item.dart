import 'package:pili_aurora_next/common/widgets/pendant_avatar.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_item.dart';
import 'package:pili_aurora_next/utils/bili_utils.dart';
import 'package:pili_aurora_next/utils/extension/theme_ext.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

class DynLikeItem extends StatelessWidget {
  const DynLikeItem({super.key, required this.item});

  final DynamicActivityAuthor item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final author = item;
    final sign = author.sign;
    return Material(
      type: .transparency,
      child: InkWell(
        onTap: () => Get.toNamed('/member?mid=${item.mid}'),
        child: Column(
          crossAxisAlignment: sign != null ? .center : .start,
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
                  ),
                  Expanded(
                    child: Column(
                      spacing: 2,
                      crossAxisAlignment: .start,
                      children: [
                        Row(
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
                                      : null,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            BiliUtils.levelPicture(
                              author.level,
                              isSeniorMember: author.isSeniorMember,
                              height: 11,
                            ),
                          ],
                        ),
                        if (sign != null)
                          Text(
                            sign,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
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
