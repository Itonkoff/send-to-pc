class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.authenticationToken,
    this.certificateFingerprint,
    this.lastKnownAddress,
    this.lastKnownPort,
    this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
    this.isTrusted = true,
    this.isRevoked = false,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String authenticationToken;
  final String? certificateFingerprint;
  final String? lastKnownAddress;
  final int? lastKnownPort;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isTrusted;
  final bool isRevoked;

  PairedDevice copyWith({
    String? id,
    String? deviceId,
    String? deviceName,
    String? platform,
    String? authenticationToken,
    String? certificateFingerprint,
    String? lastKnownAddress,
    int? lastKnownPort,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isTrusted,
    bool? isRevoked,
  }) {
    return PairedDevice(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      authenticationToken: authenticationToken ?? this.authenticationToken,
      certificateFingerprint:
          certificateFingerprint ?? this.certificateFingerprint,
      lastKnownAddress: lastKnownAddress ?? this.lastKnownAddress,
      lastKnownPort: lastKnownPort ?? this.lastKnownPort,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isTrusted: isTrusted ?? this.isTrusted,
      isRevoked: isRevoked ?? this.isRevoked,
    );
  }

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
      authenticationToken: json['authenticationToken'] as String,
      certificateFingerprint: json['certificateFingerprint'] as String?,
      lastKnownAddress: json['lastKnownAddress'] as String?,
      lastKnownPort: _intOrNull(json['lastKnownPort']),
      lastSeenAt: _dateTimeOrNull(json['lastSeenAt']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isTrusted: (json['isTrusted'] as bool?) ?? true,
      isRevoked: (json['isRevoked'] as bool?) ?? false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
      'authenticationToken': authenticationToken,
      'certificateFingerprint': certificateFingerprint,
      'lastKnownAddress': lastKnownAddress,
      'lastKnownPort': lastKnownPort,
      'lastSeenAt': lastSeenAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isTrusted': isTrusted,
      'isRevoked': isRevoked,
    };
  }
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String);
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}