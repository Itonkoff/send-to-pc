enum TransferStatus {
  pending,
  connecting,
  uploading,
  uploaded,
  verifying,
  completed,
  failed,
  cancelled,
}

extension TransferStatusJson on TransferStatus {
  String get jsonName => name;
}

TransferStatus transferStatusFromJson(Object? value) {
  final text = value?.toString();
  return TransferStatus.values.firstWhere(
    (status) => status.jsonName == text,
    orElse: () => TransferStatus.failed,
  );
}

