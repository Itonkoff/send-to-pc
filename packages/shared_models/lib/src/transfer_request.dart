class TransferRequest {
  const TransferRequest({
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.checksumAlgorithm,
    required this.checksum,
  });

  final String fileName;
  final String mimeType;
  final int fileSize;
  final String checksumAlgorithm;
  final String checksum;

  factory TransferRequest.fromJson(Map<String, dynamic> json) {
    return TransferRequest(
      fileName: json['fileName'] as String,
      mimeType: json['mimeType'] as String,
      fileSize: json['fileSize'] as int,
      checksumAlgorithm: json['checksumAlgorithm'] as String,
      checksum: json['checksum'] as String,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'checksumAlgorithm': checksumAlgorithm,
      'checksum': checksum,
    };
  }
}

class TransferCreateResponse {
  const TransferCreateResponse({
    required this.transferId,
    required this.status,
    required this.uploadUrl,
  });

  final String transferId;
  final String status;
  final String uploadUrl;

  factory TransferCreateResponse.fromJson(Map<String, dynamic> json) {
    return TransferCreateResponse(
      transferId: json['transferId'] as String,
      status: json['status'] as String,
      uploadUrl: json['uploadUrl'] as String,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'transferId': transferId,
      'status': status,
      'uploadUrl': uploadUrl,
    };
  }
}

