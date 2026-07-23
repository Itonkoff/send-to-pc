import 'package:flutter/material.dart';

import '../features/home/mobile_home_screen.dart';
import 'theme.dart';

class SendToPcMobileApp extends StatelessWidget {
  const SendToPcMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Send to PC',
      debugShowCheckedModeBanner: false,
      theme: buildMobileTheme(),
      home: const MobileHomeScreen(),
    );
  }
}