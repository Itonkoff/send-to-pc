class ProtocolError implements Exception {
  const ProtocolError({
    required this.code,
    required this.message,
    this.transferId,
  });

  final String code;
  final String message;
  final String? transferId;

  Map<String, Object?> toJson() {
    return {
      'code': code,
      'message': message,
      if (transferId != null) 'transferId': transferId,
    };
  }

  @override
  String toString() => '$code: $message';
}

