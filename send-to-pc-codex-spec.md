# Send to PC — Codex Implementation Specification

## 1. Project Overview

Build a local-first file transfer system that allows a user to share a file from an Android phone and send it directly to a paired Windows computer.

The Android application must appear in the Android share sheet as:

```text
Send to PC
```

The core user flow is:

```text
Open file in WhatsApp, Gmail, browser, or file manager
        ↓
Tap Share
        ↓
Select Send to PC
        ↓
Choose a paired computer
        ↓
Transfer file over the local network
        ↓
Receive file in a configured Windows folder
```

The system must not integrate directly with WhatsApp. It must use Android's standard share intent mechanism so it can receive files from any compatible Android application.

---

## 2. Primary Goals

The first version must:

1. Provide a Flutter Android sender application.
2. Provide a Flutter Windows receiver application.
3. Register the Android app as a share target.
4. Support sharing one or multiple files.
5. Pair Android and Windows devices using a QR code.
6. Discover paired Windows devices on the local network.
7. Transfer files over the local network.
8. Authenticate paired devices.
9. Stream files without loading entire files into memory.
10. Verify transferred files using SHA-256.
11. Save incoming files into a configurable Windows folder.
12. Show transfer progress and transfer history.
13. Run the Windows receiver from the system tray.
14. Start the Windows receiver automatically with Windows when enabled.
15. Display a Windows notification when a transfer completes.

---

## 3. Non-Goals for the MVP

Do not implement these features in the first version:

- Cloud relay
- Internet-based transfer
- User registration
- Password-based accounts
- Folder synchronization
- Automatic WhatsApp folder monitoring
- Clipboard synchronization
- Remote file browsing
- Multiple users on one device
- Web interface
- File editing
- Peer-to-peer transfer between two Android devices
- macOS support
- Linux support
- iOS support

The MVP is strictly:

```text
Android sender → Windows receiver
```

over the same local network.

---

## 4. Recommended Technology Stack

### Shared application framework

- Flutter
- Dart
- Riverpod for state management
- GoRouter for navigation
- Freezed for immutable models
- json_serializable for serialization
- Dio or `http` for network requests
- Drift or SQLite for local persistence

### Android-specific integration

Use Kotlin only where native Android integration is required.

Expected native Android responsibilities:

- Receive `ACTION_SEND`
- Receive `ACTION_SEND_MULTIPLE`
- Extract shared content URIs
- Read shared metadata
- Pass shared file references to Flutter
- Handle Android lifecycle cases when the app is already running
- Handle Android lifecycle cases when the app is launched from the share sheet

### Windows-specific integration

Use Flutter plugins or a small native Windows bridge for:

- System tray
- Windows notifications
- Startup with Windows
- Folder picker
- Optional firewall configuration guidance
- Keeping the receiver available while the main window is closed

---

## 5. High-Level Architecture

```text
┌──────────────────────────────┐
│ WhatsApp / Gmail / Browser / │
│ File Manager / Other App     │
└───────────────┬──────────────┘
                │
                │ Android Share Intent
                ▼
┌──────────────────────────────┐
│ Flutter Android Application  │
│                              │
│ - Share Intent Bridge        │
│ - File Metadata Reader       │
│ - Device Selection           │
│ - Pairing                    │
│ - Device Discovery           │
│ - Transfer Client            │
│ - Transfer Queue             │
│ - History                    │
└───────────────┬──────────────┘
                │
                │ Local HTTPS
                ▼
┌──────────────────────────────┐
│ Flutter Windows Application  │
│                              │
│ - Tray Application           │
│ - Local HTTPS Server         │
│ - Pairing Server             │
│ - Authentication            │
│ - File Receiver             │
│ - Integrity Verification    │
│ - Transfer History          │
│ - Notifications             │
└───────────────┬──────────────┘
                ▼
┌──────────────────────────────┐
│ Configured Receive Folder    │
│                              │
│ Example:                     │
│ C:\Users\User\Downloads\     │
│ SendToPC\                    │
└──────────────────────────────┘
```

---

