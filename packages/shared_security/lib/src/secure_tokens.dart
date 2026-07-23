import 'dart:convert';
import 'dart:math';

String secureToken({int byteLength = 32}) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String randomUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String two(int value) => value.toRadixString(16).padLeft(2, '0');
  final hex = bytes.map(two).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

bool constantTimeEquals(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  var diff = aBytes.length ^ bBytes.length;
  final maxLength = aBytes.length > bBytes.length ? aBytes.length : bBytes.length;

  for (var i = 0; i < maxLength; i += 1) {
    final left = i < aBytes.length ? aBytes[i] : 0;
    final right = i < bBytes.length ? bBytes[i] : 0;
    diff |= left ^ right;
  }

  return diff == 0;
}

