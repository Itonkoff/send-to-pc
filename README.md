# Send to PC

Local-first Android to Windows file transfer over the local network.

This checkpoint contains:

- Flutter Android app shell registered as the Android share target `Send to PC`.
- Kotlin share-intent bridge for `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
- Native Android streamed upload bridge for shared content URIs.
- Flutter Windows app shell with a local receiver dashboard.
- Authenticated local HTTP API under `/api/v1`.
- Streamed upload to `.part` files, SHA-256 verification, and safe final filenames.
- Editable Windows receive folder, listening port, and maximum file size settings.
- Short-lived pairing sessions with explicit Windows approval.
- Persisted trusted-device records for approved pairing requests.
- Windows pairing QR rendering plus copyable pairing payload JSON.
- Android in-app pairing from QR scan or pasted Windows pairing payload.
- Android trusted-ID local host discovery for saved paired computers.
- Windows transfer history persisted across receiver restarts with clear/open actions.
- Windows tray mode, notification balloons, and per-user Start with Windows integration.
- Android recent-transfer history persisted from completed receiver responses and failed send attempts.
- Shared Dart packages for models, protocol errors, security, and storage helpers.

The current implementation covers Phase 1, Phase 2, Android share-target registration and streamed upload from Phase 3, QR-based Android pairing plus trusted-device revocation from Phase 4, a practical trusted-ID discovery refresh from Phase 5, and Windows receiver tray/startup/notification pieces from Phase 7. mDNS advertisement, HTTPS, and richer native notification actions remain next phases.

## Project Layout

```text
apps/mobile      Flutter Android sender
apps/windows     Flutter Windows receiver
packages/*       Shared Dart packages
scripts          Local development helpers
docs             Architecture and protocol notes
```

## Setup

Run after code changes that modify `pubspec.yaml`:

```powershell
cd "C:\Users\user\AndroidStudioProjects\Send to pc"
dart pub get

cd apps/windows
flutter pub get

cd ../mobile
flutter pub get
```

## Run

Windows receiver:

```powershell
cd apps/windows
flutter run -d windows
```

Android sender:

```powershell
cd apps/mobile
flutter run -d <android-device-id>
```

## Receiver Checkpoint Test

1. Start the Windows app.
2. Copy the test client token shown on the dashboard.
3. In a separate terminal, run:

```powershell
cd "C:\Users\user\AndroidStudioProjects\Send to pc"
dart scripts/test_upload.dart C:\path\to\file.pdf --token <token>
```

The receiver writes `<name>.part`, verifies SHA-256 after upload completion, and moves the file into `Downloads\SendToPC`.

## Pairing Checkpoint Test

Script-level API check:

1. Start the Windows app.
2. Click `New` in the Pairing card.
3. Copy the `pairingToken` value from the displayed payload.
4. In a separate terminal, run:

```powershell
cd "C:\Users\user\AndroidStudioProjects\Send to pc"
dart scripts/test_pairing_request.dart --token <pairingToken>
```

5. Approve the pending request in the Windows app.
6. The script prints a persisted `deviceToken` for the simulated Android phone.

Android app check:

1. Start the Windows app.
2. Click `New` in the Pairing card.
3. In the Android app, tap `Pair new computer`.
4. Scan the Windows QR code, or paste the full pairing payload JSON shown by Windows.
5. Use `10.0.2.2` in `Host override` when pairing from the Android emulator. For a physical phone, leave it empty first; the QR payload includes alternate PC addresses and Android will try those before scanning the phone network. If discovery is blocked, enter the PC Wi-Fi IPv4 address instead.
6. Approve the pending request in the Windows app.
7. The receiver appears under `Paired computers` in Android.

## Windows Firewall Access

If Android cannot reach the receiver but the Windows app shows `Listening`, check the phone browser first:

```text
http://<pc-wifi-ip>:45873/api/v1/device
```

If that does not load, Windows Firewall is probably blocking inbound access. Run PowerShell as Administrator, then run:

```powershell
cd "C:\Users\user\AndroidStudioProjects\Send to pc"
.\scripts\allow_windows_firewall.ps1
```

The script removes stale Flutter block prompts for the debug executable and adds a local-subnet TCP allow rule for port `45873`.
## Android Share Upload Checkpoint Test

1. Start the Windows app and keep the receiver running.
2. Pair once using the Android app check above.
3. Share a file from Android and choose `Send to PC`.
4. Select the saved computer, then tap `Send`.

Use the paired-computers discovery button to refresh the saved receiver address. Use the Windows LAN IP shown by the receiver when testing from a physical phone on the same Wi-Fi. If Windows shows `192.168.137.1` but the phone is on a `192.168.1.x` network, pair again with the PC Wi-Fi IPv4 address in `Host override`. Use `10.0.2.2` as the host when testing from the Android emulator against the Windows app on the same development machine.