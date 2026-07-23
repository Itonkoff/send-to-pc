class DiscoveredDevice {
  const DiscoveredDevice({
    required this.deviceId,
    required this.deviceName,
    required this.host,
    required this.port,
    required this.protocolVersion,
    required this.seenAt,
  });

  final String deviceId;
  final String deviceName;
  final String host;
  final int port;
  final int protocolVersion;
  final DateTime seenAt;
}

