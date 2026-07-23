import 'transfer_status.dart';

class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.status,
    this.currentFileNumber = 1,
    this.totalFileCount = 1,
    this.bytesPerSecond,
  });

  final String transferId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final TransferStatus status;
  final int currentFileNumber;
  final int totalFileCount;
  final double? bytesPerSecond;

  double get percentage {
    if (totalBytes <= 0) {
      return 0;
    }
    return (bytesTransferred / totalBytes).clamp(0, 1).toDouble();
  }
}

