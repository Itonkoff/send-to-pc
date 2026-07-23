import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:send_to_pc_windows/core/pairing/pairing_coordinator.dart';
import 'package:send_to_pc_windows/core/server/paired_device_repository.dart';
import 'package:send_to_pc_windows/core/server/receiver_server.dart';
import 'package:send_to_pc_windows/core/server/transfer_record_repository.dart';
import 'package:send_to_pc_windows/core/server/trusted_device_store.dart';
import 'package:send_to_pc_windows/core/storage/receive_file_storage.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';
import 'package:shared_storage/shared_storage.dart';

void main() {
  test('rejects oversized content length before creating part file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'send_to_pc_receiver_',
    );
    final receiveDirectory = Directory(joinPath(directory.path, 'receive'));
    ReceiverServer? server;
    final client = HttpClient();

    try {
      final deviceRepository = PairedDeviceRepository(
        appDataPath: directory.path,
      );
      final trustedDevices = TrustedDeviceStore(
        await deviceRepository.load(),
        repository: deviceRepository,
      );
      final device = await trustedDevices.trustDevice(
        deviceId: 'phone-test',
        deviceName: 'Test Phone',
        platform: 'android',
      );
      final settings = AppSettings(
        receiveFolder: receiveDirectory.path,
        listenPort: 0,
        maximumFileSizeBytes: 6,
      );
      final pairingCoordinator = PairingCoordinator(
        receiverDeviceId: 'pc-test',
        receiverDeviceName: 'Test PC',
        hostProvider: () => '127.0.0.1',
        portProvider: () => server?.boundPort ?? 0,
        trustedDevices: trustedDevices,
      );
      server = ReceiverServer(
        deviceInfo: const DeviceInfo(
          deviceId: 'pc-test',
          deviceName: 'Test PC',
          platform: 'windows',
          protocolVersion: AppConstants.protocolVersion,
          serverVersion: AppConstants.serverVersion,
          requiresAuthentication: true,
        ),
        settings: settings,
        storage: ReceiveFileStorage(receiveFolder: receiveDirectory.path),
        trustedDevices: trustedDevices,
        pairingCoordinator: pairingCoordinator,
        transferHistory: TransferRecordRepository(appDataPath: directory.path),
      );
      await server.start();

      final transfer = await _createTransfer(
        client,
        port: server.boundPort!,
        token: device.authenticationToken,
        declaredFileSize: 4,
      );

      final uploadResponse = await _uploadBytes(
        client,
        port: server.boundPort!,
        transferId: transfer.transferId,
        token: device.authenticationToken,
        bytes: List<int>.filled(8, 1),
      );

      expect(uploadResponse.statusCode, HttpStatus.requestEntityTooLarge);
      expect(uploadResponse.body['code'], ErrorCodes.fileTooLarge);
      expect(await receiveDirectory.list().toList(), isEmpty);
      expect(server.records.single.status, TransferStatus.failed);
      expect(server.records.single.failureCode, ErrorCodes.fileTooLarge);
      expect(server.records.single.temporaryPath, isNull);
    } finally {
      client.close(force: true);
      await server?.stop();
      await directory.delete(recursive: true);
    }
  });
}

Future<TransferCreateResponse> _createTransfer(
  HttpClient client, {
  required int port,
  required String token,
  required int declaredFileSize,
}) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port${ApiRoutes.transfers}'),
  );
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.add(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'fileName': 'too-large.bin',
        'mimeType': 'application/octet-stream',
        'fileSize': declaredFileSize,
        'checksumAlgorithm': AppConstants.checksumAlgorithm,
        'checksum': '00',
      }),
    ),
  );

  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  expect(response.statusCode, HttpStatus.created);
  return TransferCreateResponse.fromJson(
    Map<String, dynamic>.from(jsonDecode(body) as Map),
  );
}

Future<_JsonResponse> _uploadBytes(
  HttpClient client, {
  required int port,
  required String transferId,
  required String token,
  required List<int> bytes,
}) async {
  final request = await client.putUrl(
    Uri.parse(
      'http://127.0.0.1:$port${ApiRoutes.transferContent(transferId)}',
    ),
  );
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
  request.contentLength = bytes.length;
  request.add(bytes);

  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _JsonResponse(
    statusCode: response.statusCode,
    body: Map<String, dynamic>.from(jsonDecode(body) as Map),
  );
}

class _JsonResponse {
  const _JsonResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final Map<String, dynamic> body;
}