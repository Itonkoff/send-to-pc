import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_security/shared_security.dart';
import 'package:shared_storage/shared_storage.dart';

void main() {
  test('sha256 matches a known vector', () {
    expect(
      sha256OfBytes(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('windows filename sanitizer removes unsafe input', () {
    expect(sanitizeWindowsFileName('CON.txt'), '_CON.txt');
    expect(sanitizeWindowsFileName('report.pdf   '), 'report.pdf');
    expect(sanitizeWindowsFileName('bad:name?.pdf'), 'bad_name_.pdf');
  });

  test('unique filename helper preserves extension', () async {
    final directory = await Directory.systemTemp.createTemp('send_to_pc_test_');
    try {
      await File(joinPath(directory.path, 'report.pdf')).writeAsString('old');
      final file = await uniqueFileInDirectory(directory, 'report.pdf');
      expect(file.path.endsWith('report (1).pdf'), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}