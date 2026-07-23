class DeviceInfo {
  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.protocolVersion,
    required this.serverVersion,
    required this.requiresAuthentication,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final int protocolVersion;
  final String serverVersion;
  final bool requiresAuthentication;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
      protocolVersion: json['protocolVersion'] as int,
      serverVersion:
          (json['serverVersion'] ?? json['appVersion'] ?? '0.1.0') as String,
      requiresAuthentication:
          (json['requiresAuthentication'] as bool?) ?? true,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'protocolVersion': protocolVersion,
      'serverVersion': serverVersion,
      'requiresAuthentication': requiresAuthentication,
    };
  }
}

