import 'dart:async';

import 'package:flutter/material.dart';

import 'app/windows_app.dart';
import 'core/server/receiver_app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await ReceiverAppController.create();
  runApp(SendToPcWindowsApp(controller: controller));
  unawaited(controller.initialize());
}