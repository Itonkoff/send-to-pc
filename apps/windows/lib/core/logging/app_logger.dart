import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_storage/shared_storage.dart';

import '../settings/app_data_paths.dart';

class AppLogger {
  AppLogger({String? appDataPath, DateTime Function()? now})
      : _file = File(
          joinPath(
            AppDataPaths.root(overridePath: appDataPath),
            'send_to_pc.log.jsonl',
          ),
        ),
        _now = now ?? DateTime.now;

  final File _file;
  final DateTime Function() _now;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> debug(String event, {Map<String, Object?> data = const {}}) {
    return _write('Debug', event, data);
  }

  Future<void> information(
    String event, {
    Map<String, Object?> data = const {},
  }) {
    return _write('Information', event, data);
  }

  Future<void> warning(String event, {Map<String, Object?> data = const {}}) {
    return _write('Warning', event, data);
  }

  Future<void> error(String event, {Map<String, Object?> data = const {}}) {
    return _write('Error', event, data);
  }

  Future<void> _write(
    String level,
    String event,
    Map<String, Object?> data,
  ) {
    final previous = _writeQueue.catchError((Object _) {});
    final entry = <String, Object?>{
      'timestamp': _now().toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'data': _sanitize(data),
    };
    _writeQueue = previous.then((_) => _append(entry));
    return _writeQueue;
  }

  Future<void> _append(Map<String, Object?> entry) async {
    await _file.parent.create(recursive: true);
    final sink = _file.openWrite(mode: FileMode.append);
    try {
      sink.writeln(jsonEncode(entry));
    } finally {
      await sink.close();
    }
  }

  Object? _sanitize(Object? value, [String? key]) {
    final normalizedKey = key?.toLowerCase() ?? '';
    if (normalizedKey.contains('token') ||
        normalizedKey.contains('secret') ||
        normalizedKey.contains('privatekey') ||
        normalizedKey.contains('password')) {
      return '<redacted>';
    }

    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Iterable) {
      return value.map((entry) => _sanitize(entry)).toList(growable: false);
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _sanitize(entry.value, entry.key.toString()),
      };
    }
    return value.toString();
  }
}
