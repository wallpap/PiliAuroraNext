import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/features/account/application/account_preferences.dart';
import 'package:pili_aurora_next/features/account/application/account_profile.dart';
import 'package:pili_aurora_next/features/app_shell/application/shell_badges.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/services/messaging/overview.dart';
import 'package:pili_aurora_next/services/messaging/preferences.dart';

Widget userAvatar({
  required ColorScheme colorScheme,
  required VoidCallback onOpenMine,
}) {
  return Semantics(
    label: "我的",
    child: Consumer(
      builder: (context, ref, child) {
        final info = ref.watch(accountProfileProvider).info;
        final incognito = ref.watch(incognitoProvider);
        if (ref.watch(mainAccountProvider).isLogin) {
          return Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                type: .avatar,
                width: 34,
                height: 34,
                src: info?.face ?? '',
              ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: onOpenMine,
                    splashColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    customBorder: const CircleBorder(),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Builder(
                  builder: (context) => incognito
                      ? IgnorePointer(
                          child: Container(
                            padding: const .all(2),
                            decoration: BoxDecoration(
                              shape: .circle,
                              color: colorScheme.secondaryContainer,
                            ),
                            child: Icon(
                              size: 14,
                              MdiIcons.incognito,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: '点击登录',
            style: IconButton.styleFrom(
              padding: .zero,
              backgroundColor: colorScheme.onInverseSurface,
            ),
            onPressed: onOpenMine,
            icon: Icon(
              Icons.person_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
          ),
        );
      },
    ),
  );
}

class MessageBadge extends ConsumerWidget {
  const MessageBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLogin = ref.watch(mainAccountProvider).isLogin;
    if (!isLogin) return const SizedBox.shrink();
    final unread = ref.watch(overviewProvider);
    final disableLike = ref.watch(disableLikeMessagesProvider);
    final badges = ref.watch(shellBadgesProvider);
    return ValueListenableBuilder(
      valueListenable: badges.message,
      builder: (context, preferences, _) {
        final total = unread.total(
          preferences.types,
          disableLike: disableLike,
        );
        final count = total == null || total == 0
            ? null
            : total > 99
            ? '99+'
            : '$total';
        final isNumBadge = preferences.mode == .number;
        return IconButton(
          tooltip: '消息',
          onPressed: () {
            badges.messagesOpened();
            Get.toNamed('/whisper');
          },
          icon: Badge(
            isLabelVisible: preferences.mode != .hidden && count != null,
            alignment: isNumBadge
                ? const Alignment(0.0, -0.85)
                : const Alignment(1.0, -0.85),
            label: isNumBadge && count != null ? Text(count) : null,
            child: const Icon(Icons.notifications_none),
          ),
        );
      },
    );
  }
}
