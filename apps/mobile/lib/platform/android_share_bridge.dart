import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_models/shared_models.dart';

class MobileAppSettings {
  const MobileAppSettings({
    required this.deviceName,
    this.defaultComputerId,
    required this.confirmBeforeSending,
    required this.wifiOnly,
    required this.historyRetentionDays,
  });

  const MobileAppSettings.defaults()
      : deviceName = 'Android phone',
        defaultComputerId = null,
        confirmBeforeSending = false,
        wifiOnly = false,
        historyRetentionDays = 30;

  final String deviceName;
  final String? defaultComputerId;
  final bool confirmBeforeSending;
  final bool wifiOnly;
  final int historyRetentionDays;

  MobileAppSettings copyWith({
    String? deviceName,
    String? defaultComputerId,
    bool clearDefaultComputerId = false,
    bool? confirmBeforeSending,
    bool? wifiOnly,
    int? historyRetentionDays,
  }) {
    return MobileAppSettings(
      deviceName: deviceName ?? this.deviceName,
      defaultComputerId: clearDefaultComputerId
          ? null
          : defaultComputerId ?? this.defaultComputerId,
      confirmBeforeSending:
          confirmBeforeSending ?? this.confirmBeforeSending,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      historyRetentionDays:
          historyRetentionDays ?? this.historyRetentionDays,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'deviceName': deviceName,
      'defaultComputerId': defaultComputerId,
      'confirmBeforeSending': confirmBeforeSending,
      'wifiOnly': wifiOnly,
      'historyRetentionDays': historyRetentionDays,
    };
  }

  factory MobileAppSettings.fromJson(Map<String, dynamic> json) {
    final deviceName = (json['deviceName'] as String?)?.trim();
    final defaultComputerId = (json['defaultComputerId'] as String?)?.trim();
    final retention = json['historyRetentionDays'];
    return MobileAppSettings(
      deviceName: deviceName == null || deviceName.isEmpty
          ? const MobileAppSettings.defaults().deviceName
          : deviceName,
      defaultComputerId: defaultComputerId == null || defaultComputerId.isEmpty
          ? null
          : defaultComputerId,
      confirmBeforeSending: json['confirmBeforeSending'] == true,
      wifiOnly: json['wifiOnly'] == true,
      historyRetentionDays: retention is num
          ? retention.toInt().clamp(1, 3650).toInt()
          : const MobileAppSettings.defaults().historyRetentionDays,
    );
  }
}

class AndroidShareBridge {
  AndroidShareBridge() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _channel = MethodChannel('send_to_pc/share');
  final StreamController<List<SharedFile>> _fileUpdates =
      StreamController<List<SharedFile>>.broadcast();
  final StreamController<TransferProgress> _progressUpdates =
      StreamController<TransferProgress>.broadcast();

  Stream<List<SharedFile>> watchIncomingSharedFiles() => _fileUpdates.stream;

  Stream<TransferProgress> watchTransferProgress() => _progressUpdates.stream;

  Future<MobileAppSettings> getMobileSettings() async {
    try {
      final result = await _channel.invokeMethod<Object?>('getMobileSettings');
      if (result is Map) {
        return MobileAppSettings.fromJson(_mapFromNative(result));
      }
      return const MobileAppSettings.defaults();
    } on MissingPluginException {
      return const MobileAppSettings.defaults();
    }
  }