## 6. Repository Structure

Use a monorepo.

```text
send-to-pc/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── api.md
│   ├── security.md
│   └── development.md
├── apps/
│   ├── mobile/
│   │   ├── android/
│   │   ├── lib/
│   │   ├── test/
│   │   └── pubspec.yaml
│   └── windows/
│       ├── windows/
│       ├── lib/
│       ├── test/
│       └── pubspec.yaml
├── packages/
│   ├── shared_models/
│   ├── shared_protocol/
│   ├── shared_security/
│   └── shared_storage/
└── scripts/
    ├── setup.ps1
    ├── run_mobile.ps1
    └── run_windows.ps1
```

Shared packages should contain reusable models and protocol definitions.

---

## 7. Android Application Architecture

Suggested structure:

```text
apps/mobile/lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── database/
│   ├── errors/
│   ├── networking/
│   ├── security/
│   ├── storage/
│   └── utils/
├── features/
│   ├── pairing/
│   ├── device_discovery/
│   ├── shared_files/
│   ├── transfer/
│   ├── transfer_history/
│   ├── paired_devices/
│   └── settings/
└── platform/
    ├── android_share_bridge.dart
    └── platform_channels.dart
```

### Android screens

Implement these screens:

1. Home
2. Incoming shared files
3. Paired computers
4. Pair new computer
5. Transfer progress
6. Transfer history
7. Settings

### Home screen

Show:

- Current paired computers
- Online/offline state
- Recent transfers
- Button to pair a new computer
- Button to manually select files
- Pending files received from the Android share sheet

### Shared-files screen

Show:

- File name
- MIME type
- File size
- Source URI
- Selected destination computer
- Remove file action
- Send action

Support multiple shared files.

---

## 8. Android Share Intent Integration

The Android app must register for:

```text
android.intent.action.SEND
android.intent.action.SEND_MULTIPLE
```

Supported MIME type registration should initially use:

```text
*/*
```

The implementation must:

1. Receive the incoming intent.
2. Extract one or more content URIs.
3. Read metadata using `ContentResolver`.
4. Determine:
   - display name
   - MIME type
   - size
   - URI
5. Pass the file metadata to Flutter.
6. Keep access to the content URI for the duration of the transfer.
7. Handle both cold start and warm start.
8. Avoid copying the entire file unless required.
9. Use a stream from the content URI during upload.

Recommended bridge:

```text
Kotlin Intent Handler
        ↓
EventChannel or MethodChannel
        ↓
Flutter SharedFileService
```

Suggested Dart model:

```dart
class SharedFile {
  final String id;
  final String uri;
  final String fileName;
  final String mimeType;
  final int? size;
}
```

---

## 9. Windows Application Architecture

Suggested structure:

```text
apps/windows/lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── database/
│   ├── server/
│   ├── security/
│   ├── storage/
│   ├── notifications/
│   └── utils/
├── features/
│   ├── pairing/
│   ├── incoming_transfers/
│   ├── transfer_history/
│   ├── paired_devices/
│   ├── receive_folder/
│   └── settings/
└── platform/
    ├── tray_service.dart
    ├── startup_service.dart
    └── windows_notifications.dart
```

### Windows screens

Implement:

1. Dashboard
2. Pairing QR screen
3. Incoming transfers
4. Transfer history
5. Paired devices
6. Settings

### Windows dashboard

Show:

- Receiver status
- Local IP address
- Listening port
- Receive folder
- Pairing status
- Paired devices
- Recent transfers
- Start/stop receiver action

---

## 10. Windows Tray Behavior

The Windows app must:

- Minimize to the tray.
- Keep the receiver server running when the main window is closed.
- Provide tray menu actions:
  - Open Send to PC
  - Show receive folder
  - Pause receiving
  - Resume receiving
  - Exit
- Display an incoming transfer indicator.
- Display transfer-complete notifications.

Closing the main window must not exit the application unless the user selects Exit.

---

## 11. Pairing Architecture

Pairing must occur once per device relationship.

### Pairing flow

