import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';
import 'package:shared_security/shared_security.dart';
import 'package:shared_storage/shared_storage.dart';

import '../pairing/pairing_coordinator.dart';
import '../storage/receive_file_storage.dart';
import 'transfer_record_repository.dart';
import 'trusted_device_store.dart';

class ReceiverServer {
  ReceiverServer({
    required this.deviceInfo,
    required this.settings,
    required this.storage,
    required this.trustedDevices,
    required this.pairingCoordinator,
    required this.transferHistory,
  });

  final DeviceInfo deviceInfo;
  AppSettings settings;
  final ReceiveFileStorage storage;
  final TrustedDeviceStore trustedDevices;
  final PairingCoordinator pairingCoordinator;
  final TransferRecordRepository transferHistory;

  final Map<String, TransferRecord> _records = <String, TransferRecord>{};
  final StreamController<TransferRecord> _recordEvents =
      StreamController<TransferRecord>.broadcast();
  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  List<TransferRecord> get records => List.unmodifiable(_records.values);
  Stream<TransferRecord> get recordEvents => _recordEvents.stream;

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    await storage.ensureReady();
    if (_records.isEmpty) {
      await _loadPersistedRecords();
    }
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      settings.listenPort,
    );
    unawaited(_server!.forEach(_handleRequest));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  void updateSettings(AppSettings nextSettings) {
    settings = nextSettings;
    storage.updateReceiveFolder(nextSettings.receiveFolder);
  }

  Future<void> clearTransferHistory() async {
    _records.clear();
    await transferHistory.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == ApiRoutes.device) {
        await _writeJson(request.response, HttpStatus.ok, deviceInfo.toJson());
        return;
      }

      if (request.method == 'POST' &&
          request.uri.path == ApiRoutes.pairingRequest) {
        await _handlePairingRequest(request);
        return;
      }

      final device = trustedDevices.authenticate(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      if (device == null) {
        await _writeError(
          request.response,
          HttpStatus.unauthorized,
          const ProtocolError(
            code: ErrorCodes.authenticationFailed,
            message: 'A trusted bearer token is required.',
          ),
        );
        return;
      }

      if (request.method == 'POST' && request.uri.path == ApiRoutes.transfers) {
        await _createTransfer(request, device);
        return;
      }

      final routed = await _tryHandleTransferRoute(request, device);
      if (routed) {
        return;
      }

      await _writeError(
        request.response,
        HttpStatus.notFound,
        const ProtocolError(
          code: ErrorCodes.transferNotFound,
          message: 'The requested API route was not found.',
        ),
      );
    } on ProtocolError catch (error) {
      await _writeError(request.response, HttpStatus.badRequest, error);
    } on Object {
      await _writeError(
        request.response,
        HttpStatus.internalServerError,
        const ProtocolError(
          code: ErrorCodes.internalError,
          message: 'The receiver could not complete the request.',
        ),
      );
    }
  }

  Future<void> _handlePairingRequest(HttpRequest request) async {
    final decoded = await _readJson(request);
    final response = await pairingCoordinator.handlePairingRequest(
      decoded,
      remoteAddress: request.connectionInfo?.remoteAddress.address,
    );
    await _writeJson(request.response, HttpStatus.ok, response);
  }

  Future<bool> _tryHandleTransferRoute(
    HttpRequest request,
    PairedDevice device,
  ) async {
    final segments = request.uri.pathSegments;
    if (segments.length < 4 ||
        segments[0] != 'api' ||
        segments[1] != 'v1' ||
        segments[2] != 'transfers') {
      return false;
    }

    final transferId = segments[3];

    if (segments.length == 4 && request.method == 'GET') {
      final record = _records[transferId];
      if (record == null) {
        await _missingTransfer(request.response, transferId);
      } else {
        await _writeJson(request.response, HttpStatus.ok, record.toJson());
      }
      return true;
    }

    if (segments.length == 4 && request.method == 'DELETE') {
      await _cancelTransfer(request, transferId);
      return true;
    }

    if (segments.length == 5 &&
        segments[4] == 'content' &&
        request.method == 'PUT') {
      await _receiveTransferContent(request, transferId);
      return true;
    }

    if (segments.length == 5 &&
        segments[4] == 'complete' &&
        request.method == 'POST') {
      await _completeTransfer(request, transferId, device);
      return true;
    }

    return false;
  }

  Future<void> _createTransfer(
    HttpRequest request,
    PairedDevice device,
  ) async {
    final decoded = await _readJson(request);
    final transferRequest = TransferRequest.fromJson(decoded);

    if (transferRequest.fileSize < 0 ||
        transferRequest.fileSize > settings.maximumFileSizeBytes) {
      await _writeError(
        request.response,
        HttpStatus.requestEntityTooLarge,
        const ProtocolError(
          code: ErrorCodes.fileTooLarge,
          message: 'The requested file is larger than the configured limit.',
        ),
      );
      return;
    }

    if (transferRequest.checksumAlgorithm.toUpperCase() !=
        AppConstants.checksumAlgorithm) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        const ProtocolError(
          code: ErrorCodes.internalError,
          message: 'Only SHA-256 checksums are supported.',
        ),
      );
      return;
    }

    final safeFileName = sanitizeWindowsFileName(transferRequest.fileName);
    final now = DateTime.now();
    final transferId = randomUuidV4();
    final record = TransferRecord(
      id: transferId,
      senderDeviceId: device.deviceId,
      receiverDeviceId: deviceInfo.deviceId,
      fileName: transferRequest.fileName,
      safeFileName: safeFileName,
      mimeType: transferRequest.mimeType,
      fileSize: transferRequest.fileSize,
      checksumAlgorithm: AppConstants.checksumAlgorithm,
      checksum: transferRequest.checksum.toLowerCase(),
      status: TransferStatus.pending,
      bytesTransferred: 0,
      createdAt: now,
      updatedAt: now,
    );
    _updateRecord(record);

    await _writeJson(
      request.response,
      HttpStatus.created,
      TransferCreateResponse(
        transferId: transferId,
        status: TransferStatus.pending.jsonName,
        uploadUrl: ApiRoutes.transferContent(transferId),
      ).toJson(),
    );
  }

  Future<void> _receiveTransferContent(
    HttpRequest request,
    String transferId,
  ) async {
    final record = _records[transferId];
    if (record == null) {
      await _missingTransfer(request.response, transferId);
      return;
    }
    if (record.status == TransferStatus.completed) {
      await _writeError(
        request.response,
        HttpStatus.conflict,
        ProtocolError(
          code: ErrorCodes.transferAlreadyCompleted,
          message: 'The transfer is already completed.',
          transferId: transferId,
        ),
      );
      return;
    }
    if (record.status == TransferStatus.failed ||
        record.status == TransferStatus.cancelled) {
      await _writeError(
        request.response,
        HttpStatus.conflict,
        ProtocolError(
          code: ErrorCodes.uploadInterrupted,
          message: 'The transfer is no longer active.',
          transferId: transferId,
        ),
      );
      return;
    }

    final contentLength = request.contentLength;
    if (contentLength > settings.maximumFileSizeBytes) {
      await _failTransfer(
        record,
        ErrorCodes.fileTooLarge,
        'The upload content length is larger than the configured limit.',
      );
      await _writeError(
        request.response,
        HttpStatus.requestEntityTooLarge,
        ProtocolError(
          code: ErrorCodes.fileTooLarge,
          message: 'The upload content length is larger than the configured limit.',
          transferId: transferId,
        ),
      );
      return;
    }

    if (contentLength > record.fileSize) {
      await _failTransfer(
        record,
        ErrorCodes.uploadInterrupted,
        'The upload content length is larger than declared.',
      );
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        ProtocolError(
          code: ErrorCodes.uploadInterrupted,
          message: 'The upload content length is larger than declared.',
          transferId: transferId,
        ),
      );
      return;
    }

    var current = record.copyWith(
      status: TransferStatus.uploading,
      startedAt: record.startedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    if (current.temporaryPath == null) {
      current = current.copyWith(
        temporaryPath: await storage.createPartFile(record.safeFileName),
      );
    }
    _updateRecord(current);

    final partFile = File(current.temporaryPath!);
    final sink = partFile.openWrite();
    var bytesTransferred = 0;
    var lastProgressEvent = 0;

    try {
      await for (final chunk in request) {
        if (bytesTransferred + chunk.length > record.fileSize) {
          await sink.close();
          await _safeDelete(partFile);
          await _failTransfer(
            current,
            ErrorCodes.uploadInterrupted,
            'The upload sent more bytes than declared.',
          );
          await _writeError(
            request.response,
            HttpStatus.badRequest,
            ProtocolError(
              code: ErrorCodes.uploadInterrupted,
              message: 'The upload sent more bytes than declared.',
              transferId: transferId,
            ),
          );
          return;
        }

        sink.add(chunk);
        bytesTransferred += chunk.length;

        if (bytesTransferred - lastProgressEvent >= 256 * 1024 ||
            bytesTransferred == record.fileSize) {
          lastProgressEvent = bytesTransferred;
          current = current.copyWith(
            bytesTransferred: bytesTransferred,
            updatedAt: DateTime.now(),
          );
          _updateRecord(current);
        }
      }
      await sink.close();

      if (bytesTransferred != record.fileSize) {
        await _safeDelete(partFile);
        await _failTransfer(
          current,
          ErrorCodes.uploadInterrupted,
          'The upload ended before all declared bytes arrived.',
        );
        await _writeError(
          request.response,
          HttpStatus.badRequest,
          ProtocolError(
            code: ErrorCodes.uploadInterrupted,
            message: 'The upload ended before all declared bytes arrived.',
            transferId: transferId,
          ),
        );
        return;
      }

      current = current.copyWith(
        status: TransferStatus.uploaded,
        bytesTransferred: bytesTransferred,
        updatedAt: DateTime.now(),
      );
      _updateRecord(current);
      await _writeJson(request.response, HttpStatus.ok, current.toJson());
    } on Object {
      await sink.close();
      await _failTransfer(
        current,
        ErrorCodes.uploadInterrupted,
        'The upload stream was interrupted.',
      );
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        ProtocolError(
          code: ErrorCodes.uploadInterrupted,
          message: 'The upload stream was interrupted.',
          transferId: transferId,
        ),
      );
    }
  }

  Future<void> _completeTransfer(
    HttpRequest request,
    String transferId,
    PairedDevice device,
  ) async {
    final record = _records[transferId];
    if (record == null || record.temporaryPath == null) {
      await _missingTransfer(request.response, transferId);
      return;
    }
    if (record.senderDeviceId != device.deviceId) {
      await _writeError(
        request.response,
        HttpStatus.forbidden,
        ProtocolError(
          code: ErrorCodes.authenticationFailed,
          message: 'The transfer belongs to a different sender.',
          transferId: transferId,
        ),
      );
      return;
    }
    if (record.status != TransferStatus.uploaded) {
      await _writeError(
        request.response,
        HttpStatus.conflict,
        ProtocolError(
          code: ErrorCodes.uploadInterrupted,
          message: 'The transfer content has not been fully uploaded.',
          transferId: transferId,
        ),
      );
      return;
    }

    var current = record.copyWith(
      status: TransferStatus.verifying,
      updatedAt: DateTime.now(),
    );
    _updateRecord(current);

    final partFile = File(record.temporaryPath!);
    final checksum = await sha256OfFile(partFile);
    if (!constantTimeEquals(checksum.toLowerCase(), record.checksum)) {
      await _safeDelete(partFile);
      await _failTransfer(
        current,
        ErrorCodes.checksumMismatch,
        'The uploaded file failed integrity verification.',
      );
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        ProtocolError(
          code: ErrorCodes.checksumMismatch,
          message: 'The uploaded file failed integrity verification.',
          transferId: transferId,
        ),
      );
      return;
    }

    final finalPath = await storage.finalizeFile(
      temporaryPath: record.temporaryPath!,
      requestedFileName: record.safeFileName,
    );
    current = current.copyWith(
      status: TransferStatus.completed,
      bytesTransferred: record.fileSize,
      finalPath: finalPath,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _updateRecord(current);
    await _writeJson(request.response, HttpStatus.ok, current.toJson());
  }

  Future<void> _cancelTransfer(
    HttpRequest request,
    String transferId,
  ) async {
    final record = _records[transferId];
    if (record == null) {
      await _missingTransfer(request.response, transferId);
      return;
    }

    if (record.temporaryPath != null) {
      await _safeDelete(File(record.temporaryPath!));
    }

    final cancelled = record.copyWith(
      status: TransferStatus.cancelled,
      updatedAt: DateTime.now(),
      completedAt: DateTime.now(),
    );
    _updateRecord(cancelled);
    await _writeJson(request.response, HttpStatus.ok, cancelled.toJson());
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const ProtocolError(
        code: ErrorCodes.internalError,
        message: 'The request body must be a JSON object.',
      );
    }
    return decoded;
  }

  Future<void> _missingTransfer(
    HttpResponse response,
    String transferId,
  ) async {
    await _writeError(
      response,
      HttpStatus.notFound,
      ProtocolError(
        code: ErrorCodes.transferNotFound,
        message: 'The transfer was not found.',
        transferId: transferId,
      ),
    );
  }

  Future<void> _failTransfer(
    TransferRecord record,
    String code,
    String message,
  ) async {
    _updateRecord(
      record.copyWith(
        status: TransferStatus.failed,
        failureCode: code,
        failureMessage: message,
        completedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _loadPersistedRecords() async {
    final loaded = await transferHistory.load();
    var changed = false;
    final now = DateTime.now();

    _records.clear();
    for (final record in loaded) {
      final restored = _restoredRecord(record, now);
      changed = changed || restored.status != record.status;
      _records[restored.id] = restored;
    }

    if (changed) {
      await transferHistory.save(_records.values);
    }
  }

  TransferRecord _restoredRecord(TransferRecord record, DateTime now) {
    if (_isTerminalStatus(record.status)) {
      return record;
    }

    return record.copyWith(
      status: TransferStatus.failed,
      failureCode: ErrorCodes.uploadInterrupted,
      failureMessage: 'The receiver restarted before this transfer completed.',
      completedAt: record.completedAt ?? now,
      updatedAt: now,
    );
  }

  bool _isTerminalStatus(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed ||
      TransferStatus.failed ||
      TransferStatus.cancelled => true,
      _ => false,
    };
  }

  void _updateRecord(TransferRecord record) {
    _records[record.id] = record;
    if (_shouldPersistRecord(record)) {
      unawaited(transferHistory.save(_records.values));
    }
    _recordEvents.add(record);
  }

  bool _shouldPersistRecord(TransferRecord record) {
    return record.status != TransferStatus.uploading;
  }

  Future<void> _safeDelete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _writeError(
    HttpResponse response,
    int statusCode,
    ProtocolError error,
  ) async {
    await _writeJson(response, statusCode, error.toJson());
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Object? body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }
}
