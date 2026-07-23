import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_models/shared_models.dart';

import '../../platform/android_share_bridge.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  late final AndroidShareBridge _shareBridge;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;
  StreamSubscription<List<SharedFile>>? _shareSubscription;
  StreamSubscription<TransferProgress>? _progressSubscription;
  List<SharedFile> _sharedFiles = const <SharedFile>[];
  List<PairedDevice> _pairedDevices = const <PairedDevice>[];
  List<TransferRecord> _transferHistory = const <TransferRecord>[];
  TransferProgress? _progress;
  String? _selectedDeviceId;
  String? _lastError;
  var _isSending = false;
  var _isPairing = false;
  var _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController();
    _portController = TextEditingController(text: '${AppConstants.defaultPort}');
    _tokenController = TextEditingController();
    _shareBridge = AndroidShareBridge();
    _shareSubscription = _shareBridge.watchIncomingSharedFiles().listen((files) {
      if (mounted) {
        setState(() => _sharedFiles = files);
      }
    });
    _progressSubscription = _shareBridge.watchTransferProgress().listen((progress) {
      if (mounted) {
        setState(() => _progress = progress);
      }
    });
    unawaited(_loadInitialFiles());
    unawaited(_loadPairedDevices());
    unawaited(_loadTransferHistory());
  }

  Future<void> _loadInitialFiles() async {
    final files = await _shareBridge.getInitialSharedFiles();
    if (mounted) {
      setState(() => _sharedFiles = files);
    }
  }

  Future<void> _loadPairedDevices() async {
    final devices = await _shareBridge.getPairedDevices();
    if (!mounted) {
      return;
    }

    setState(() {
      _pairedDevices = devices;
      final selectedStillExists = devices.any(
        (device) => device.id == _selectedDeviceId,
      );
      if (!selectedStillExists && devices.isNotEmpty) {
        _selectedDeviceId = devices.first.id;
        _applyDeviceToControllers(devices.first);
      }
    });
  }

  Future<void> _loadTransferHistory() async {
    final records = await _shareBridge.getTransferHistory();
    if (mounted) {
      setState(() => _transferHistory = records);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    unawaited(_shareSubscription?.cancel());
    unawaited(_progressSubscription?.cancel());
    unawaited(_shareBridge.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFiles = _sharedFiles.isNotEmpty;
    final controlsEnabled = !_isSending && !_isPairing && !_isDiscovering;
    final canSend = hasFiles && controlsEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send to PC'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              hasFiles ? 'Files selected' : 'Ready to share',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFiles
                  ? '${_sharedFiles.length} file${_sharedFiles.length == 1 ? '' : 's'} waiting for a paired computer.'
                  : 'Use Android share and choose Send to PC.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _SelectedFilesCard(
              files: _sharedFiles,
              onClear: hasFiles && !_isSending ? _clearFiles : null,
            ),
            const SizedBox(height: 16),
            _PairedComputersCard(
              devices: _pairedDevices,
              selectedDeviceId: _selectedDeviceId,
              enabled: controlsEnabled,
              isDiscovering: _isDiscovering,
              onSelected: _selectDevice,
              onForget: _forgetDevice,
              onDiscover: _discoverPairedDevices,
            ),
            const SizedBox(height: 16),
            _DestinationCard(
              hostController: _hostController,
              portController: _portController,
              tokenController: _tokenController,
              enabled: controlsEnabled,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canSend ? _sendFiles : null,
              icon: _isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_isSending ? 'Sending' : 'Send'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: controlsEnabled ? _pairNewComputer : null,
              icon: _isPairing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_scanner_outlined),
              label: Text(_isPairing ? 'Pairing' : 'Pair new computer'),
            ),
            if (_lastError != null) ...[
              const SizedBox(height: 16),
              _ErrorCard(message: _lastError!),
            ],
            if (_progress != null && _progress!.status != TransferStatus.completed) ...[
              const SizedBox(height: 16),
              _TransferProgressCard(progress: _progress!),
            ],
            const SizedBox(height: 24),
            _RecentTransfersCard(
              records: _transferHistory,
              onClear: _transferHistory.isEmpty || _isSending
                  ? null
                  : _clearTransferHistory,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFiles() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final token = _tokenController.text.trim();

    if (host.isEmpty || port == null || port <= 0 || port > 65535 || token.isEmpty) {
      setState(() => _lastError = 'Enter a PC host, port, and device token.');
      return;
    }

    setState(() {
      _isSending = true;
      _lastError = null;
      _progress = null;
    });

    try {
      await _shareBridge.sendSharedFiles(
        host: host,
        port: port,
        token: token,
        files: _sharedFiles,
      );
      await _shareBridge.clearSharedFiles();
      final history = await _shareBridge.getTransferHistory();
      if (mounted) {
        setState(() {
          _sharedFiles = const <SharedFile>[];
          _transferHistory = history;
          _progress = null;
        });
      }
    } on Object catch (error) {
      final history = await _shareBridge.getTransferHistory();
      if (mounted) {
        setState(() {
          _lastError = _errorMessage(error);
          _transferHistory = history;
          _progress = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pairNewComputer() async {
    final input = await _showPairingDialog();
    if (input == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (input.pairingPayload.isEmpty) {
      setState(() => _lastError = 'Enter the pairing payload from Windows.');
      return;
    }

    setState(() {
      _isPairing = true;
      _lastError = null;
    });

    try {
      final device = await _shareBridge.pairWithComputer(
        pairingPayload: input.pairingPayload,
        deviceName: input.deviceName,
        hostOverride: input.hostOverride,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pairedDevices = _upsertDevice(_pairedDevices, device);
        _selectedDeviceId = device.id;
        _applyDeviceToControllers(device);
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _lastError = _errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isPairing = false);
      }
    }
  }

  Future<_PairComputerInput?> _showPairingDialog() {
    return showDialog<_PairComputerInput>(
      context: context,
      builder: (context) => const _PairComputerDialog(),
    );
  }

  Future<void> _discoverPairedDevices() async {
    if (_pairedDevices.isEmpty) {
      setState(() => _lastError = 'Pair a computer before discovery.');
      return;
    }

    setState(() {
      _isDiscovering = true;
      _lastError = null;
    });

    try {
      final devices = await _shareBridge.discoverPairedDevices();
      if (!mounted) {
        return;
      }

      setState(() {
        _pairedDevices = devices;
        final selected = _selectedPairedDevice(devices, _selectedDeviceId) ??
            (devices.isEmpty ? null : devices.first);
        _selectedDeviceId = selected?.id;
        if (selected != null) {
          _applyDeviceToControllers(selected);
        }
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _lastError = _errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isDiscovering = false);
      }
    }
  }

  Future<void> _forgetDevice(PairedDevice device) async {
    await _shareBridge.forgetPairedDevice(device.id);
    if (!mounted) {
      return;
    }

    setState(() {
      _pairedDevices = _pairedDevices
          .where((candidate) => candidate.id != device.id)
          .toList(growable: false);
      if (_selectedDeviceId == device.id) {
        final next = _pairedDevices.isEmpty ? null : _pairedDevices.first;
        _selectedDeviceId = next?.id;
        if (next != null) {
          _applyDeviceToControllers(next);
        } else {
          _hostController.clear();
          _portController.text = '${AppConstants.defaultPort}';
          _tokenController.clear();
        }
      }
    });
  }

  Future<void> _clearFiles() async {
    await _shareBridge.clearSharedFiles();
    if (mounted) {
      setState(() => _sharedFiles = const <SharedFile>[]);
    }
  }

  Future<void> _clearTransferHistory() async {
    await _shareBridge.clearTransferHistory();
    if (mounted) {
      setState(() => _transferHistory = const <TransferRecord>[]);
    }
  }

  void _selectDevice(PairedDevice device) {
    setState(() {
      _selectedDeviceId = device.id;
      _lastError = null;
      _applyDeviceToControllers(device);
    });
  }

  void _applyDeviceToControllers(PairedDevice device) {
    _hostController.text = device.lastKnownAddress ?? '';
    _portController.text = '${device.lastKnownPort ?? AppConstants.defaultPort}';
    _tokenController.text = device.authenticationToken;
  }

  PairedDevice? _selectedPairedDevice(
    List<PairedDevice> devices,
    String? selectedId,
  ) {
    if (selectedId == null) {
      return null;
    }
    for (final device in devices) {
      if (device.id == selectedId) {
        return device;
      }
    }
    return null;
  }

  List<PairedDevice> _upsertDevice(
    List<PairedDevice> devices,
    PairedDevice device,
  ) {
    return <PairedDevice>[
      device,
      for (final existing in devices)
        if (existing.id != device.id && existing.deviceId != device.deviceId)
          existing,
    ];
  }
}

class _SelectedFilesCard extends StatelessWidget {
  const _SelectedFilesCard({
    required this.files,
    required this.onClear,
  });

  final List<SharedFile> files;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Selected files',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Clear files',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (files.isEmpty)
              Text(
                'No shared files yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final file in files) _SharedFileTile(file: file),
          ],
        ),
      ),
    );
  }
}

class _SharedFileTile extends StatelessWidget {
  const _SharedFileTile({required this.file});

  final SharedFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${file.mimeType}${file.size == null ? '' : ' - ${_formatBytes(file.size!)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedComputersCard extends StatelessWidget {
  const _PairedComputersCard({
    required this.devices,
    required this.selectedDeviceId,
    required this.enabled,
    required this.isDiscovering,
    required this.onSelected,
    required this.onForget,
    required this.onDiscover,
  });

  final List<PairedDevice> devices;
  final String? selectedDeviceId;
  final bool enabled;
  final bool isDiscovering;
  final ValueChanged<PairedDevice> onSelected;
  final ValueChanged<PairedDevice> onForget;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Paired computers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Discover paired computers',
                  onPressed: enabled && devices.isNotEmpty ? onDiscover : null,
                  icon: isDiscovering
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              Text(
                'No paired computers saved.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final device in devices)
                ListTile(
                  enabled: enabled,
                  contentPadding: EdgeInsets.zero,
                  selected: device.id == selectedDeviceId,
                  leading: Icon(
                    device.id == selectedDeviceId
                        ? Icons.check_circle_outline
                        : Icons.desktop_windows_outlined,
                  ),
                  title: Text(
                    device.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _deviceEndpoint(device),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Forget computer',
                    onPressed: enabled ? () => onForget(device) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: enabled ? () => onSelected(device) : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.hostController,
    required this.portController,
    required this.tokenController,
    required this.enabled,
  });

  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController tokenController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.computer_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Destination computer',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: hostController,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'PC host',
                      hintText: '192.168.1.25 or 10.0.2.2',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: portController,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tokenController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Device token',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferProgressCard extends StatelessWidget {
  const _TransferProgressCard({required this.progress});

  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    progress.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(progress.status.jsonName),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress.percentage),
            const SizedBox(height: 8),
            Text(
              'File ${progress.currentFileNumber} of ${progress.totalFileCount} - '
              '${_formatBytes(progress.bytesTransferred)} of ${_formatBytes(progress.totalBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTransfersCard extends StatelessWidget {
  const _RecentTransfersCard({
    required this.records,
    required this.onClear,
  });

  final List<TransferRecord> records;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recent transfers',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear history',
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (records.isEmpty)
              Text(
                'Transfer history will appear here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final record in records.take(10))
                _TransferHistoryTile(record: record),
          ],
        ),
      ),
    );
  }
}

