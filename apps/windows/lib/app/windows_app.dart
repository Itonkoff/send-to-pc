import 'package:flutter/material.dart';

import '../core/server/receiver_app_controller.dart';
import '../features/dashboard/dashboard_screen.dart';
import 'windows_theme.dart';

class SendToPcWindowsApp extends StatelessWidget {
  const SendToPcWindowsApp({
    required this.controller,
    super.key,
  });

  final ReceiverAppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Send to PC',
      debugShowCheckedModeBanner: false,
      theme: buildWindowsTheme(),
      home: DashboardScreen(controller: controller),
    );
  }
}