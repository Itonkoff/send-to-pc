# Development

Codex should not run Flutter commands in this workspace because they can hang in this environment. Run Flutter commands manually and paste errors back into the task.

## Install Dependencies

```powershell
cd apps/windows
flutter pub get

cd ../mobile
flutter pub get
```

## Run Windows Receiver

```powershell
cd apps/windows
flutter run -d windows
```

## Run Android Sender

```powershell
cd apps/mobile
flutter devices
flutter run -d <android-device-id>
```

## Test Upload Client

With the Windows receiver running, copy the dashboard token and run:

```powershell
dart scripts/test_upload.dart C:\path\to\file.pdf --token <token>
```

The receive folder defaults to `%USERPROFILE%\Downloads\SendToPC`.