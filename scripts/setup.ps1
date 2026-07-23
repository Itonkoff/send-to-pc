Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location apps/windows
flutter pub get
Pop-Location

Push-Location apps/mobile
flutter pub get
Pop-Location