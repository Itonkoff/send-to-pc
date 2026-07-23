class ErrorCodes {
  const ErrorCodes._();

  static const authenticationFailed = 'AUTHENTICATION_FAILED';
  static const deviceRevoked = 'DEVICE_REVOKED';
  static const pairingTokenInvalid = 'PAIRING_TOKEN_INVALID';
  static const pairingTokenExpired = 'PAIRING_TOKEN_EXPIRED';
  static const pairingRejected = 'PAIRING_REJECTED';
  static const deviceNotFound = 'DEVICE_NOT_FOUND';
  static const deviceOffline = 'DEVICE_OFFLINE';
  static const transferNotFound = 'TRANSFER_NOT_FOUND';
  static const transferAlreadyCompleted = 'TRANSFER_ALREADY_COMPLETED';
  static const fileTooLarge = 'FILE_TOO_LARGE';
  static const insufficientDiskSpace = 'INSUFFICIENT_DISK_SPACE';
  static const invalidFileName = 'INVALID_FILE_NAME';
  static const invalidMimeType = 'INVALID_MIME_TYPE';
  static const uploadInterrupted = 'UPLOAD_INTERRUPTED';
  static const checksumMismatch = 'CHECKSUM_MISMATCH';
  static const networkTimeout = 'NETWORK_TIMEOUT';
  static const serverUnavailable = 'SERVER_UNAVAILABLE';
  static const protocolVersionUnsupported =
      'PROTOCOL_VERSION_UNSUPPORTED';
  static const internalError = 'INTERNAL_ERROR';
}

