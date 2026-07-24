# Architecture

Send to PC is a local-first sender/receiver pair.

## Current Checkpoint

The Windows app owns the receive path. It starts a local HTTPS server on the configured port, exposes `/api/v1/device`, accepts authenticated transfer creation, streams content into a `.part` file, verifies SHA-256, renames the file into the configured receive folder, and persists transfer history under the app data folder.

The Android app is registered as a generic Android share target and forwards shared file metadata from Kotlin into Flutter through a method channel named `send_to_pc/share`. The same bridge stores paired receiver credentials, performs QR/payload pairing, uploads shared content streams, and can refresh a paired computer address by probing local candidates and trusting only a matching receiver `deviceId` from `/api/v1/device`.

## Current Layers

- Pairing: QR payload, approval prompt, stored per-device credentials, and per-device token revocation.
- Discovery: trusted-ID local probe refresh for paired computers and pairing fallback hosts.
- Security: local HTTPS is enabled for the Windows app. The QR payload carries the generated receiver certificate fingerprint, and Android uses a pinned HTTPS connection for pairing, discovery, and uploads.
- Settings: editable receive folder, listening port, startup preference, notifications, and maximum file size.
- Desktop integration: tray mode, open receive folder/open received file, startup registration, and Windows notifications.

## Remaining Layers

- Discovery: mDNS/DNS-SD advertisement as `_sendtopc._tcp.local` instead of local subnet probing.
- Hardening: upload idle timeouts and release packaging/signing.
