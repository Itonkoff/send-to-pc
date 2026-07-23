import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:send_to_pc_windows/core/server/transfer_record_repository.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('transfer history repository saves and loads recent records', () async {
    final directory = await Directory.systemTemp.createTemp(
      'send_to_pc_transfer_history_',
    );
    try {
      final repository = TransferRecordRepository(
        appDataPath: directory.path,
        maxRecords: 2,
      );
      final first = _record(
        id: 'one',
        createdAt: DateTime.utc(2026, 7, 23, 10),
      );
      final second = _record(
        id: 'two',
        createdAt: DateTime.utc(2026, 7, 23, 11),
      );
      final third = _record(
        id: 'three',
        createdAt: DateTime.utc(2026, 7, 23, 12),
        status: TransferStatus.failed,
        failureCode: 'UPLOAD_INTERRUPTED',
      );

      await repository.save(<TransferRecord>[third, first, second]);

      final loaded = await repository.load();
      expect(loaded.map((record) => record.id), ['two', 'three']);
      expect(loaded.last.status, TransferStatus.failed);
      expect(loaded.last.failureCode, 'UPLOAD_INTERRUPTED');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('transfer history repository clears persisted records', () async {
    final directory = await Directory.systemTemp.createTemp(
      'send_to_pc_transfer_history_',
    );
    try {
      final repository = TransferRecordRepository(appDataPath: directory.path);
      await repository.save(<TransferRecord>[
        _record(
          id: 'one',
          createdAt: DateTime.utc(2026, 7, 23, 10),
        ),
      ]);

      await repository.clear();

      expect(await repository.load(), isEmpty);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

TransferRecord _record({
  required String id,
  required DateTime createdAt,
  TransferStatus status = TransferStatus.completed,
  String? failureCode,
}) {
  return TransferRecord(
    id: id,
    senderDeviceId: 'phone-test',
    receiverDeviceId: 'pc-test',
    fileName: '$id.txt',
    safeFileName: '$id.txt',
    mimeType: 'text/plain',
    fileSize: 12,
    checksumAlgorithm: AppConstants.checksumAlgorithm,
    checksum: 'abc123',
    status: status,
    bytesTransferred: status == TransferStatus.completed ? 12 : 6,
    finalPath: status == TransferStatus.completed
        ? 'C:\\SendToPC\\$id.txt'
        : null,
    failureCode: failureCode,
    createdAt: createdAt,
    completedAt: status == TransferStatus.completed
        ? createdAt.add(const Duration(seconds: 1))
        : null,
    updatedAt: createdAt.add(const Duration(seconds: 1)),
  );
}