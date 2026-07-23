import 'dart:convert';
import 'dart:io';

import 'package:shared_models/shared_models.dart';
import 'package:shared_security/shared_security.dart';
import 'package:shared_storage/shared_storage.dart';

import 'app_data_paths.dart';
import 'receiver_settings.dart';

class SettingsRepository {
  SettingsRepository({String? appDataPath})
      : _settingsFile = File(
          joinPath(AppDataPaths.root(overridePath: appDataPath), 'settings.json'),
        );

  final File _settingsFile;

  Future<ReceiverSettingsSnapshot> load() async {
    if (await _settingsFile.exists()) {
      final decoded = jsonDecode(await _settingsFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        return ReceiverSettingsSnapshot.fromJson(decoded);
      }
    }

    final snapshot = ReceiverSettingsSnapshot(
      deviceId: _newDeviceId(),
      deviceName: Platform.localHostname,
      appSettings: AppSettings(receiveFolder: defaultReceiveFolder()),
    );
    await save(snapshot);
    return snapshot;
  }

  Future<void> save(ReceiverSettingsSnapshot snapshot) async {
    await _settingsFile.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _settingsFile.writeAsString(encoder.convert(snapshot.toJson()));
  }

  static String _newDeviceId() {
    return 'pc-${randomUuidV4().replaceAll('-', '').substring(0, 8)}';
  }
}