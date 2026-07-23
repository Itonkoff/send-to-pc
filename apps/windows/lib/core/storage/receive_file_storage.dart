import 'dart:io';

import 'package:shared_storage/shared_storage.dart';

class ReceiveFileStorage {
  ReceiveFileStorage({required String receiveFolder})
      : receiveDirectory = Directory(receiveFolder);

  Directory receiveDirectory;

  void updateReceiveFolder(String receiveFolder) {
    receiveDirectory = Directory(receiveFolder);
  }

  Future<void> ensureReady() async {
    await receiveDirectory.create(recursive: true);
  }

  Future<String> createPartFile(String requestedFileName) async {
    await ensureReady();
    final safeName = sanitizeWindowsFileName(requestedFileName);
    final partFile = await uniqueFileInDirectory(
      receiveDirectory,
      '$safeName.part',
    );
    await partFile.create(exclusive: true);
    return partFile.path;
  }

  Future<String> finalizeFile({
    required String temporaryPath,
    required String requestedFileName,
  }) async {
    await ensureReady();
    final destination = await uniqueFileInDirectory(
      receiveDirectory,
      requestedFileName,
    );
    await File(temporaryPath).rename(destination.path);
    return destination.path;
  }
}