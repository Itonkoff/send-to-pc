param(
  [Parameter(Mandatory = $true)]
  [string]$DeviceId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location apps/mobile
flutter run -d $DeviceId
Pop-Location