```text
Windows app generates pairing session
        ↓
Windows app displays QR code
        ↓
Android app scans QR code
        ↓
Android app sends pairing request
        ↓
Windows app asks user to approve
        ↓
Windows app confirms pairing
        ↓
Both devices store trusted credentials
```

### QR payload

Use a versioned JSON payload.

Example:

```json
{
  "protocolVersion": 1,
  "deviceId": "pc-b71e13",
  "deviceName": "Brighton-PC",
  "host": "192.168.1.25",
  "port": 45873,
  "pairingToken": "one-time-random-token",
  "certificateFingerprint": "sha256-fingerprint",
  "expiresAt": "2026-07-17T14:30:00Z"
}
```

### Pairing token requirements

- Cryptographically random
- Single use
- Short expiry
- Stored only while pairing is active
- Invalidated after successful pairing
- Invalidated after rejection
- Invalidated after expiration

### Pairing approval

The Windows app must show:

- Phone name
- Phone device ID
- Platform
- Request time

The user must explicitly approve or reject the request.

---

## 12. Device Discovery

Use mDNS or DNS-SD for local discovery.

Windows should advertise:

```text
_sendtopc._tcp.local
```

Suggested service attributes:

```text
deviceId
deviceName
protocolVersion
port
```

The Android app should:

1. Search for `_sendtopc._tcp.local`.
2. Match discovered services against paired device IDs.
3. Update online/offline state.
4. Use the current discovered IP address.
5. Fall back to the last known address if discovery temporarily fails.
6. Never trust a discovered device only by name.

Identity must be based on the stored device ID and trusted credentials.

---

## 13. Network Protocol

Use HTTPS over the local network.

The Windows app acts as the server.

The Android app acts as the client.

Recommended default port:

```text
45873
```

The port must be configurable.

### API versioning

All API routes must begin with:

```text
/api/v1
```

### Required endpoints

```http
GET  /api/v1/device
POST /api/v1/pairing/request
POST /api/v1/pairing/approve
POST /api/v1/pairing/reject
POST /api/v1/transfers
PUT  /api/v1/transfers/{transferId}/content
POST /api/v1/transfers/{transferId}/complete
GET  /api/v1/transfers/{transferId}
DELETE /api/v1/transfers/{transferId}
```

For the MVP, the implementation may simplify file transfer into a single streamed upload endpoint:

```http
POST /api/v1/files
```

However, the internal architecture should permit resumable transfers later.

---

## 14. Device Information Endpoint

### Request

```http
GET /api/v1/device
```

### Response

```json
{
  "deviceId": "pc-b71e13",
  "deviceName": "Brighton-PC",
  "platform": "windows",
  "protocolVersion": 1,
  "serverVersion": "0.1.0",
  "requiresAuthentication": true
}
```

---

## 15. Transfer Creation

### Request

```http
POST /api/v1/transfers
Authorization: Bearer <device-token>
Content-Type: application/json
```

```json
{
  "fileName": "report.pdf",
  "mimeType": "application/pdf",
  "fileSize": 1048576,
  "checksumAlgorithm": "SHA-256",
  "checksum": "expected-checksum"
}
```

### Response

```json
{
  "transferId": "9ab89a06-4f08-4cdc-b499-fd333e58b040",
  "status": "pending",
  "uploadUrl": "/api/v1/transfers/9ab89a06-4f08-4cdc-b499-fd333e58b040/content"
}
```

---

## 16. File Upload

The upload must be streamed.

Do not read the full file into memory.

### Request

```http
PUT /api/v1/transfers/{transferId}/content
Authorization: Bearer <device-token>
Content-Type: application/octet-stream
Content-Length: <file-size>
```

The Windows receiver must:

1. Validate the authenticated device.
2. Validate the transfer record.
3. Check available disk space.
4. Create a temporary `.part` file.
5. Stream bytes directly into the temporary file.
6. Update progress.
7. Reject excess bytes.
8. Reject files larger than the configured maximum.
9. Mark the transfer as uploaded after the stream completes.

---

## 17. Transfer Completion

