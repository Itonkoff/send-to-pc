class ApiRoutes {
  const ApiRoutes._();

  static const base = '/api/v1';
  static const device = '$base/device';
  static const pairingRequest = '$base/pairing/request';
  static const pairingApprove = '$base/pairing/approve';
  static const pairingReject = '$base/pairing/reject';
  static const transfers = '$base/transfers';
  static const files = '$base/files';

  static String transfer(String transferId) => '$transfers/$transferId';
  static String transferContent(String transferId) =>
      '$transfers/$transferId/content';
  static String transferComplete(String transferId) =>
      '$transfers/$transferId/complete';
}

