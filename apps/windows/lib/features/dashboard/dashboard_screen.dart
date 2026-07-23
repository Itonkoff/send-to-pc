import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_models/shared_models.dart';

import '../../core/pairing/pairing_coordinator.dart';
import '../../core/server/receiver_app_controller.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.controller,
    super.key,
  });

  final ReceiverAppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Send to PC'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _StatusPill(isRunning: controller.isRunning),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(controller: controller),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 860;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _ReceiverCard(controller: controller),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _PairingCard(controller: controller),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _ReceiverCard(controller: controller),
                          const SizedBox(height: 16),
                          _PairingCard(controller: controller),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _TransferHistoryCard(
                    records: controller.records,
                    onClear: controller.records.isEmpty
                        ? null
                        : () {
                            unawaited(
                              _confirmClearTransferHistory(context, controller),
                            );
                          },
                    onCancelTransfer: (record) {
                      unawaited(controller.cancelTransfer(record.id));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final ReceiverAppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          controller.settingsSnapshot.deviceName,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Receiver ${controller.isRunning ? 'listening' : 'paused'} on '
          '${controller.localAddress}:${controller.listeningPort}',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReceiverCard extends StatelessWidget {
  const _ReceiverCard({required this.controller});

  final ReceiverAppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = controller.startupError;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Receiver',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Receiver settings',
                  onPressed: () {
                    unawaited(_showReceiverSettingsDialog(context, controller));
                  },
                  icon: const Icon(Icons.tune_outlined),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: controller.isRunning
                      ? controller.stopServer
                      : controller.startServer,
                  icon: Icon(
                    controller.isRunning ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(controller.isRunning ? 'Pause' : 'Start'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoRow(
              icon: Icons.folder_outlined,
              label: 'Receive folder',
              value: controller.settingsSnapshot.appSettings.receiveFolder,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.router_outlined,
              label: 'Local endpoint',
              value: 'http://${controller.localAddress}:'
                  '${controller.listeningPort}/api/v1',
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.sd_storage_outlined,
              label: 'Maximum file size',
              value: _formatBytes(
                controller.settingsSnapshot.appSettings.maximumFileSizeBytes,
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.swap_horiz_outlined,
              label: 'Maximum concurrent transfers',
              value: '${controller.settingsSnapshot.appSettings.maximumConcurrentTransfers}',
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.power_settings_new_outlined,
              label: 'Start with Windows',
              value: controller.settingsSnapshot.appSettings.startWithWindows
                  ? 'Enabled'
                  : 'Disabled',
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  unawaited(_openReceiveFolder(context, controller));
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open folder'),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$error',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _showReceiverSettingsDialog(
  BuildContext context,
  ReceiverAppController controller,
) async {
  final nextSettings = await showDialog<AppSettings>(
    context: context,
    builder: (context) => _ReceiverSettingsDialog(
      settings: controller.settingsSnapshot.appSettings,
    ),
  );

  if (nextSettings != null) {
    await controller.updateAppSettings(nextSettings);
  }
}

class _ReceiverSettingsDialog extends StatefulWidget {
  const _ReceiverSettingsDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_ReceiverSettingsDialog> createState() =>
      _ReceiverSettingsDialogState();
}

class _ReceiverSettingsDialogState extends State<_ReceiverSettingsDialog> {
  late final TextEditingController _receiveFolderController;
  late final TextEditingController _portController;
  late final TextEditingController _maxFileSizeController;
  late final TextEditingController _maxConcurrentTransfersController;
  late bool _startWithWindows;
  late bool _minimizeToTray;
  late bool _showNotifications;
  String? _error;

  @override
  void initState() {
    super.initState();
    _receiveFolderController = TextEditingController(
      text: widget.settings.receiveFolder,
    );
    _portController = TextEditingController(
      text: '${widget.settings.listenPort}',
    );
    _maxFileSizeController = TextEditingController(
      text: _megabytes(widget.settings.maximumFileSizeBytes).toString(),
    );
    _maxConcurrentTransfersController = TextEditingController(
      text: '${widget.settings.maximumConcurrentTransfers}',
    );
    _startWithWindows = widget.settings.startWithWindows;
    _minimizeToTray = widget.settings.minimizeToTray;
    _showNotifications = widget.settings.showNotifications;
  }

  @override
  void dispose() {
    _receiveFolderController.dispose();
    _portController.dispose();
    _maxFileSizeController.dispose();
    _maxConcurrentTransfersController.dispose();
    super.dispose();
  }

  Future<void> _pickReceiveFolder() async {
    final initialFolder = _receiveFolderController.text.trim();
    final quotedFolder = _powerShellStringLiteral(initialFolder);
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
\$dialog.Description = 'Choose Send to PC receive folder'
\$dialog.ShowNewFolderButton = \$true
if ([System.IO.Directory]::Exists($quotedFolder)) {
  \$dialog.SelectedPath = $quotedFolder
}
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Out.Write(\$dialog.SelectedPath)
}
''';

    final result = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-STA', '-Command', script],
    );
    if (!mounted) {
      return;
    }

    if (result.exitCode != 0) {
      setState(() => _error = 'Could not open the folder picker.');
      return;
    }

    final selectedFolder = result.stdout.toString().trim();
    if (selectedFolder.isNotEmpty) {
      setState(() {
        _receiveFolderController.text = selectedFolder;
        _error = null;
      });
    }
  }

  void _save() {
    final receiveFolder = _receiveFolderController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final maxFileSizeMb = int.tryParse(_maxFileSizeController.text.trim());
    final maxConcurrentTransfers = int.tryParse(
      _maxConcurrentTransfersController.text.trim(),
    );

    if (receiveFolder.isEmpty) {
      setState(() => _error = 'Enter a receive folder.');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter a valid port between 1 and 65535.');
      return;
    }
    if (maxFileSizeMb == null || maxFileSizeMb < 1) {
      setState(() => _error = 'Enter a maximum file size of at least 1 MB.');
      return;
    }
    if (maxConcurrentTransfers == null || maxConcurrentTransfers < 1) {
      setState(() => _error = 'Allow at least 1 concurrent transfer.');
      return;
    }

    Navigator.of(context).pop(
      widget.settings.copyWith(
        receiveFolder: receiveFolder,
        listenPort: port,
        maximumFileSizeBytes: maxFileSizeMb * 1024 * 1024,
        maximumConcurrentTransfers: maxConcurrentTransfers,
        startWithWindows: _startWithWindows,
        minimizeToTray: _minimizeToTray,
        showNotifications: _showNotifications,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Receiver settings'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _receiveFolderController,
                      decoration: const InputDecoration(
                        labelText: 'Receive folder',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Browse folders',
                    onPressed: _pickReceiveFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Listening port',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _maxFileSizeController,
                decoration: const InputDecoration(
                  labelText: 'Maximum file size (MB)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _maxConcurrentTransfersController,
                decoration: const InputDecoration(
                  labelText: 'Maximum concurrent transfers',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _startWithWindows,
                onChanged: (value) {
                  setState(() => _startWithWindows = value ?? false);
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Start with Windows'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _minimizeToTray,
                onChanged: (value) {
                  setState(() => _minimizeToTray = value ?? true);
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Minimize to system tray'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: _showNotifications,
                onChanged: (value) {
                  setState(() => _showNotifications = value ?? true);
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Show notifications'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}

int _megabytes(int bytes) {
  return (bytes / (1024 * 1024)).round().clamp(1, 1 << 31).toInt();
}

String _powerShellStringLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

Future<void> _openReceiveFolder(
  BuildContext context,
  ReceiverAppController controller,
) async {
  final folder = controller.settingsSnapshot.appSettings.receiveFolder;
  try {
    await Directory(folder).create(recursive: true);
    await Process.start(
      'explorer.exe',
      <String>[folder],
      mode: ProcessStartMode.detached,
    );
  } on Object catch (error) {
    if (context.mounted) {
      _showExplorerError(context, error);
    }
  }
}

Future<void> _showFileInExplorer(BuildContext context, String path) async {
  try {
    await Process.start(
      'explorer.exe',
      <String>['/select,$path'],
      mode: ProcessStartMode.detached,
    );
  } on Object catch (error) {
    if (context.mounted) {
      _showExplorerError(context, error);
    }
  }
}

void _showExplorerError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Could not open Explorer: $error')),
  );
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.controller});

  final ReceiverAppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = controller.activePairingSession;
    final payloadText = session == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(session.payload.toJson());
    final payloadQrText = session == null
        ? null
        : jsonEncode(session.payload.toJson());
    final requests = controller.pairingRequests;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Pairing',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: controller.createPairingSession,
                  icon: const Icon(Icons.add_link),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Device ID',
              value: controller.settingsSnapshot.deviceId,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.key_outlined,
              label: 'Test client token',
              value: controller.bootstrapToken,
              monospace: true,
            ),
            const SizedBox(height: 16),
            if (payloadText == null)
              Text(
                'Create a pairing session to show the versioned QR payload.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text('Pairing QR', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xffd7e1ec)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: payloadQrText!,
                        version: QrVersions.auto,
                        size: 220,
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pairing payload',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xfff0f4f8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xffd7e1ec)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              payloadText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Expires ${session!.payload.expiresAt.toLocal()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text('Pairing requests', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (requests.isEmpty)
              Text(
                'No phone requests yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final request in requests) ...[
                _PairingRequestTile(
                  request: request,
                  onApprove: () {
                    unawaited(controller.approvePairingRequest(request.id));
                  },
                  onReject: () {
                    controller.rejectPairingRequest(request.id);
                  },
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 18),
            Text('Trusted devices', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (controller.pairedDevices.isEmpty)
              Text(
                'No trusted phones yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final device in controller.pairedDevices)
                _TrustedDeviceTile(
                  device: device,
                  onRevoke: () {
                    unawaited(_confirmRevokeDevice(
                      context,
                      controller,
                      device,
                    ));
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _PairingRequestTile extends StatelessWidget {
  const _PairingRequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final PairingRequestSnapshot request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = request.status == PairingRequestStatus.pending;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffd7e1ec)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(request.status.label),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${request.platform} - ${request.deviceId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (request.remoteAddress != null) ...[
              const SizedBox(height: 2),
              Text(
                request.remoteAddress!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmRevokeDevice(
  BuildContext context,
  ReceiverAppController controller,
  PairedDevice device,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Revoke device'),
      content: Text(
        '${device.deviceName} will need to pair again before sending files.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.block_outlined),
          label: const Text('Revoke'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await controller.revokeDevice(device.deviceId);
  }
}

class _TrustedDeviceTile extends StatelessWidget {
  const _TrustedDeviceTile({
    required this.device,
    required this.onRevoke,
  });

  final PairedDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revoked = device.isRevoked || !device.isTrusted;
    final statusColor = revoked
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            revoked
                ? Icons.block_outlined
                : Icons.verified_user_outlined,
            size: 20,
            color: statusColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${device.platform} - ${device.deviceId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  revoked ? 'revoked' : 'trusted',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: revoked ? 'Device revoked' : 'Revoke device',
            onPressed: revoked ? null : onRevoke,
            icon: const Icon(Icons.block_outlined),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmClearTransferHistory(
  BuildContext context,
  ReceiverAppController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear transfer history'),
      content: const Text(
        'Completed and failed transfer records will be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Clear'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await controller.clearTransferHistory();
  }
}

class _TransferHistoryCard extends StatelessWidget {
  const _TransferHistoryCard({
    required this.records,
    required this.onClear,
    required this.onCancelTransfer,
  });

  final List<TransferRecord> records;
  final VoidCallback? onClear;
  final ValueChanged<TransferRecord> onCancelTransfer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Recent transfers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Clear transfer history',
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (records.isEmpty)
              Text(
                'No transfers yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: [
                  for (final record in records)
                    _TransferTile(
                      record: record,
                      onCancel: onCancelTransfer,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.record,
    required this.onCancel,
  });

  final TransferRecord record;
  final ValueChanged<TransferRecord> onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCancel = _isActiveTransferStatus(record.status);
    final speed = _transferSpeedBytesPerSecond(record);
    final remaining = _estimatedRemainingTime(record, speed);
    final detailParts = <String>[
      '${_formatBytes(record.bytesTransferred)} of ${_formatBytes(record.fileSize)}',
      if (speed != null) '${_formatBytes(speed.round())}/s',
      if (remaining != null) '${_formatDuration(remaining)} remaining',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon(record.status), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  record.safeFileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(record.status.jsonName),
              if (canCancel) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Cancel transfer',
                  onPressed: () => onCancel(record),
                  icon: const Icon(Icons.cancel_outlined),
                ),
              ] else if (record.finalPath != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Show in folder',
                  onPressed: () {
                    unawaited(_showFileInExplorer(context, record.finalPath!));
                  },
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'From ${record.senderDeviceId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: record.progress),
          const SizedBox(height: 6),
          Text(
            detailParts.join(' - '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (record.failureMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              record.failureMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _statusIcon(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed => Icons.check_circle_outline,
      TransferStatus.failed => Icons.error_outline,
      TransferStatus.cancelled => Icons.cancel_outlined,
      TransferStatus.uploading => Icons.sync,
      TransferStatus.verifying => Icons.verified_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: monospace ? 'Consolas' : null,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

bool _isActiveTransferStatus(TransferStatus status) {
  return switch (status) {
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

double? _transferSpeedBytesPerSecond(TransferRecord record) {
  if (record.bytesTransferred <= 0) {
    return null;
  }
  final start = record.startedAt ?? record.createdAt;
  final end = _isActiveTransferStatus(record.status)
      ? DateTime.now()
      : (record.completedAt ?? record.updatedAt);
  final elapsedSeconds = end.difference(start).inMilliseconds / 1000;
  if (elapsedSeconds <= 0) {
    return null;
  }
  return record.bytesTransferred / elapsedSeconds;
}

Duration? _estimatedRemainingTime(TransferRecord record, double? speed) {
  if (!_isActiveTransferStatus(record.status) || speed == null || speed <= 0) {
    return null;
  }
  final remainingBytes = record.fileSize - record.bytesTransferred;
  if (remainingBytes <= 0) {
    return null;
  }
  return Duration(seconds: (remainingBytes / speed).ceil());
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes < 60) {
    return '${minutes}m ${seconds}s';
  }
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return '${hours}h ${remainingMinutes}m';
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isRunning});

  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isRunning ? Colors.green.shade700 : Colors.orange.shade800;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(
              isRunning ? Icons.circle : Icons.pause_circle_outline,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              isRunning ? 'Listening' : 'Paused',
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}