class _TransferHistoryTile extends StatelessWidget {
  const _TransferHistoryTile({required this.record});

  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_transferStatusIcon(record.status), size: 20),
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
              const SizedBox(width: 8),
              Text(record.status.jsonName),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatBytes(record.bytesTransferred)} of '
            '${_formatBytes(record.fileSize)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (record.completedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              record.completedAt!.toLocal().toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (record.failureMessage != null) ...[
            const SizedBox(height: 2),
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
}

class _PairComputerDialog extends StatefulWidget {
  const _PairComputerDialog();

  @override
  State<_PairComputerDialog> createState() => _PairComputerDialogState();
}

class _PairComputerDialogState extends State<_PairComputerDialog> {
  late final TextEditingController _payloadController;
  late final TextEditingController _deviceNameController;
  late final TextEditingController _hostOverrideController;

  @override
  void initState() {
    super.initState();
    _payloadController = TextEditingController();
    _deviceNameController = TextEditingController(text: 'Android phone');
    _hostOverrideController = TextEditingController();
  }

  @override
  void dispose() {
    _payloadController.dispose();
    _deviceNameController.dispose();
    _hostOverrideController.dispose();
    super.dispose();
  }

  Future<void> _scanPairingPayload() async {
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => const _QrScannerDialog(),
    );
    if (!mounted || payload == null) {
      return;
    }
    _payloadController.text = payload.trim();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair computer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(
                labelText: 'Phone name',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostOverrideController,
              decoration: const InputDecoration(
                labelText: 'Host override',
                hintText: '192.168.1.x or 10.0.2.2',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _scanPairingPayload,
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('Scan QR code'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _payloadController,
              decoration: const InputDecoration(
                labelText: 'Pairing payload',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.multiline,
              minLines: 4,
              maxLines: 8,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_PairComputerInput(
              pairingPayload: _payloadController.text.trim(),
              deviceName: _deviceNameController.text.trim(),
              hostOverride: _hostOverrideController.text.trim(),
            ));
          },
          child: const Text('Pair'),
        ),
      ],
    );
  }
}

