import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_security/shared_security.dart';
import 'package:shared_storage/shared_storage.dart';

import '../settings/app_data_paths.dart';

class ReceiverTlsCertificate {
  const ReceiverTlsCertificate({
    required this.context,
    required this.fingerprint,
  });

  final SecurityContext context;
  final String fingerprint;
}

class TlsCertificateStore {
  TlsCertificateStore({
    String? appDataPath,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
        runProcess,
  })  : _directory = Directory(
          joinPath(AppDataPaths.root(overridePath: appDataPath), 'tls'),
        ),
        _runProcess = runProcess ??
            ((executable, arguments) => Process.run(executable, arguments));

  final Directory _directory;
  final Future<ProcessResult> Function(String executable, List<String> arguments)
      _runProcess;

  File get _certificateFile => File(joinPath(_directory.path, 'receiver.crt'));
  File get _privateKeyFile => File(joinPath(_directory.path, 'receiver.key'));

  Future<ReceiverTlsCertificate> ensureReady() async {
    await _directory.create(recursive: true);
    if (!await _certificateFile.exists() || !await _privateKeyFile.exists()) {
      await regenerate();
    }
    return _load();
  }

  Future<ReceiverTlsCertificate> regenerate() async {
    await _directory.create(recursive: true);
    final openssl = await _findOpenSslExecutable();
    if (openssl == null) {
      throw StateError(
        'OpenSSL was not found. Install Git for Windows or set OPENSSL_EXE.',
      );
    }

    final result = await _runProcess(openssl, <String>[
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-sha256',
      '-nodes',
      '-days',
      '1825',
      '-subj',
      '/CN=Send to PC Receiver',
      '-keyout',
      _privateKeyFile.path,
      '-out',
      _certificateFile.path,
    ]);

    if (result.exitCode != 0) {
      throw StateError(
        'OpenSSL certificate generation failed: ${result.stderr}',
      );
    }

    return _load();
  }

  Future<ReceiverTlsCertificate> _load() async {
    final context = SecurityContext()
      ..useCertificateChain(_certificateFile.path)
      ..usePrivateKey(_privateKeyFile.path);
    final fingerprint = await _certificateFingerprint(_certificateFile);
    return ReceiverTlsCertificate(
      context: context,
      fingerprint: 'sha256:$fingerprint',
    );
  }

  Future<String?> _findOpenSslExecutable() async {
    final configured = Platform.environment['OPENSSL_EXE'];
    if (configured != null && configured.trim().isNotEmpty) {
      final file = File(configured.trim());
      if (await file.exists()) {
        return file.path;
      }
    }

    final candidates = <String>[
      r'C:\Program Files\Git\usr\bin\openssl.exe',
      r'C:\Program Files (x86)\Git\usr\bin\openssl.exe',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    try {
      final result = await _runProcess('where.exe', <String>['openssl']);
      if (result.exitCode == 0) {
        final lines = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);
        for (final line in lines) {
          if (await File(line).exists()) {
            return line;
          }
        }
      }
    } on Object {
      // A missing PATH entry is fine; the fixed Git paths above cover the
      // common Windows development install.
    }

    return null;
  }
}

Future<String> _certificateFingerprint(File certificateFile) async {
  final pem = await certificateFile.readAsString();
  final base64Body = pem
      .split(RegExp(r'\r?\n'))
      .where((line) => !line.startsWith('-----'))
      .join();
  return sha256OfBytes(base64Decode(base64Body));
}
