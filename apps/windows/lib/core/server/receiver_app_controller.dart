import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';
import 'package:shared_security/shared_security.dart';

import '../logging/app_logger.dart';
import '../notifications/windows_notification_service.dart';
import '../pairing/pairing_coordinator.dart';
import '../settings/receiver_settings.dart';
import '../settings/settings_repository.dart';
import '../startup/windows_startup_service.dart';
import '../storage/receive_file_storage.dart';
import '../utils/network_interfaces.dart';
import 'paired_device_repository.dart';
import 'receiver_server.dart';
import 'transfer_record_repository.dart';
import 'trusted_device_store.dart';

class ReceiverAppController extends ChangeNotifier {
  ReceiverAppController._({
    required this.settingsSnapshot,
    required this.settingsRepository,
    required this.bootstrapToken,
    required this.storage,
    required this.trustedDevices,
    required this.notificationService,
    required this.startupService,
    required this.logger,
  });

  ReceiverSettingsSnapshot settingsSnapshot;
  final SettingsRepository settingsRepository;
  final String bootstrapToken;
  final ReceiveFileStorage storage;
  final TrustedDeviceStore trustedDevices;
  final WindowsNotificationService notificationService;
  final WindowsStartupService startupService;
  final AppLogger logger;

  late final PairingCoordinator pairingCoordinator;
  late final ReceiverServer server;

  StreamSubscription<TransferRecord>? _recordSubscription;
  Object? _startupError;
  String _localAddress = '127.0.0.1';
  List<String> _localAddresses = const <String>['127.0.0.1'];
  List<TransferRecord> _records = <TransferRecord>[];
  final Set<String> _notifiedTransferEvents = <String>{};
  final Set<String> _notifiedPairingRequestIds = <String>{};
  final Set<String> _loggedTransferStatuses = <String>{};
  final Set<String> _loggedPairingRequestIds = <String>{};
  final Map<String, int> _lastLoggedProgressBytes = <String, int>{};

  bool get isRunning => server.isRunning;
  Object? get startupError => _startupError;
  String get localAddress => _localAddress;
  List<String> get localAddresses => List.unmodifiable(_localAddresses);
  int get listeningPort => server.boundPort ?? settingsSnapshot.appSettings.listenPort;
  List<TransferRecord> get records => List.unmodifiable(_records.reversed);
  int get activeTransferCount => _records.where(_isActiveTransfer).length;
  List<PairedDevice> get pairedDevices => trustedDevices.devices;
  PairingSessionSnapshot? get activePairingSession => pairingCoordinator.activeSession;
  List<PairingRequestSnapshot> get pairingRequests => pairingCoordinator.requests;

  static Future<ReceiverAppController> create() async {
    final settingsRepository = SettingsRepository();
    final settings = await settingsRepository.load();
    final deviceRepository = PairedDeviceRepository();
    final transferHistory = TransferRecordRepository();
    final persistedDevices = await deviceRepository.load();
    final token = secureToken();
    final now = DateTime.now();
    final bootstrapDevice = PairedDevice(
      id: 'bootstrap-test-client',
      deviceId: 'bootstrap-test-client',
      deviceName: 'Local test client',
      platform: 'development',
      authenticationToken: token,
      createdAt: now,
      updatedAt: now,
    );
    final trustedDevices = TrustedDeviceStore(
      persistedDevices,
      repository: deviceRepository,
      ephemeralDevices: <PairedDevice>[bootstrapDevice],
    );
    final storage = ReceiveFileStorage(
      receiveFolder: settings.appSettings.receiveFolder,
    );
    final controller = ReceiverAppController._(
      settingsSnapshot: settings,
      settingsRepository: settingsRepository,
      bootstrapToken: token,
      storage: storage,
      trustedDevices: trustedDevices,
      notificationService: WindowsNotificationService(),
      startupService: const WindowsStartupService(),
      logger: AppLogger(),
    );

    final deviceInfo = DeviceInfo(
      deviceId: settings.deviceId,
      deviceName: settings.deviceName,
      platform: 'windows',
      protocolVersion: AppConstants.protocolVersion,
      serverVersion: AppConstants.serverVersion,
      requiresAuthentication: true,
    );
    controller.pairingCoordinator = PairingCoordinator(
      receiverDeviceId: settings.deviceId,
      receiverDeviceName: settings.deviceName,
      hostProvider: () => controller.localAddress,
      hostAlternativesProvider: () => controller.localAddresses,
      portProvider: () => controller.listeningPort,
      trustedDevices: trustedDevices,
      onChanged: controller._notifyPairingChanged,
    );
    controller.server = ReceiverServer(
      deviceInfo: deviceInfo,
      settings: settings.appSettings,
      storage: storage,
      trustedDevices: trustedDevices,
      pairingCoordinator: controller.pairingCoordinator,
      transferHistory: transferHistory,
      onServerWarning: controller._handleServerWarning,
    );

    unawaited(controller.logger.information(
      'application_startup',
      data: <String, Object?>{
        'deviceId': settings.deviceId,
        'deviceName': settings.deviceName,
      },
    ));
    return controller;
  }

