import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:send_to_pc_windows/core/settings/receiver_settings.dart';
import 'package:send_to_pc_windows/core/settings/settings_repository.dart';

void main() {
  test('settings repository persists receiver settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'send_to_pc_settings_',
    );
    try {
      final repository = SettingsRepository(appDataPath: directory.path);
      final initial = await repository.load();
      final updated = initial.appSettings.copyWith(
        receiveFolder: 'C:\\SendToPC\\Inbox',
        listenPort: 45999,
        maximumFileSizeBytes: 128 * 1024 * 1024,
        minimizeToTray: false,
      );

      await repository.save(
        ReceiverSettingsSnapshot(
          deviceId: initial.deviceId,
          deviceName: initial.deviceName,
          appSettings: updated,
        ),
      );

      final loaded = await repository.load();
      expect(loaded.deviceId, initial.deviceId);
      expect(loaded.deviceName, initial.deviceName);
      expect(loaded.appSettings.receiveFolder, 'C:\\SendToPC\\Inbox');
      expect(loaded.appSettings.listenPort, 45999);
      expect(loaded.appSettings.maximumFileSizeBytes, 128 * 1024 * 1024);
      expect(loaded.appSettings.minimizeToTray, isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}