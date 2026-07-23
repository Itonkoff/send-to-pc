import 'dart:io';

import 'package:shared_models/shared_models.dart';

class WindowsNotificationService {
  Future<void> showIncomingTransfer(TransferRecord record) {
    return _showBalloon(
      title: 'Incoming transfer',
      message: '${record.safeFileName} from ${record.senderDeviceId}',
      icon: 'Info',
    );
  }

  Future<void> showTransferCompleted(TransferRecord record) {
    return _showBalloon(
      title: 'Transfer complete',
      message: '${record.safeFileName} received from ${record.senderDeviceId}',
      icon: 'Info',
    );
  }

  Future<void> showTransferFailed(TransferRecord record) {
    return _showBalloon(
      title: 'Transfer failed',
      message: '${record.safeFileName}: ${record.failureMessage ?? record.status.jsonName}',
      icon: 'Error',
    );
  }

  Future<void> showPairingRequest({
    required String deviceName,
    required String platform,
  }) {
    return _showBalloon(
      title: 'Pairing request',
      message: '$deviceName wants to pair as $platform.',
      icon: 'Info',
    );
  }

  Future<void> _showBalloon({
    required String title,
    required String message,
    required String icon,
  }) async {
    if (!Platform.isWindows) {
      return;
    }

    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
\$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
\$notifyIcon.Visible = \$true
\$notifyIcon.BalloonTipTitle = ${_powerShellStringLiteral(title)}
\$notifyIcon.BalloonTipText = ${_powerShellStringLiteral(message)}
\$notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::$icon
\$notifyIcon.ShowBalloonTip(5000)
Start-Sleep -Seconds 6
\$notifyIcon.Dispose()
''';

    try {
      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ],
        mode: ProcessStartMode.detached,
      );
    } on Object {
      // Notifications are useful, but a missing shell capability must not break
      // receiving files.
    }
  }
}

String _powerShellStringLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}