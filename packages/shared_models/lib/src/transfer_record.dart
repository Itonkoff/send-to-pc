import 'transfer_status.dart';

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.senderDeviceId,
    required this.receiverDeviceId,
    required this.fileName,
    required this.safeFileName,
    required this.mimeType,
    required this.fileSize,
    required this.checksumAlgorithm,
    required this.checksum,
    required this.status,
    required this.bytesTransferred,
    this.temporaryPath,
    this.finalPath,
    this.failureCode,
    this.failureMessage,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    required this.updatedAt,
  });

  final String id;
  final String senderDeviceId;
  final String receiverDeviceId;
  final String fileName;
  final String safeFileName;
  final String mimeType;
  final int fileSize;
  final String checksumAlgorithm;
  final String checksum;
  final TransferStatus status;
  final int bytesTransferred;
  final String? temporaryPath;
  final String? finalPath;
  final String? failureCode;
  final String? failureMessage;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime updatedAt;

  double get progress {
    if (fileSize <= 0) {
      return status == TransferStatus.completed ? 1 : 0;
    }
    return (bytesTransferred / fileSize).clamp(0, 1).toDouble();
  }

  TransferRecord copyWith({
    String? id,
    String? senderDeviceId,
    String? receiverDeviceId,
    String? fileName,
    String? safeFileName,
    String? mimeType,
    int? fileSize,
    String? checksumAlgorithm,
    String? checksum,
    TransferStatus? status,
    int? bytesTransferred,
    String? temporaryPath,
    String? finalPath,
    String? failureCode,
    String? failureMessage,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? updatedAt,
  }) {
    return TransferRecord(
      id: id ?? this.id,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      receiverDeviceId: receiverDeviceId ?? this.receiverDeviceId,
      fileName: fileName ?? this.fileName,
      safeFileName: safeFileName ?? this.safeFileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      checksumAlgorithm: checksumAlgorithm ?? this.checksumAlgorithm,
      checksum: checksum ?? this.checksum,
      status: status ?? this.status,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      temporaryPath: temporaryPath ?? this.temporaryPath,
      finalPath: finalPath ?? this.finalPath,
      failureCode: failureCode ?? this.failureCode,
      failureMessage: failureMessage ?? this.failureMessage,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      id: json['id'] as String,
      senderDeviceId: json['senderDeviceId'] as String,
      receiverDeviceId: json['receiverDeviceId'] as String,
      fileName: json['fileName'] as String,
      safeFileName: json['safeFileName'] as String,
      mimeType: json['mimeType'] as String,
      fileSize: json['fileSize'] as int,
      checksumAlgorithm: json['checksumAlgorithm'] as String,
      checksum: json['checksum'] as String,
      status: transferStatusFromJson(json['status']),
      bytesTransferred: json['bytesTransferred'] as int,
      temporaryPath: json['temporaryPath'] as String?,
      finalPath: json['finalPath'] as String?,
      failureCode: json['failureCode'] as String?,
      failureMessage: json['failureMessage'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      startedAt: _dateTimeOrNull(json['startedAt']),
      completedAt: _dateTimeOrNull(json['completedAt']),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'senderDeviceId': senderDeviceId,
      'receiverDeviceId': receiverDeviceId,
      'fileName': fileName,
      'safeFileName': safeFileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'checksumAlgorithm': checksumAlgorithm,
      'checksum': checksum,
      'status': status.jsonName,
      'bytesTransferred': bytesTransferred,
      'temporaryPath': temporaryPath,
      'finalPath': finalPath,
      'failureCode': failureCode,
      'failureMessage': failureMessage,
      'createdAt': createdAt.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String);
}