### Request

```http
POST /api/v1/transfers/{transferId}/complete
Authorization: Bearer <device-token>
```

### Receiver actions

1. Calculate SHA-256.
2. Compare it with the expected checksum.
3. If valid:
   - determine final safe filename
   - move the `.part` file to the receive folder
   - mark transfer as completed
   - send Windows notification
4. If invalid:
   - mark transfer as failed
   - delete or quarantine the temporary file
   - return a checksum mismatch error

---

## 18. Transfer States

Use these transfer states:

```text
pending
connecting
uploading
uploaded
verifying
completed
failed
cancelled
```

Suggested Dart enum:

```dart
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
```

---

## 19. Local Data Model

Use SQLite or Drift.

### PairedDevice

```text
id
deviceId
deviceName
platform
authenticationToken
certificateFingerprint
lastKnownAddress
lastSeenAt
createdAt
updatedAt
isTrusted
isRevoked
```

### Transfer

```text
id
senderDeviceId
receiverDeviceId
fileName
safeFileName
mimeType
fileSize
checksumAlgorithm
checksum
status
bytesTransferred
temporaryPath
finalPath
failureCode
failureMessage
createdAt
startedAt
completedAt
updatedAt
```

### AppSettings

```text
receiveFolder
listenPort
startWithWindows
minimizeToTray
showNotifications
maximumFileSizeBytes
allowMultipleFiles
autoAcceptTrustedDevices
```

`autoAcceptTrustedDevices` should default to true for file transfers after pairing.

Pairing requests must never be auto-approved.

---

## 20. File Naming and Storage

Default receive folder:

```text
C:\Users\<User>\Downloads\SendToPC
```

Incoming files must first be stored as:

```text
report.pdf.part
```

After checksum verification:

```text
report.pdf
```

If a file already exists, generate:

```text
report (1).pdf
report (2).pdf
report (3).pdf
```

The sender must never provide an absolute destination path.

The Windows receiver must sanitize filenames.

Reject or remove:

- `..`
- drive letters
- UNC paths
- path separators
- control characters
- reserved Windows filenames
- invalid trailing spaces
- invalid trailing periods

Examples of reserved Windows filenames include:

```text
CON
PRN
AUX
NUL
COM1
LPT1
```

---

## 21. Security Requirements

The receiver must not accept unauthenticated file uploads.

Implement:

- One-time QR pairing token
- Per-device authentication token
- HTTPS
- Certificate fingerprint pinning where practical
- SHA-256 file integrity verification
- File-size limits
- Filename sanitization
- MIME metadata validation
- Request rate limiting
- Device revocation
- Temporary `.part` files
- Safe final destination handling
- Transfer audit history
- Pairing expiration
- Explicit pairing approval
- Constant-time token comparison where practical
- Secure random token generation
- No credentials in application logs

### Authentication header

Use:

```http
Authorization: Bearer <device-token>
```

### Device revocation

When a device is revoked:

- Its authentication token becomes invalid.
- New transfers must be rejected.
- Existing active transfers may be cancelled.
- The device must pair again to regain access.

---

## 22. HTTPS and Trust Model

For the MVP, the Windows receiver may generate a local self-signed certificate.

The Android application must store the certificate fingerprint during pairing.

For later connections:

1. Discover the device.
2. Connect using HTTPS.
3. Verify that the presented certificate matches the stored fingerprint.
4. Reject the connection if the fingerprint changes unexpectedly.
5. Require re-pairing after certificate regeneration.

Do not disable certificate verification globally.

---

## 23. File-Size and Resource Limits

Configurable defaults:

```text
Maximum single file size: 5 GB
Maximum files per share action: 20
Maximum concurrent transfers: 2
Maximum pending transfer records: 100
Pairing token expiry: 5 minutes
Idle upload timeout: 2 minutes
```

The Windows receiver must check available disk space before accepting an upload.

Reserve additional space for temporary files.

---

## 24. Error Model

Use structured errors.

Example:

