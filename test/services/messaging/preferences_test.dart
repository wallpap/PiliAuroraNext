import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pili_aurora_next/services/messaging/preferences.dart';
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/services/settings/storage_key.dart';

void main() {
  test('赞消息偏好在现有订阅中立即更新，释放后重建读取最新值', () async {
    GStorage.setting = await Hive.openBox(
      'message-preferences',
      bytes: Uint8List(0),
    );
    final container = ProviderContainer();
    final values = <bool>[];
    final subscription = container.listen(
      disableLikeMessagesProvider,
      (_, next) => values.add(next),
      fireImmediately: true,
    );
    await GStorage.setting.put(SettingBoxKey.disableLikeMsg, true);
    await Future<void>.delayed(Duration.zero);
    expect(values, [false, true]);
    subscription.close();
    container.dispose();
    final next = ProviderContainer();
    expect(next.read(disableLikeMessagesProvider), isTrue);
    next.dispose();
    await GStorage.setting.close();
  });
}
