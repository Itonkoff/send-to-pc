import 'dart:io';

import 'windows_filename.dart';

String defaultReceiveFolder() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return joinPath(joinPath(home, 'Downloads'), 'SendToPC');
}

String joinPath(String left, String right) {
  final separator = Platform.pathSeparator;
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left$separator$right';
}

Future<File> uniqueFileInDirectory(
  Directory directory,
  String requestedFileName,
) async {
  await directory.create(recursive: true);
  final safeName = sanitizeWindowsFileName(requestedFileName);
  final parts = splitExtension(safeName);

  for (var suffix = 0; suffix < 10000; suffix += 1) {
    final candidateName = suffix == 0
        ? safeName
        : '${parts.base} ($suffix)${parts.extension}';
    final candidate = File(joinPath(directory.path, candidateName));
    if (!await candidate.exists()) {
      return candidate;
    }
  }

  throw FileSystemException(
    'Could not allocate a unique filename.',
    directory.path,
  );
}

({String base, String extension}) splitExtension(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  if (lastDot <= 0 || lastDot == fileName.length - 1) {
    return (base: fileName, extension: '');
  }
  return (
    base: fileName.substring(0, lastDot),
    extension: fileName.substring(lastDot),
  );
}

