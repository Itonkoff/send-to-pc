import 'dart:convert';
import 'dart:io';

import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';
import 'package:shared_security/shared_security.dart';

Future<void> main(List<String> args) async {
  final options = _UploadOptions.parse(args);
  if (options == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final file = File(options.filePath);
  if (!await file.exists()) {
    stderr.writeln('File not found: ${options.filePath}');
    exitCode = 66;
    return;
  }

  final length = await file.length();
  final checksum = await sha256OfFile(file);
  final client = HttpClient();

  try {
    final transfer = await _createTransfer(
      client: client,
      options: options,
      file: file,
      length: length,
      checksum: checksum,
    );
    await _uploadContent(
      client: client,
      options: options,
      file: file,
      length: length,
      transferId: transfer.transferId,
    );
    final completed = await _completeTransfer(
      client: client,
      options: options,
      transferId: transfer.transferId,
    );

    stdout.writeln("Transfer completed: ${completed['finalPath']}");
  } finally {
    client.close(force: true);
  }
}

Future<TransferCreateResponse> _createTransfer({
  required HttpClient client,
  required _UploadOptions options,
  required File file,
  required int length,
  required String checksum,
}) async {
  final request = await client.postUrl(options.uri(ApiRoutes.transfers));
  _authorize(request, options.token);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(TransferRequest(
    fileName: _fileNameFor(file),
    mimeType: 'application/octet-stream',
    fileSize: length,
    checksumAlgorithm: AppConstants.checksumAlgorithm,
    checksum: checksum,
  ).toJson()));

  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode != HttpStatus.created) {
    throw StateError('Create transfer failed (${response.statusCode}): $body');
  }
  return TransferCreateResponse.fromJson(
    jsonDecode(body) as Map<String, dynamic>,
  );
}

Future<void> _uploadContent({
  required HttpClient client,
  required _UploadOptions options,
  required File file,
  required int length,
  required String transferId,
}) async {
  final request = await client.putUrl(
    options.uri(ApiRoutes.transferContent(transferId)),
  );
  _authorize(request, options.token);
  request.headers.contentType = ContentType.binary;
  request.contentLength = length;
  await request.addStream(file.openRead());

  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('Upload failed (${response.statusCode}): $body');
  }
}

Future<Map<String, dynamic>> _completeTransfer({
  required HttpClient client,
  required _UploadOptions options,
  required String transferId,
}) async {
  final request = await client.postUrl(
    options.uri(ApiRoutes.transferComplete(transferId)),
  );
  _authorize(request, options.token);

  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('Complete failed (${response.statusCode}): $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

String _fileNameFor(File file) {
  return file.path.replaceAll('\\', '/').split('/').last;
}

void _authorize(HttpClientRequest request, String token) {
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
}

class _UploadOptions {
  const _UploadOptions({
    required this.filePath,
    required this.host,
    required this.port,
    required this.token,
  });

  final String filePath;
  final String host;
  final int port;
  final String token;

  Uri uri(String path) => Uri(scheme: 'http', host: host, port: port, path: path);

  static _UploadOptions? parse(List<String> args) {
    if (args.isEmpty || args.contains('--help')) {
      return null;
    }

    String? filePath;
    var host = '127.0.0.1';
    var port = AppConstants.defaultPort;
    var token = Platform.environment['SEND_TO_PC_TOKEN'];

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
        default:
          filePath ??= args[i];
          break;
      }
    }

    if (filePath == null || token == null || token.isEmpty) {
      return null;
    }

    return _UploadOptions(
      filePath: filePath,
      host: host,
      port: port,
      token: token,
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
    'Usage: dart scripts/test_upload.dart <file> --token <token> '
    '[--host 127.0.0.1] [--port 45873]',
  );
  stdout.writeln('You can also set SEND_TO_PC_TOKEN instead of --token.');
}