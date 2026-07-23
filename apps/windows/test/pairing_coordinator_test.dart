import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:send_to_pc_windows/core/pairing/pairing_coordinator.dart';
import 'package:send_to_pc_windows/core/server/paired_device_repository.dart';
import 'package:send_to_pc_windows/core/server/trusted_device_store.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';

void main() {
  test('pairing request waits for approval and persists trusted device', () async {
    final directory = await Directory.systemTemp.createTemp('send_to_pc_pairing_');
    try {
      final repository = PairedDeviceRepository(appDataPath: directory.path);
      final store = TrustedDeviceStore(
        await repository.load(),
        repository: repository,
      );
      final coordinator = PairingCoordinator(
        receiverDeviceId: 'pc-test',
        receiverDeviceName: 'Test PC',
        hostProvider: () => '127.0.0.1',
        portProvider: () => AppConstants.defaultPort,
        trustedDevices: store,
      );

      final session = coordinator.createSession();
      final responseFuture = coordinator.handlePairingRequest({
        'protocolVersion': AppConstants.protocolVersion,
        'pairingToken': session.payload.pairingToken,
        'deviceId': 'phone-test',
        'deviceName': 'Test Phone',
        'platform': 'android',
      });

      await Future<void>.delayed(Duration.zero);
      expect(coordinator.requests.single.status, PairingRequestStatus.pending);

      await coordinator.approve(coordinator.requests.single.id);
      final response = await responseFuture;

      expect(response['status'], 'approved');
      expect(response['deviceToken'], isA<String>());
      expect(store.devices.single.deviceId, 'phone-test');
      expect((await repository.load()).single.deviceId, 'phone-test');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('pairing payload includes host alternatives', () async {
    final directory = await Directory.systemTemp.createTemp('send_to_pc_pairing_');
    try {
      final repository = PairedDeviceRepository(appDataPath: directory.path);
      final store = TrustedDeviceStore(
        await repository.load(),
        repository: repository,
      );
      final coordinator = PairingCoordinator(
        receiverDeviceId: 'pc-test',
        receiverDeviceName: 'Test PC',
        hostProvider: () => '192.168.1.184',
        hostAlternativesProvider: () => const [
          '192.168.1.184',
          '192.168.137.1',
        ],
        portProvider: () => AppConstants.defaultPort,
        trustedDevices: store,
      );

      final session = coordinator.createSession();

      expect(session.payload.host, '192.168.1.184');
      expect(session.payload.hostAlternatives, [
        '192.168.1.184',
        '192.168.137.1',
      ]);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('revoked trusted device can no longer authenticate', () async {
    final directory = await Directory.systemTemp.createTemp('send_to_pc_pairing_');
    try {
      final repository = PairedDeviceRepository(appDataPath: directory.path);
      final store = TrustedDeviceStore(
        await repository.load(),
        repository: repository,
      );

      final device = await store.trustDevice(
        deviceId: 'phone-test',
        deviceName: 'Test Phone',
        platform: 'android',
      );
      final header = 'Bearer ${device.authenticationToken}';

      expect(store.authenticate(header)?.deviceId, 'phone-test');

      await store.revokeDevice('phone-test');

      expect(store.authenticate(header), isNull);
      final persisted = await repository.load();
      expect(persisted.single.deviceId, 'phone-test');
      expect(persisted.single.isTrusted, isFalse);
      expect(persisted.single.isRevoked, isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('pairing rejects invalid token', () async {
    final directory = await Directory.systemTemp.createTemp('send_to_pc_pairing_');
    try {
      final repository = PairedDeviceRepository(appDataPath: directory.path);
      final store = TrustedDeviceStore(
        await repository.load(),
        repository: repository,
      );
      final coordinator = PairingCoordinator(
        receiverDeviceId: 'pc-test',
        receiverDeviceName: 'Test PC',
        hostProvider: () => '127.0.0.1',
        portProvider: () => AppConstants.defaultPort,
        trustedDevices: store,
      );

      coordinator.createSession();

      await expectLater(
        coordinator.handlePairingRequest({
          'protocolVersion': AppConstants.protocolVersion,
          'pairingToken': 'wrong-token',
          'deviceId': 'phone-test',
          'deviceName': 'Test Phone',
          'platform': 'android',
        }),
        throwsA(
          isA<ProtocolError>().having(
            (error) => error.code,
            'code',
            ErrorCodes.pairingTokenInvalid,
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
