import 'app_constants.dart';

class AppSettings {
  const AppSettings({
    required this.receiveFolder,
    this.listenPort = AppConstants.defaultPort,
    this.startWithWindows = false,
    this.minimizeToTray = true,
    this.showNotifications = true,
    this.maximumFileSizeBytes = AppConstants.maxSingleFileSizeBytes,
    this.allowMultipleFiles = true,
    this.autoAcceptTrustedDevices = true,
    this.maximumConcurrentTransfers = AppConstants.maxConcurrentTransfers,
  });

  final String receiveFolder;
  final int listenPort;
  final bool startWithWindows;
  final bool minimizeToTray;
  final bool showNotifications;
  final int maximumFileSizeBytes;
  final bool allowMultipleFiles;
  final bool autoAcceptTrustedDevices;
  final int maximumConcurrentTransfers;

  AppSettings copyWith({
    String? receiveFolder,
    int? listenPort,
    bool? startWithWindows,
    bool? minimizeToTray,
    bool? showNotifications,
    int? maximumFileSizeBytes,
    bool? allowMultipleFiles,
    bool? autoAcceptTrustedDevices,
    int? maximumConcurrentTransfers,
  }) {
    return AppSettings(
      receiveFolder: receiveFolder ?? this.receiveFolder,
      listenPort: listenPort ?? this.listenPort,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      showNotifications: showNotifications ?? this.showNotifications,
      maximumFileSizeBytes:
          maximumFileSizeBytes ?? this.maximumFileSizeBytes,
      allowMultipleFiles: allowMultipleFiles ?? this.allowMultipleFiles,
      autoAcceptTrustedDevices:
          autoAcceptTrustedDevices ?? this.autoAcceptTrustedDevices,
      maximumConcurrentTransfers:
          maximumConcurrentTransfers ?? this.maximumConcurrentTransfers,
    );
  }
}

