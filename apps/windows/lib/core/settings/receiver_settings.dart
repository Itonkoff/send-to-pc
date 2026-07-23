import 'package:shared_models/shared_models.dart';

class ReceiverSettingsSnapshot {
  const ReceiverSettingsSnapshot({
    required this.deviceId,
    required this.deviceName,
    required this.appSettings,
  });

  final String deviceId;
  final String deviceName;
  final AppSettings appSettings;

  factory ReceiverSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'] as Map<String, dynamic>;
    return ReceiverSettingsSnapshot(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      appSettings: AppSettings(
        receiveFolder: settings['receiveFolder'] as String,
        listenPort: (settings['listenPort'] as int?) ?? AppConstants.defaultPort,
        startWithWindows: (settings['startWithWindows'] as bool?) ?? false,
        minimizeToTray: (settings['minimizeToTray'] as bool?) ?? true,
        showNotifications: (settings['showNotifications'] as bool?) ?? true,
        maximumFileSizeBytes: (settings['maximumFileSizeBytes'] as int?) ??
            AppConstants.maxSingleFileSizeBytes,
        allowMultipleFiles: (settings['allowMultipleFiles'] as bool?) ?? true,
        autoAcceptTrustedDevices:
            (settings['autoAcceptTrustedDevices'] as bool?) ?? true,
        maximumConcurrentTransfers:
            (settings['maximumConcurrentTransfers'] as int?) ??
                AppConstants.maxConcurrentTransfers,
      ),
    );
  }

  Map<String, Object?> toJson() {
    final settings = appSettings;
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'settings': {
        'receiveFolder': settings.receiveFolder,
        'listenPort': settings.listenPort,
        'startWithWindows': settings.startWithWindows,
        'minimizeToTray': settings.minimizeToTray,
        'showNotifications': settings.showNotifications,
        'maximumFileSizeBytes': settings.maximumFileSizeBytes,
        'allowMultipleFiles': settings.allowMultipleFiles,
        'autoAcceptTrustedDevices': settings.autoAcceptTrustedDevices,
        'maximumConcurrentTransfers': settings.maximumConcurrentTransfers,
      },
    };
  }
}