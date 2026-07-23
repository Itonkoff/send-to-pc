# Architecture

Send to PC is a local-first sender/receiver pair.

## Current Checkpoint

The Windows app owns the receive path. It starts a local HTTP server on the configured port, exposes `/api/v1/device`, accepts authenticated transfer creation, streams content into a `.part` file, verifies SHA-256, renames the file into the configured receive folder, and persists transfer history under the app data folder.

The Android app is registered as a generic Android share target and forwards shared file metadata from Kotlin into Flutter through a method channel named `send_to_pc/share`. The same bridge stores paired receiver credentials, performs QR/payload pairing, uploads shared content streams, and can refresh a paired computer address by probing local candidates and trusting only a matching receiver `deviceId` from `/api/v1/device`.

## Planned Layers

- Pairing: QR payload, approval prompt, and stored per-device credentials.
- Discovery: mDNS advertisement as `_sendtopc._tcp.local` on top of the current trusted-ID local probe refresh.
- Security: HTTPS with certificate fingerprint pinning after pairing.
- Settings: editable receive folder, listening port, and maximum file size.
- Desktop integration: tray mode plus open receive folder/open received file now; startup registration and Windows notifications next.