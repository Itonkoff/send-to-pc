class AppConstants {
  const AppConstants._();

  static const productName = 'Send to PC';
  static const protocolVersion = 1;
  static const serverVersion = '0.1.0';
  static const defaultPort = 45873;
  static const defaultDiscoveryService = '_sendtopc._tcp.local';
  static const checksumAlgorithm = 'SHA-256';
  static const maxSingleFileSizeBytes = 5 * 1024 * 1024 * 1024;
  static const maxFilesPerShare = 20;
  static const maxConcurrentTransfers = 2;
}

