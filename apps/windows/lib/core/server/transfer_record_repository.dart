import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_models/shared_models.dart';
import 'package:shared_storage/shared_storage.dart';

import '../settings/app_data_paths.dart';

class TransferRecordRepository {
  TransferRecordRepository({String? appDataPath, this.maxRecords = 100})
      : _file = File(
          joinPath(
            AppDataPaths.root(overridePath: appDataPath),
            'transfer_history.json',
          ),
        );

  final File _file;
  final int maxRecords;
  Future<void> _saveQueue = Future<void>.value();

  Future<List<TransferRecord>> load() async {
    if (!await _file.exists()) {
      return <TransferRecord>[];
    }

    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! List) {
      return <TransferRecord>[];
    }

    final records = <TransferRecord>[];
    for (final entry in decoded.whereType<Map>()) {
      try {
        records.add(
          TransferRecord.fromJson(Map<String, dynamic>.from(entry)),
        );
      } on Object {
        // Ignore malformed records so one bad entry does not hide history.
      }
    }
    return records;
  }

  Future<void> save(Iterable<TransferRecord> records) {
    final snapshot = _retainedRecords(records);
    return _queueWrite(snapshot);
  }

  Future<void> clear() {
    return _queueWrite(const <TransferRecord>[]);
  }

  Future<void> _queueWrite(List<TransferRecord> records) {
    final previous = _saveQueue.catchError((Object _) {});
    _saveQueue = previous.then((_) => _writeRecords(records));
    return _saveQueue;
  }

  List<TransferRecord> _retainedRecords(Iterable<TransferRecord> records) {
    final retained = records.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return retained.length <= maxRecords
        ? retained
        : retained.sublist(retained.length - maxRecords);
  }

  Future<void> _writeRecords(List<TransferRecord> records) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString(
      encoder.convert(records.map((record) => record.toJson()).toList()),
    );
  }
}