class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  late final MobileScannerController _controller;
  var _hasResult = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_hasResult) {
      return;
    }

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      _hasResult = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Scan pairing QR'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Camera scanner unavailable.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            placeholderBuilder: (context) => ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PairComputerInput {
  const _PairComputerInput({
    required this.pairingPayload,
    required this.deviceName,
    required this.hostOverride,
  });

  final String pairingPayload;
  final String deviceName;
  final String hostOverride;
}

String _errorMessage(Object error) {
  if (error is PlatformException) {
    final message = error.message ?? error.code;
    if (message.contains('PAIRING_TOKEN_EXPIRED') ||
        message.contains('No active pairing session')) {
      return 'Pairing session expired. Click New in the Windows app, then scan the fresh QR code or paste its payload.';
    }
    if (message.contains('PAIRING_TOKEN_INVALID')) {
      return 'Pairing token was rejected. Scan the fresh QR code from Windows or copy the full payload and try again.';
    }
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.contains('failed to connect') ||
        lowerMessage.contains('connection refused') ||
        lowerMessage.contains('timed out') ||
        lowerMessage.contains('timeout')) {
      return 'Could not reach the Windows receiver at that address. '
          'Make sure both devices are on the same Wi-Fi, then pair with '
          'the PC Wi-Fi IPv4 address in Host override if needed.';
    }
    return message;
  }
  return '$error';
}

IconData _transferStatusIcon(TransferStatus status) {
  return switch (status) {
    TransferStatus.completed => Icons.check_circle_outline,
    TransferStatus.failed => Icons.error_outline,
    TransferStatus.cancelled => Icons.cancel_outlined,
    TransferStatus.uploading => Icons.sync,
    TransferStatus.verifying => Icons.verified_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
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

String _deviceEndpoint(PairedDevice device) {
  final host = device.lastKnownAddress;
  if (host == null || host.isEmpty) {
    return 'Unknown host';
  }
  return '$host:${device.lastKnownPort ?? AppConstants.defaultPort}';
}