```json
{
  "code": "CHECKSUM_MISMATCH",
  "message": "The uploaded file failed integrity verification.",
  "transferId": "9ab89a06-4f08-4cdc-b499-fd333e58b040"
}
```

Suggested error codes:

```text
AUTHENTICATION_FAILED
DEVICE_REVOKED
PAIRING_TOKEN_INVALID
PAIRING_TOKEN_EXPIRED
PAIRING_REJECTED
DEVICE_NOT_FOUND
DEVICE_OFFLINE
TRANSFER_NOT_FOUND
TRANSFER_ALREADY_COMPLETED
FILE_TOO_LARGE
INSUFFICIENT_DISK_SPACE
INVALID_FILE_NAME
INVALID_MIME_TYPE
UPLOAD_INTERRUPTED
CHECKSUM_MISMATCH
NETWORK_TIMEOUT
SERVER_UNAVAILABLE
PROTOCOL_VERSION_UNSUPPORTED
INTERNAL_ERROR
```

---

## 25. Transfer Queue

The Android sender must maintain a local transfer queue.

Each queued transfer should contain:

```text
transferId
localSharedFileId
destinationDeviceId
status
bytesTransferred
retryCount
lastError
createdAt
updatedAt
```

Retry policy:

- Retry transient network errors.
- Use exponential backoff.
- Do not retry authentication failures.
- Do not retry checksum failures automatically.
- Stop retrying after a configurable retry limit.
- Allow manual retry.

Suggested retry delays:

```text
2 seconds
5 seconds
10 seconds
30 seconds
60 seconds
```

---

## 26. Progress Reporting

The Android app must show:

- Current file name
- Current file number
- Total file count
- Bytes transferred
- Total bytes
- Percentage
- Transfer speed
- Estimated remaining time where possible
- Cancel action

The Windows app must show:

- Sender device
- File name
- Progress
- Transfer speed
- Current status
- Reject or cancel action for active transfers

---

## 27. Notifications

### Android notifications

Use notifications for:

- Transfer started
- Transfer completed
- Transfer failed
- Destination PC offline
- Retry scheduled

### Windows notifications

Use notifications for:

- Pairing request
- Incoming transfer
- Transfer completed
- Transfer failed
- Disk space warning

A completed notification should include:

```text
report.pdf received from Brighton Phone
```

Actions may include:

- Open file
- Open folder

---

## 28. Settings

### Android settings

Include:

- Device name
- Default computer
- Confirm computer before sending
- Wi-Fi only
- Transfer history retention
- Clear history
- Manage paired computers

### Windows settings

Include:

- Computer display name
- Receive folder
- Listening port
- Start with Windows
- Minimize to tray
- Show notifications
- Maximum file size
- Maximum concurrent transfers
- Manage paired devices
- Regenerate certificate
- Clear transfer history

Certificate regeneration must warn that all devices will need to pair again.

---

## 29. UI Requirements

Use a clean, simple desktop and mobile interface.

### Android design

Prioritize the share flow.

When opened from Android's share sheet, the app should immediately show:

```text
Files selected
Destination computer
Send button
```

Avoid navigating the user through unnecessary screens.

### Windows design

Prioritize:

```text
Receiver status
Pairing
Receive folder
Recent transfers
```

The app must remain usable without requiring administrator privileges.

---

## 30. Protocol Versioning

Every pairing and device payload must include:

```text
protocolVersion
```

Start with:

```text
1
```

If the sender and receiver do not support compatible versions, return:

```text
PROTOCOL_VERSION_UNSUPPORTED
```

Do not silently continue with incompatible versions.

---

## 31. Logging

Use structured logging.

Log:

- Application startup
- Receiver startup
- Receiver shutdown
- Pairing requests
- Pairing approvals
- Pairing rejections
- Device discovery
- Transfer creation
- Transfer progress checkpoints
- Transfer completion
- Transfer failure
- Device revocation
- Configuration changes

Never log:

- Authentication tokens
- Pairing tokens
- Complete certificate private keys
- File contents
- Sensitive full filesystem paths unless required for local debugging

Use log levels:

