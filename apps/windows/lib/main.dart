import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/windows_app.dart';
import 'core/server/receiver_app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final controller = await ReceiverAppController.create();
  runApp(SendToPcWindowsApp(controller: controller));
  unawaited(controller.initialize());
}