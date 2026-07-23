import 'dart:async';

import 'package:shared_models/shared_models.dart';
import 'package:shared_protocol/shared_protocol.dart';
import 'package:shared_security/shared_security.dart';

import '../server/trusted_device_store.dart';

class PairingCoordinator {
  PairingCoordinator({
    required this.receiverDeviceId,
    required this.receiverDeviceName,
    required this.hostProvider,
    List<String> Function()? hostAlternativesProvider,
    required this.portProvider,
    required this.trustedDevices,
    this.onChanged,
  }) : hostAlternativesProvider =
            hostAlternativesProvider ?? (() => const <String>[]);

  final String receiverDeviceId;
  final String receiverDeviceName;
  final String Function() hostProvider;
  final List<String> Function() hostAlternativesProvider;
  final int Function() portProvider;
  final TrustedDeviceStore trustedDevices;
  final void Function()? onChanged;

  PairingSessionSnapshot? _activeSession;
  final List<PairingRequestSnapshot> _requests = <PairingRequestSnapshot>[];
  final Map<String, Completer<PairingDecision>> _waiters = <String, Completer<PairingDecision>>{};

  PairingSessionSnapshot? get activeSession {
    final session = _activeSession;
    if (session == null) {
      return null;
    }
    if (session.isExpired) {
      _activeSession = null;
      return null;
    }
    return session;
  }

  List<PairingRequestSnapshot> get requests => List.unmodifiable(_requests.reversed);

  PairingSessionSnapshot createSession() {
    final now = DateTime.now().toUtc();
    final host = hostProvider();
    final hostAlternatives = <String>{
      host,
      ...hostAlternativesProvider(),
    }.where((candidate) => candidate.trim().isNotEmpty).toList(growable: false);
    final session = PairingSessionSnapshot(
      id: randomUuidV4(),
      token: secureToken(),
      payload: PairingPayload(
        protocolVersion: AppConstants.protocolVersion,
        deviceId: receiverDeviceId,
        deviceName: receiverDeviceName,
        host: host,
        hostAlternatives: hostAlternatives,
        port: portProvider(),
        pairingToken: secureToken(),
        certificateFingerprint: 'development-http',
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
      createdAt: now,
    );
    _activeSession = session;
    _notify();
    return session;
  }

  Future<Map<String, Object?>> handlePairingRequest(
    Map<String, dynamic> body, {
    String? remoteAddress,
  }) async {
    final session = activeSession;
    if (session == null) {
      throw const ProtocolError(
        code: ErrorCodes.pairingTokenExpired,
        message: 'No active pairing session is available.',
      );
    }

    final protocolVersion = body['protocolVersion'] as int?;
    if (protocolVersion != AppConstants.protocolVersion) {
      throw const ProtocolError(
        code: ErrorCodes.protocolVersionUnsupported,
        message: 'The pairing request uses an unsupported protocol version.',
      );
    }

    final token = body['pairingToken'] as String?;
    if (token == null || !constantTimeEquals(token, session.payload.pairingToken)) {
      throw const ProtocolError(
        code: ErrorCodes.pairingTokenInvalid,
        message: 'The pairing token is invalid.',
      );
    }

    final request = PairingRequestSnapshot(
      id: randomUuidV4(),
      deviceId: _requiredString(body, 'deviceId'),
      deviceName: _requiredString(body, 'deviceName'),
      platform: _requiredString(body, 'platform'),
      remoteAddress: remoteAddress,
      requestedAt: DateTime.now().toUtc(),
      status: PairingRequestStatus.pending,
    );
    _requests.add(request);
    final completer = Completer<PairingDecision>();
    _waiters[request.id] = completer;
    _notify();

    final decision = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _replaceRequest(request.copyWith(status: PairingRequestStatus.expired));
        _waiters.remove(request.id);
        _notify();
        return const PairingDecision.rejected(
          code: ErrorCodes.pairingTokenExpired,
          message: 'The pairing request expired before approval.',
        );
      },
    );

    if (!decision.approved) {
      throw ProtocolError(
        code: decision.failureCode ?? ErrorCodes.pairingRejected,
        message: decision.failureMessage ?? 'The pairing request was rejected.',
      );
    }

    final pairedDevice = decision.device!;
    _activeSession = null;
    return {
      'status': 'approved',
      'protocolVersion': AppConstants.protocolVersion,
      'receiverDeviceId': receiverDeviceId,
      'receiverDeviceName': receiverDeviceName,
      'deviceToken': pairedDevice.authenticationToken,
      'certificateFingerprint': pairedDevice.certificateFingerprint,
    };
  }

  Future<void> approve(String requestId) async {
    final request = _requestById(requestId);
    if (request == null || request.status != PairingRequestStatus.pending) {
      return;
    }

    final device = await trustedDevices.trustDevice(
      deviceId: request.deviceId,
      deviceName: request.deviceName,
      platform: request.platform,
      certificateFingerprint: 'development-http',
      lastKnownAddress: request.remoteAddress,
    );
    _replaceRequest(request.copyWith(status: PairingRequestStatus.approved));
    _waiters.remove(requestId)?.complete(PairingDecision.approved(device));
    _notify();
  }

  void reject(String requestId) {
    final request = _requestById(requestId);
    if (request == null || request.status != PairingRequestStatus.pending) {
      return;
    }

    _replaceRequest(request.copyWith(status: PairingRequestStatus.rejected));
    _waiters.remove(requestId)?.complete(
          const PairingDecision.rejected(
            code: ErrorCodes.pairingRejected,
            message: 'The Windows user rejected the pairing request.',
          ),
        );
    _notify();
  }

  PairingRequestSnapshot? _requestById(String requestId) {
    for (final request in _requests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  void _replaceRequest(PairingRequestSnapshot replacement) {
    final index = _requests.indexWhere((request) => request.id == replacement.id);
    if (index >= 0) {
      _requests[index] = replacement;
    }
  }

  String _requiredString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw ProtocolError(
      code: ErrorCodes.internalError,
      message: 'Pairing request is missing $key.',
    );
  }

  void _notify() => onChanged?.call();
}

class PairingSessionSnapshot {
  const PairingSessionSnapshot({
    required this.id,
    required this.token,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String token;
  final PairingPayload payload;
  final DateTime createdAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(payload.expiresAt);
}

enum PairingRequestStatus {
  pending,
  approved,
  rejected,
  expired,
}

extension PairingRequestStatusText on PairingRequestStatus {
  String get label => name;
}

class PairingRequestSnapshot {
  const PairingRequestSnapshot({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.requestedAt,
    required this.status,
    this.remoteAddress,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? remoteAddress;
  final DateTime requestedAt;
  final PairingRequestStatus status;

  PairingRequestSnapshot copyWith({
    PairingRequestStatus? status,
  }) {
    return PairingRequestSnapshot(
      id: id,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
      remoteAddress: remoteAddress,
      requestedAt: requestedAt,
      status: status ?? this.status,
    );
  }
}

class PairingDecision {
  const PairingDecision._({
    required this.approved,
    this.device,
    this.failureCode,
    this.failureMessage,
  });

  const PairingDecision.approved(PairedDevice device)
      : this._(approved: true, device: device);

  const PairingDecision.rejected({
    required String code,
    required String message,
  }) : this._(
          approved: false,
          failureCode: code,
          failureMessage: message,
        );

  final bool approved;
  final PairedDevice? device;
  final String? failureCode;
  final String? failureMessage;
}
