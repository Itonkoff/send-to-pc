class PairingPayload {
  const PairingPayload({
    required this.protocolVersion,
    required this.deviceId,
    required this.deviceName,
    required this.host,
    required this.port,
    required this.pairingToken,
    required this.certificateFingerprint,
    required this.expiresAt,
    this.hostAlternatives = const <String>[],
  });

  final int protocolVersion;
  final String deviceId;
  final String deviceName;
  final String host;
  final int port;
  final String pairingToken;
  final String certificateFingerprint;
  final DateTime expiresAt;
  final List<String> hostAlternatives;

  factory PairingPayload.fromJson(Map<String, dynamic> json) {
    return PairingPayload(
      protocolVersion: json['protocolVersion'] as int,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      pairingToken: json['pairingToken'] as String,
      certificateFingerprint: json['certificateFingerprint'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      hostAlternatives: (json['hostAlternatives'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'protocolVersion': protocolVersion,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'host': host,
      'hostAlternatives': hostAlternatives,
      'port': port,
      'pairingToken': pairingToken,
      'certificateFingerprint': certificateFingerprint,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }
}