```text
Debug
Information
Warning
Error
Critical
```

---

## 32. Testing Requirements

### Unit tests

Test:

- Filename sanitization
- Duplicate filename generation
- Pairing token expiry
- Token validation
- Checksum calculation
- Transfer-state transitions
- Retry policy
- Error mapping
- Protocol serialization
- File-size validation

### Integration tests

Test:

- Pair Android and Windows
- Upload a small file
- Upload a large streamed file
- Upload multiple files
- Reject an invalid token
- Reject a revoked device
- Reject a file above the size limit
- Handle insufficient disk space
- Handle interrupted upload
- Handle checksum mismatch
- Handle duplicate filenames
- Handle certificate fingerprint mismatch

### Manual tests

Test sharing from:

- WhatsApp
- Gmail
- Chrome
- Android Files
- Google Drive
- Microsoft Office
- A photo gallery application

Test Windows on:

- Windows 10
- Windows 11

---

## 33. Development Phases

### Phase 1: Project foundation

Implement:

- Monorepo
- Shared packages
- Flutter Android project
- Flutter Windows project
- Shared models
- Shared protocol definitions
- Local databases
- Base navigation
- Logging

### Phase 2: Windows receiver

Implement:

- Local HTTP server
- Device information endpoint
- Receive folder
- File streaming
- Temporary files
- Filename sanitization
- SHA-256 verification
- Transfer history

HTTP may be used temporarily during development only.

### Phase 3: Android share target

Implement:

- Android share intent registration
- Kotlin intent receiver
- Flutter platform channel
- Shared file list
- Manual destination selection
- Streamed upload

### Phase 4: Pairing and authentication

Implement:

- QR generation
- QR scanning
- Pairing token
- Pairing approval
- Per-device token
- Device storage
- Device revocation

### Phase 5: Local discovery

Implement:

- mDNS advertisement
- Android discovery
- Online/offline state
- Current address resolution

### Phase 6: HTTPS

Implement:

- Local certificate generation
- Certificate fingerprint in QR
- Certificate pinning
- Secure transfer

### Phase 7: Desktop integration

Implement:

- Tray mode
- Windows startup
- Windows notifications
- Open file
- Open folder

### Phase 8: Hardening

Implement:

- Rate limiting
- Concurrent transfer limits
- Disk-space validation
- Timeouts
- Retry behavior
- Security review
- Integration tests
- Packaging

---

## 34. MVP Acceptance Criteria

The MVP is complete when all of the following work:

1. The Windows app installs and runs.
2. The Windows app creates or selects a receive folder.
3. The Windows app starts a receiver server.
4. The Windows app displays a QR pairing code.
5. The Android app scans the QR code.
6. The Windows user approves the phone.
7. The phone and PC remain paired after restart.
8. The Android app appears in the Android share sheet.
9. A user can share a PDF from WhatsApp.
10. The user can select the paired PC.
11. The file transfers over the same Wi-Fi network.
12. The Android app displays transfer progress.
13. The Windows app displays incoming progress.
14. The file is first stored with a `.part` extension.
15. The SHA-256 checksum is verified.
16. The final file appears in the configured folder.
17. Duplicate filenames are renamed safely.
18. A Windows notification appears after completion.
19. An invalid or revoked device cannot upload files.
20. A failed transfer appears in transfer history with a useful error.

---

## 35. Coding Standards

Use:

- Null safety
- Immutable models
- Clear separation between UI, domain, and infrastructure
- Dependency injection
- Repository pattern for persistence
- Service abstractions for networking and platform integration
- Typed error handling
- Async streaming APIs
- Cancellation tokens or equivalent cancellation handling
- Small focused classes
- Descriptive names
- Unit-testable business logic

Avoid:

- Global mutable state
- Loading whole files into memory
- Hard-coded IP addresses
- Hard-coded Windows paths
- Hard-coded credentials
- Direct UI access to database APIs
- Direct UI access to low-level networking
- Silent exception swallowing
- Disabling TLS verification
- Trusting filenames from the sender

---

## 36. Suggested Shared Models

