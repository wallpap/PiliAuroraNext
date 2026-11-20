class LoginDevice {
  final String? deviceName;
  final bool? isCurrentDevice;
  final String? latestLoginAt;
  final String? source;

  const LoginDevice({
    this.deviceName,
    this.isCurrentDevice,
    this.latestLoginAt,
    this.source,
  });
}
