import 'package:shared_models/shared_models.dart';
import 'package:shared_security/shared_security.dart';

import 'paired_device_repository.dart';

class TrustedDeviceStore {
  TrustedDeviceStore(
    Iterable<PairedDevice> devices, {
    required PairedDeviceRepository repository,
    Iterable<PairedDevice> ephemeralDevices = const <PairedDevice>[],
  })  : _repository = repository,
        _devices = List<PairedDevice>.of(devices),
        _ephemeralDevices = List<PairedDevice>.of(ephemeralDevices);

  final PairedDeviceRepository _repository;
  final List<PairedDevice> _devices;
  final List<PairedDevice> _ephemeralDevices;

  List<PairedDevice> get devices => List.unmodifiable(_devices);

  PairedDevice? authenticate(String? authorizationHeader) {
    if (authorizationHeader == null ||
        !authorizationHeader.toLowerCase().startsWith('bearer ')) {
      return null;
    }

    final token = authorizationHeader.substring(7).trim();
    for (final device in <PairedDevice>[..._devices, ..._ephemeralDevices]) {
      if (device.isRevoked || !device.isTrusted) {
        continue;
      }
      if (constantTimeEquals(device.authenticationToken, token)) {
        return device.copyWith(lastSeenAt: DateTime.now());
      }
    }
    return null;
  }

  Future<PairedDevice> trustDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
    String? certificateFingerprint,
    String? lastKnownAddress,
  }) async {
    final now = DateTime.now();
    final device = PairedDevice(
      id: randomUuidV4(),
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
      authenticationToken: secureToken(),
      certificateFingerprint: certificateFingerprint,
      lastKnownAddress: lastKnownAddress,
      lastSeenAt: now,
      createdAt: now,
      updatedAt: now,
    );

    final existingIndex = _devices.indexWhere((entry) => entry.deviceId == deviceId);
    if (existingIndex >= 0) {
      _devices[existingIndex] = device;
    } else {
      _devices.add(device);
    }
    await _repository.save(_devices);
    return device;
  }

  Future<void> revokeDevice(String deviceId) async {
    final index = _devices.indexWhere((device) => device.deviceId == deviceId);
    if (index < 0) {
      return;
    }
    _devices[index] = _devices[index].copyWith(
      isRevoked: true,
      isTrusted: false,
      updatedAt: DateTime.now(),
    );
    await _repository.save(_devices);
  }
}