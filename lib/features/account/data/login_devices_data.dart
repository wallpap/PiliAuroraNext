import 'package:pili_aurora_next/features/account/domain/login_device.dart';

class LoginDevicesData {
  final List<LoginDevice>? devices;

  LoginDevicesData({this.devices});

  factory LoginDevicesData.fromJson(Map<String, dynamic> json) =>
      LoginDevicesData(
        devices: (json['devices'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map(
              (json) => LoginDevice(
                deviceName: json['device_name'] as String?,
                isCurrentDevice: json['is_current_device'] as bool?,
                latestLoginAt: json['latest_login_at'] as String?,
                source: json['source'] as String?,
              ),
            )
            .toList(),
      );
}
