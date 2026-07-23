const _reservedNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

String sanitizeWindowsFileName(
  String requested, {
  String fallback = 'received-file',
}) {
  var name = requested.trim();
  name = name.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  name = name.replaceAll('..', '.');
  name = name.replaceAll(RegExp(r'\s+'), ' ');
  name = name.replaceAll(RegExp(r'[ .]+$'), '');

  if (name.isEmpty || name == '.') {
    name = fallback;
  }

  final parts = _splitExtension(name);
  if (_reservedNames.contains(parts.base.toUpperCase())) {
    name = '_$name';
  }

  if (name.length > 240) {
    final shortenedBaseLength = 240 - parts.extension.length;
    final keepLength = shortenedBaseLength.clamp(1, parts.base.length).toInt();
    final shortenedBase = parts.base.substring(0, keepLength);
    name = '$shortenedBase${parts.extension}';
    name = name.replaceAll(RegExp(r'[ .]+$'), '');
  }

  return name;
}

bool isWindowsReservedFileName(String fileName) {
  final parts = _splitExtension(fileName);
  return _reservedNames.contains(parts.base.toUpperCase());
}

({String base, String extension}) _splitExtension(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  if (lastDot <= 0 || lastDot == fileName.length - 1) {
    return (base: fileName, extension: '');
  }
  return (
    base: fileName.substring(0, lastDot),
    extension: fileName.substring(lastDot),
  );
}