  Future<void> initialize() async {
    try {
      final addresses = await localIpv4Addresses();
      _localAddresses = addresses.isEmpty
          ? const <String>['127.0.0.1']
          : addresses;
      _localAddress = _localAddresses.first;
      _recordSubscription = server.recordEvents.listen(_handleRecordChanged);
      unawaited(logger.information('receiver_start_requested'));
      await server.start();
      unawaited(logger.information(
        'receiver_started',
        data: <String, Object?>{'port': listeningPort},
      ));
      _records = server.records;
      _startupError = null;
    } on Object catch (error) {
      _startupError = error;
      unawaited(logger.error(
        'receiver_start_failed',
        data: <String, Object?>{'error': error.toString()},
      ));
    } finally {
      notifyListeners();
    }
  }

  Future<void> startServer() async {
    try {
      unawaited(logger.information('receiver_start_requested'));
      await server.start();
      unawaited(logger.information(
        'receiver_started',
        data: <String, Object?>{'port': listeningPort},
      ));
      _startupError = null;
    } on Object catch (error) {
      _startupError = error;
      unawaited(logger.error(
        'receiver_start_failed',
        data: <String, Object?>{'error': error.toString()},
      ));
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    await server.stop();
    unawaited(logger.information('receiver_stopped'));
    notifyListeners();
  }

  void _notifyPairingChanged() {
    _maybeLogPairingRequests();
    _maybeNotifyPairingRequests();
    notifyListeners();
  }

  void _handleRecordChanged(TransferRecord record) {
    _records = server.records;
    _maybeLogTransfer(record);
    _maybeNotifyTransfer(record);
    notifyListeners();
  }

  void _maybeNotifyTransfer(TransferRecord record) {
    if (!settingsSnapshot.appSettings.showNotifications) {
      return;
    }
    final eventKey = '${record.id}:${record.status.jsonName}';
    if (!_notifiedTransferEvents.add(eventKey)) {
      return;
    }

    switch (record.status) {
      case TransferStatus.pending:
        unawaited(notificationService.showIncomingTransfer(record));
        break;
      case TransferStatus.completed:
        unawaited(notificationService.showTransferCompleted(record));
        break;
      case TransferStatus.failed:
        unawaited(notificationService.showTransferFailed(record));
        break;
      case TransferStatus.connecting:
      case TransferStatus.uploading:
      case TransferStatus.uploaded:
      case TransferStatus.verifying:
      case TransferStatus.cancelled:
        break;
    }
  }

  void _maybeLogTransfer(TransferRecord record) {
    final statusKey = '${record.id}:${record.status.jsonName}';
    final isProgressCheckpoint = record.status == TransferStatus.uploading &&
        record.bytesTransferred -
                (_lastLoggedProgressBytes[record.id] ?? 0) >=
            _progressLogIntervalBytes;
    if (!isProgressCheckpoint && !_loggedTransferStatuses.add(statusKey)) {
      return;
    }
    if (record.status == TransferStatus.uploading) {
      _lastLoggedProgressBytes[record.id] = record.bytesTransferred;
    }

    unawaited(logger.information(
      'transfer_${record.status.jsonName}',
      data: <String, Object?>{
        'transferId': record.id,
        'senderDeviceId': record.senderDeviceId,
        'fileName': record.safeFileName,
        'mimeType': record.mimeType,
        'fileSize': record.fileSize,
        'bytesTransferred': record.bytesTransferred,
        'failureCode': record.failureCode,
      },
    ));
  }

  void _maybeLogPairingRequests() {
    for (final request in pairingCoordinator.requests) {
      if (!_loggedPairingRequestIds.add(request.id)) {
        continue;
      }
      unawaited(logger.information(
        'pairing_request',
        data: <String, Object?>{
          'requestId': request.id,
          'deviceName': request.deviceName,
          'deviceId': request.deviceId,
          'platform': request.platform,
          'remoteAddress': request.remoteAddress,
          'status': request.status.name,
        },
      ));
    }
  }

  void _handleServerWarning(String code, String message, String? fileName) {
    unawaited(logger.warning(
      'server_warning',
      data: <String, Object?>{
        'code': code,
        'message': message,
        'fileName': fileName,
      },
    ));
    if (!settingsSnapshot.appSettings.showNotifications) {
      return;
    }
    if (code == ErrorCodes.insufficientDiskSpace) {
      unawaited(
        notificationService.showDiskSpaceWarning(fileName ?? 'the file'),
      );
    }
  }

  void _maybeNotifyPairingRequests() {
    if (!settingsSnapshot.appSettings.showNotifications) {
      return;
    }
    for (final request in pairingCoordinator.requests) {
      if (request.status != PairingRequestStatus.pending ||
          !_notifiedPairingRequestIds.add(request.id)) {
        continue;
      }
      unawaited(
        notificationService.showPairingRequest(
          deviceName: request.deviceName,
          platform: request.platform,
        ),
      );
    }
  }

  void createPairingSession() {
    pairingCoordinator.createSession();
    unawaited(logger.information('pairing_session_created'));
    notifyListeners();
  }

  Future<void> approvePairingRequest(String requestId) async {
    await pairingCoordinator.approve(requestId);
    unawaited(logger.information(
      'pairing_approved',
      data: <String, Object?>{'requestId': requestId},
    ));
    notifyListeners();
  }

  void rejectPairingRequest(String requestId) {
    pairingCoordinator.reject(requestId);
    unawaited(logger.information(
      'pairing_rejected',
      data: <String, Object?>{'requestId': requestId},
    ));
    notifyListeners();
  }

  Future<void> revokeDevice(String deviceId) async {
    await trustedDevices.revokeDevice(deviceId);
    unawaited(logger.warning(
      'device_revoked',
      data: <String, Object?>{'deviceId': deviceId},
    ));
    notifyListeners();
  }

  Future<void> clearTransferHistory() async {
    await server.clearTransferHistory();
    _records = server.records;
    notifyListeners();
  }

  Future<void> cancelTransfer(String transferId) async {
    await server.cancelTransfer(transferId);
    _records = server.records;
    notifyListeners();
  }

  bool _isActiveTransfer(TransferRecord record) {
    return switch (record.status) {
      TransferStatus.pending ||
      TransferStatus.connecting ||
      TransferStatus.uploading ||
      TransferStatus.uploaded ||
      TransferStatus.verifying =>
        true,
      TransferStatus.completed ||
      TransferStatus.failed ||
      TransferStatus.cancelled =>
        false,
    };
  }

  Future<void> updateAppSettings(AppSettings appSettings) async {
    final previousSnapshot = settingsSnapshot;
    final previousSettings = previousSnapshot.appSettings;
    final nextSnapshot = ReceiverSettingsSnapshot(
      deviceId: settingsSnapshot.deviceId,
      deviceName: settingsSnapshot.deviceName,
      appSettings: appSettings,
    );
    final wasRunning = server.isRunning;
    if (wasRunning) {
      await server.stop();
    }

    try {
      await settingsRepository.save(nextSnapshot);
      if (appSettings.startWithWindows != previousSettings.startWithWindows) {
        await startupService.setEnabled(appSettings.startWithWindows);
      }
      settingsSnapshot = nextSnapshot;
      unawaited(logger.information(
        'configuration_changed',
        data: <String, Object?>{
          'listenPort': appSettings.listenPort,
          'receiveFolderChanged':
              appSettings.receiveFolder != previousSettings.receiveFolder,
          'startWithWindows': appSettings.startWithWindows,
          'minimizeToTray': appSettings.minimizeToTray,
          'showNotifications': appSettings.showNotifications,
          'maximumFileSizeBytes': appSettings.maximumFileSizeBytes,
          'maximumConcurrentTransfers': appSettings.maximumConcurrentTransfers,
        },
      ));
      server.updateSettings(appSettings);
      if (wasRunning) {
        await server.start();
      }
      _records = server.records;
      _startupError = null;
    } on Object catch (error) {
      settingsSnapshot = previousSnapshot;
      server.updateSettings(previousSettings);
      await settingsRepository.save(previousSnapshot);
      if (appSettings.startWithWindows != previousSettings.startWithWindows) {
        try {
          await startupService.setEnabled(previousSettings.startWithWindows);
        } on Object {
          // Keep the original failure visible to the user.
        }
      }
      if (wasRunning) {
        try {
          await server.start();
        } on Object catch (restartError) {
          _startupError = restartError;
        }
      }
      _startupError ??= error;
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_recordSubscription?.cancel());
    unawaited(server.stop());
    super.dispose();
  }
}

const _progressLogIntervalBytes = 1024 * 1024;