### DeviceInfo

```dart
@freezed
class DeviceInfo with _$DeviceInfo {
  const factory DeviceInfo({
    required String deviceId,
    required String deviceName,
    required String platform,
    required int protocolVersion,
    required String appVersion,
  }) = _DeviceInfo;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
}
```

### TransferRequest

```dart
@freezed
class TransferRequest with _$TransferRequest {
  const factory TransferRequest({
    required String fileName,
    required String mimeType,
    required int fileSize,
    required String checksumAlgorithm,
    required String checksum,
  }) = _TransferRequest;

  factory TransferRequest.fromJson(Map<String, dynamic> json) =>
      _$TransferRequestFromJson(json);
}
```

### TransferRecord

```dart
@freezed
class TransferRecord with _$TransferRecord {
  const factory TransferRecord({
    required String id,
    required String senderDeviceId,
    required String fileName,
    required String mimeType,
    required int fileSize,
    required int bytesTransferred,
    required TransferStatus status,
    String? finalPath,
    String? failureCode,
    String? failureMessage,
    required DateTime createdAt,
    DateTime? completedAt,
  }) = _TransferRecord;

  factory TransferRecord.fromJson(Map<String, dynamic> json) =>
      _$TransferRecordFromJson(json);
}
```

---

## 37. Suggested Service Interfaces

### Android

```dart
abstract interface class SharedFileService {
  Stream<List<SharedFile>> watchIncomingSharedFiles();
  Future<void> clearSharedFiles();
}

abstract interface class DeviceDiscoveryService {
  Stream<List<DiscoveredDevice>> discover();
}

abstract interface class PairingService {
  Future<PairedDevice> pairFromQr(String qrPayload);
  Future<void> revokeDevice(String deviceId);
}

abstract interface class TransferClient {
  Stream<TransferProgress> sendFiles({
    required PairedDevice destination,
    required List<SharedFile> files,
  });
}
```

### Windows

```dart
abstract interface class ReceiverServer {
  Future<void> start();
  Future<void> stop();
  Stream<IncomingTransferEvent> get events;
}

abstract interface class FileStorageService {
  Future<String> createTemporaryFile(String fileName);
  Future<String> finalizeFile({
    required String temporaryPath,
    required String requestedFileName,
  });
}

abstract interface class PairingServer {
  Future<PairingSession> createSession();
  Stream<PairingRequest> get requests;
  Future<void> approve(String requestId);
  Future<void> reject(String requestId);
}
```

---

## 38. Codex Execution Instructions

Codex should implement the project incrementally.

For every phase:

1. Create the necessary files.
2. Keep the applications buildable.
3. Add tests for completed business logic.
4. Update project documentation.
5. Avoid implementing future-phase functionality prematurely.
6. Use interfaces around platform-specific code.
7. Keep all protocol models versioned.
8. Document setup and run commands.
9. Add error handling for all I/O operations.
10. Do not use mock security in production paths.

Start with Phase 1 and Phase 2.

The first implementation checkpoint should demonstrate:

```text
Windows app starts
        ↓
Receiver server listens
        ↓
A test client streams a file
        ↓
Receiver writes a .part file
        ↓
Receiver verifies SHA-256
        ↓
Receiver moves it to final destination
```

After that checkpoint, implement the Android share target and pairing.

---

## 39. Final Product Name

Working name:

```text
Send to PC
```

Package name example:

```text
com.brightonkofu.sendtopc
```

Windows executable example:

```text
SendToPC.exe
```

Default Windows folder:

```text
C:\Users\<User>\Downloads\SendToPC
```

Default discovery service:

```text
_sendtopc._tcp.local
```

Default port:

```text
45873
```

---

## 40. Definition of Done

The system is done when a user can:

```text
Receive a file in WhatsApp
        ↓
Tap Share
        ↓
Select Send to PC
        ↓
Choose a paired Windows computer
        ↓
See transfer progress
        ↓
Find the verified file in the Windows receive folder
```

without opening WhatsApp Desktop and without uploading the file to a third-party cloud service.
