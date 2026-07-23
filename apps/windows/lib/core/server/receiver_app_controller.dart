import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_security/shared_security.dart';

import '../pairing/pairing_coordinator.dart';
import '../settings/receiver_settings.dart';
import '../settings/settings_repository.dart';
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
  });

  ReceiverSettingsSnapshot settingsSnapshot;
  final SettingsRepository settingsRepository;
  final String bootstrapToken;
  final ReceiveFileStorage storage;
  final TrustedDeviceStore trustedDevices;

  late final PairingCoordinator pairingCoordinator;
  late final ReceiverServer server;

  StreamSubscription<TransferRecord>? _recordSubscription;
  Object? _startupError;
  String _localAddress = '127.0.0.1';
  List<String> _localAddresses = const <String>['127.0.0.1'];
  List<TransferRecord> _records = <TransferRecord>[];

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
    );

    return controller;
  }

  Future<void> initialize() async {
    try {
      final addresses = await localIpv4Addresses();
      _localAddresses = addresses.isEmpty
          ? const <String>['127.0.0.1']
          : addresses;
      _localAddress = _localAddresses.first;
      _recordSubscription = server.recordEvents.listen((_) {
        _records = server.records;
        notifyListeners();
      });
      await server.start();
      _records = server.records;
      _startupError = null;
    } on Object catch (error) {
      _startupError = error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> startServer() async {
    try {
      await server.start();
      _startupError = null;
    } on Object catch (error) {
      _startupError = error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    await server.stop();
    notifyListeners();
  }

  void _notifyPairingChanged() {
    notifyListeners();
  }

  void createPairingSession() {
    pairingCoordinator.createSession();
    notifyListeners();
  }

  Future<void> approvePairingRequest(String requestId) async {
    await pairingCoordinator.approve(requestId);
    notifyListeners();
  }

  void rejectPairingRequest(String requestId) {
    pairingCoordinator.reject(requestId);
    notifyListeners();
  }

  Future<void> revokeDevice(String deviceId) async {
    await trustedDevices.revokeDevice(deviceId);
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
      settingsSnapshot = nextSnapshot;
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
