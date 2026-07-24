import 'dart:convert';
import 'dart:io';

import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';
import 'package:shared_security/shared_security.dart';

Future<void> main(List<String> args) async {
  final options = _PairingOptions.parse(args);
  if (options == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  if (options.allowSelfSigned) {
    client.badCertificateCallback = (_, __, ___) => true;
  }
  try {
    final request = await client.postUrl(options.uri(ApiRoutes.pairingRequest));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'protocolVersion': AppConstants.protocolVersion,
      'pairingToken': options.pairingToken,
      'deviceId': options.deviceId,
      'deviceName': options.deviceName,
      'platform': 'android',
    }));

    stdout.writeln('Pairing request sent. Approve it in the Windows app.');
    final response = await request.close().timeout(const Duration(minutes: 6));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Pairing failed (${response.statusCode}): $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    stdout.writeln("Pairing approved. Device token: ${decoded['deviceToken']}");
  } finally {
    client.close(force: true);
  }
}

class _PairingOptions {
  const _PairingOptions({
    required this.host,
    required this.port,
    required this.pairingToken,
    required this.deviceId,
    required this.deviceName,
    required this.scheme,
    required this.allowSelfSigned,
  });

  final String host;
  final int port;
  final String pairingToken;
  final String deviceId;
  final String deviceName;
  final String scheme;
  final bool allowSelfSigned;

  Uri uri(String path) => Uri(scheme: scheme, host: host, port: port, path: path);

  static _PairingOptions? parse(List<String> args) {
    if (args.contains('--help')) {
      return null;
    }

    var host = '127.0.0.1';
    var port = AppConstants.defaultPort;
    var token = Platform.environment['SEND_TO_PC_PAIRING_TOKEN'];
    var deviceId = 'phone-${randomUuidV4().replaceAll('-', '').substring(0, 8)}';
    var deviceName = 'Test Android Phone';
    var scheme = 'https';
    var allowSelfSigned = false;

    for (var i = 0; i < args.length; i += 1) {
      switch (args[i]) {
        case '--host':
          i += 1;
          host = _argAt(args, i) ?? host;
          break;
        case '--port':
          i += 1;
          port = int.tryParse(_argAt(args, i) ?? '') ?? port;
          break;
        case '--token':
          i += 1;
          token = _argAt(args, i) ?? token;
          break;
        case '--device-id':
          i += 1;
          deviceId = _argAt(args, i) ?? deviceId;
          break;
        case '--device-name':
          i += 1;
          deviceName = _argAt(args, i) ?? deviceName;
          break;
        case '--http':
          scheme = 'http';
          break;
        case '--https':
          scheme = 'https';
          break;
        case '--allow-self-signed':
          allowSelfSigned = true;
          break;
      }
    }

    if (token == null || token.isEmpty) {
      return null;
    }

    return _PairingOptions(
      host: host,
      port: port,
      pairingToken: token,
      deviceId: deviceId,
      deviceName: deviceName,
      scheme: scheme,
      allowSelfSigned: allowSelfSigned,
    );
  }
}

String? _argAt(List<String> args, int index) {
  if (index < 0 || index >= args.length) {
    return null;
  }
  return args[index];
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart scripts/test_pairing_request.dart --token <pairingToken> '
    '[--host 127.0.0.1] [--port 45873] [--https|--http] '
    '[--allow-self-signed]',
  );
  stdout.writeln('You can also set SEND_TO_PC_PAIRING_TOKEN instead of --token.');
}
