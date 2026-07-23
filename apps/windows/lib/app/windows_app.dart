import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../core/server/receiver_app_controller.dart';
import '../features/dashboard/dashboard_screen.dart';
import 'windows_theme.dart';

class SendToPcWindowsApp extends StatefulWidget {
  const SendToPcWindowsApp({
    required this.controller,
    super.key,
  });

  final ReceiverAppController controller;

  @override
  State<SendToPcWindowsApp> createState() => _SendToPcWindowsAppState();
}

class _SendToPcWindowsAppState extends State<SendToPcWindowsApp>
    with WindowListener, tray.TrayListener {
  var _isQuitting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    tray.trayManager.addListener(this);
    widget.controller.addListener(_handleControllerChanged);
    unawaited(_initializeDesktopShell());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    tray.trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Send to PC',
      debugShowCheckedModeBanner: false,
      theme: buildWindowsTheme(),
      home: DashboardScreen(controller: widget.controller),
    );
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(tray.trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        unawaited(_showWindow());
        break;
      case 'open_folder':
        unawaited(_openReceiveFolder());
        break;
      case 'toggle_receiving':
        if (widget.controller.isRunning) {
          unawaited(widget.controller.stopServer());
        } else {
          unawaited(widget.controller.startServer());
        }
        break;
      case 'quit':
        unawaited(_quitApp());
        break;
    }
  }

  void _handleControllerChanged() {
    unawaited(_syncTrayMenu());
  }

  Future<void> _initializeDesktopShell() async {
    try {
      await windowManager.setPreventClose(true);
      await tray.trayManager.setIcon(_trayIconPath());
      await _syncTrayMenu();
    } on Object {
      // Tray plugins are not available in widget tests and may be unavailable
      // on unsupported desktop shells. The receiver should still run normally.
    }
  }

  Future<void> _syncTrayMenu() async {
    try {
      final status = widget.controller.isRunning ? 'Listening' : 'Paused';
      final menu = tray.Menu(
        items: [
          tray.MenuItem(key: 'open', label: 'Open Send to PC'),
          tray.MenuItem(key: 'open_folder', label: 'Show receive folder'),
          tray.MenuItem.separator(),
          tray.MenuItem(
            key: 'toggle_receiving',
            label: widget.controller.isRunning
                ? 'Pause receiving'
                : 'Resume receiving',
          ),
          tray.MenuItem.separator(),
          tray.MenuItem(key: 'quit', label: 'Quit Send to PC'),
        ],
      );
      await tray.trayManager.setToolTip('Send to PC - $status');
      await tray.trayManager.setContextMenu(menu);
    } on Object {
      // See _initializeDesktopShell.
    }
  }

  Future<void> _handleWindowClose() async {
    if (_isQuitting ||
        !widget.controller.settingsSnapshot.appSettings.minimizeToTray) {
      await windowManager.destroy();
      return;
    }

    await windowManager.hide();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openReceiveFolder() async {
    final folder = widget.controller.settingsSnapshot.appSettings.receiveFolder;
    await Directory(folder).create(recursive: true);
    await Process.start(
      'explorer.exe',
      <String>[folder],
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> _quitApp() async {
    _isQuitting = true;
    await tray.trayManager.destroy();
    await windowManager.destroy();
  }

  String _trayIconPath() {
    final candidates = <String>[
      'windows/runner/resources/app_icon.ico',
      'apps/windows/windows/runner/resources/app_icon.ico',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return candidates.first;
  }
}