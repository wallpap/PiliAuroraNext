import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';
import 'package:pili_aurora_next/services/settings/stored_preferences.dart';

abstract final class MessagingPreferences {
  static bool get hideLikes => Pref.disableLikeMsg;
}

/// 本地入口与角标共用偏好，独立于账号的远端消息接收设置。
final disableLikeMessagesProvider = NotifierProvider<DisableLikeMessages, bool>(
  DisableLikeMessages.new,
  isAutoDispose: true,
);

class DisableLikeMessages extends Notifier<bool> {
  @override
  bool build() {
    final subscription = GStorage.setting
        .watch(key: SettingBoxKey.disableLikeMsg)
        .listen((_) => state = MessagingPreferences.hideLikes);
    ref.onDispose(subscription.cancel);
    return MessagingPreferences.hideLikes;
  }
}
