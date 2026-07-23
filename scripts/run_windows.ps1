Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location apps/windows
flutter run -d windows
Pop-Location