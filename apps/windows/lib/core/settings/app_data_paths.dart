import 'dart:io';

import 'package:shared_storage/shared_storage.dart';

class AppDataPaths {
  const AppDataPaths._();

  static String root({String? overridePath}) {
    if (overridePath != null) {
      return overridePath;
    }
    final userProfile = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final fallbackRoot = joinPath(joinPath(userProfile, 'AppData'), 'Roaming');
    return joinPath(Platform.environment['APPDATA'] ?? fallbackRoot, 'SendToPC');
  }
}