  Future<MobileAppSettings> saveMobileSettings(
    MobileAppSettings settings,
  ) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'saveMobileSettings',
        settings.toJson(),
      );
      if (result is Map) {
        return MobileAppSettings.fromJson(_mapFromNative(result));
      }
      return settings;
    } on MissingPluginException {
      return settings;
    }
  }

  Future<List<SharedFile>> getInitialSharedFiles() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'getInitialSharedFiles',
      );
      return _decodeFiles(result);
    } on MissingPluginException {
      return const <SharedFile>[];
    }
  }

  Future<List<PairedDevice>> getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod<Object?>('getPairedDevices');
      return _decodePairedDevices(result);
    } on MissingPluginException {
      return const <PairedDevice>[];
    }
  }

  Future<List<PairedDevice>> discoverPairedDevices() async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'discoverPairedDevices',
      );
      return _decodePairedDevices(result);
    } on MissingPluginException {
      return const <PairedDevice>[];
    }
  }

  Future<List<TransferRecord>> getTransferHistory() async {
    try {
      final result = await _channel.invokeMethod<Object?>('getTransferHistory');
      return _decodeTransferRecords(result);
    } on MissingPluginException {
      return const <TransferRecord>[];
    }
  }

  Future<void> clearTransferHistory() async {
    try {
      await _channel.invokeMethod<void>('clearTransferHistory');
    } on MissingPluginException {
      // Non-Android platforms do not provide this channel.
    }
  }

  Future<PairedDevice> pairWithComputer({
    required String pairingPayload,
    required String deviceName,
    String? hostOverride,
  }) async {
    try {
      final result = await _channel.invokeMethod<Object?>('pairWithComputer', {
        'pairingPayload': pairingPayload,
        'deviceName': deviceName,
        'hostOverride': hostOverride,
      });
      return _decodePairedDevice(result);
    } on MissingPluginException {
      throw UnsupportedError('Pairing is only available on Android.');
    }
  }

  Future<void> forgetPairedDevice(String id) async {
    try {
      await _channel.invokeMethod<void>('forgetPairedDevice', {'id': id});
    } on MissingPluginException {
      // Non-Android platforms do not provide this channel.
    }
  }

  Future<void> sendSharedFiles({
    required String host,
    required int port,
    required String token,
    required List<SharedFile> files,
    bool wifiOnly = false,
  }) async {
    if (files.isEmpty) {
      return;
    }

    await _channel.invokeMethod<void>('uploadSharedFiles', {
      'host': host,
      'port': port,
      'token': token,
      'files': files.map((file) => file.toJson()).toList(growable: false),
      'wifiOnly': wifiOnly,
    });
  }

  Future<void> clearSharedFiles() async {
    try {
      await _channel.invokeMethod<void>('clearSharedFiles');
    } on MissingPluginException {
      // Non-Android platforms do not provide this channel.
    }
    _fileUpdates.add(const <SharedFile>[]);
  }

  Future<void> dispose() async {
    await _fileUpdates.close();
    await _progressUpdates.close();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'sharedFilesUpdated':
        _fileUpdates.add(_decodeFiles(call.arguments));
        break;
      case 'transferProgressUpdated':
        _progressUpdates.add(_decodeProgress(call.arguments));
        break;
    }
  }

  List<SharedFile> _decodeFiles(Object? value) {
    if (value is! List) {
      return const <SharedFile>[];
    }

    return value.whereType<Map>().map((raw) {
      final json = _mapFromNative(raw);
      final size = json['size'];
      if (size is num) {
        json['size'] = size.toInt();
      }
      return SharedFile.fromJson(json);
    }).toList(growable: false);
  }

  List<PairedDevice> _decodePairedDevices(Object? value) {
    if (value is! List) {
      return const <PairedDevice>[];
    }

    return value
        .whereType<Map>()
        .map((raw) => PairedDevice.fromJson(_mapFromNative(raw)))
        .toList(growable: false);
  }

  List<TransferRecord> _decodeTransferRecords(Object? value) {
    if (value is! List) {
      return const <TransferRecord>[];
    }

    return value
        .whereType<Map>()
        .map((raw) => TransferRecord.fromJson(_transferRecordJson(raw)))
        .toList(growable: false);
  }

  PairedDevice _decodePairedDevice(Object? value) {
    if (value is! Map) {
      throw StateError('The pairing response was not a paired device.');
    }
    return PairedDevice.fromJson(_mapFromNative(value));
  }

  TransferProgress _decodeProgress(Object? value) {
    final json = value is Map ? _mapFromNative(value) : <String, dynamic>{};

    int intValue(String key, [int fallback = 0]) {
      final value = json[key];
      if (value is num) {
        return value.toInt();
      }
      return fallback;
    }

    return TransferProgress(
      transferId: (json['transferId'] as String?) ?? 'pending',
      fileName: (json['fileName'] as String?) ?? 'Shared file',
      bytesTransferred: intValue('bytesTransferred'),
      totalBytes: intValue('totalBytes'),
      status: transferStatusFromJson(json['status']),
      currentFileNumber: intValue('currentFileNumber', 1),
      totalFileCount: intValue('totalFileCount', 1),
    );
  }

  Map<String, dynamic> _transferRecordJson(Map raw) {
    final json = _mapFromNative(raw);
    for (final key in const <String>[
      'fileSize',
      'bytesTransferred',
    ]) {
      final value = json[key];
      if (value is num) {
        json[key] = value.toInt();
      }
    }
    return json;
  }

  Map<String, dynamic> _mapFromNative(Map raw) {
    final json = <String, dynamic>{};
    for (final entry in raw.entries) {
      json[entry.key.toString()] = entry.value;
    }
    return json;
  }
}
