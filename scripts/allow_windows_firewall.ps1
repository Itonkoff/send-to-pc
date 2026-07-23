# Run from an elevated PowerShell prompt.
# Allows Android devices on the local network to reach the Windows receiver.

param(
    [string]$AppPath = "C:\Users\user\AndroidStudioProjects\Send to pc\apps\windows\build\windows\x64\runner\Debug\send_to_pc_windows.exe",
    [int]$Port = 45873
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this script in PowerShell as Administrator."
    exit 1
}

if (-not (Test-Path -LiteralPath $AppPath)) {
    Write-Error "Windows app executable not found: $AppPath"
    exit 1
}

$ruleName = "Send to PC Receiver TCP $Port"
$legacyRuleName = "send_to_pc_windows.exe"

Write-Host "Removing old Flutter/Windows prompts for $AppPath ..."
netsh advfirewall firewall delete rule name="$legacyRuleName" program="$AppPath" | Out-Host
netsh advfirewall firewall delete rule name="$ruleName" | Out-Host

Write-Host "Adding local-subnet allow rule for TCP $Port ..."
netsh advfirewall firewall add rule `
    name="$ruleName" `
    dir=in `
    action=allow `
    protocol=TCP `
    localport=$Port `
    remoteip=localsubnet `
    profile=any `
    program="$AppPath" `
    enable=yes | Out-Host

Write-Host "Done. From the phone, test: http://192.168.1.184:$Port/api/v1/device"