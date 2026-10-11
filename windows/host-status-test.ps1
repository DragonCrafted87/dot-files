# Fixture for the calligraphy-wyrm publisher. This does not launch
# CrystalDiskInfo and it does not publish.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "host-status.ps1")

$serialA = "WD-WCC4N1234567"
$serialB = "S6Z1NG0T123456"
$report = @"
----------------------------------------------------------------------------
 (01) WDC WD40EFRX-68N32N0
----------------------------------------------------------------------------
           Model : WDC WD40EFRX-68N32N0
        Firmware : 82.00A82
   Serial Number : $serialA
     Temperature : 32 C
   Health Status : Good (100%)
----------------------------------------------------------------------------
 (02) Samsung SSD 990 PRO 2TB
----------------------------------------------------------------------------
           Model : Samsung SSD 990 PRO 2TB
        Firmware : 1B2QJXD7
   Serial Number : $serialB
     Temperature : 41 C
   Health Status : Good
"@

$disks = ConvertFrom-DiskInfoText $report
if ($disks.Count -ne 2) { throw "expected 2 disks, got $($disks.Count)" }
if ($disks[0].model -ne "WDC WD40EFRX-68N32N0") { throw "model 0" }
if ($disks[0].health -ne "Good (100%)") { throw "health 0" }
if ($disks[0].health_percent -ne 100) { throw "percent 0" }
if ($disks[0].temperature_c -ne 32) { throw "temp 0" }
if ($disks[1].model -ne "Samsung SSD 990 PRO 2TB") { throw "model 1" }
if ($disks[1].health -ne "Good") { throw "health 1" }
if ($disks[1].Contains("health_percent")) { throw "percent 1 should be absent" }
if ($disks[1].temperature_c -ne 41) { throw "temp 1" }

$payload = ConvertTo-HostStatusJson 12.5 41.0 $null "Ethernet" 1000 2000 @(
    [ordered]@{ name = "Ethernet"; rx_bps = 1000; tx_bps = 2000 }
) $disks
if ($payload.Contains($serialA) -or $payload.Contains($serialB)) {
    throw "serial number leaked into the payload"
}
if ($payload -notmatch '"model":"WDC WD40EFRX-68N32N0"') { throw "payload model" }
if ($payload -notmatch '"health":"Good \(100%\)"') { throw "payload health" }
if ($payload -notmatch '"temperature_c":null') { throw "cpu temperature should be null" }
if ($payload -notmatch '"disks":\[') { throw "disks" }

if (-not (Test-HostStatusSkipInterface "vEthernet (Default Switch)")) { throw "default switch" }
if (-not (Test-HostStatusSkipInterface "Loopback Pseudo-Interface 1")) { throw "loopback" }
if (-not (Test-HostStatusSkipInterface "Bluetooth Network Connection")) { throw "bluetooth" }
if (-not (Test-HostStatusSkipInterface "vEthernet (WSL)")) { throw "wsl" }
if (Test-HostStatusSkipInterface "vEthernet (External Switch)") { throw "external vEthernet should stay" }
if (Test-HostStatusSkipInterface "Ethernet") { throw "ethernet should stay" }

$packet = New-MqttPublishPacket "homelab/status/calligraphy-wyrm" $payload
if ($packet[0] -ne 0x31) { throw "publish retain header" }
$text = [System.Text.Encoding]::UTF8.GetString($packet)
if ($text -notmatch "homelab/status/calligraphy-wyrm") { throw "topic" }
if ($text.Contains($serialA)) { throw "serial in packet" }

$chosen = Select-LhmTemperature @(
    [ordered]@{ name = "CPU"; value = 30 }
    [ordered]@{ name = "Core (Tctl/Tdie)"; value = 31.5 }
    [ordered]@{ name = "CPU Package"; value = 40 }
)
if ($chosen -ne 40) { throw "package rank" }
$chosen = Select-LhmTemperature @(
    [ordered]@{ name = "CPU"; value = 30 }
    [ordered]@{ name = "Core (Tctl/Tdie)"; value = 31.5 }
)
if ($chosen -ne 31.5) { throw "tctl rank" }

$savedHost = $env:HOST_STATUS_HOST
$savedComputer = $env:COMPUTERNAME
$env:HOST_STATUS_HOST = ""
$env:COMPUTERNAME = "CALLIGRAPHY-WYR"
if ((Get-HostStatusName) -ne "calligraphy-wyrm") { throw "netbios name" }
$env:COMPUTERNAME = "ROOST-DRAKE"
if ((Get-HostStatusName) -ne "roost-drake") { throw "short name" }
$env:HOST_STATUS_HOST = "override"
if ((Get-HostStatusName) -ne "override") { throw "override" }
$env:HOST_STATUS_HOST = $savedHost
$env:COMPUTERNAME = $savedComputer

Write-Output "netbios topic"
Write-Output "disk model"
Write-Output "disk health"
Write-Output "disk temperature"
Write-Output "no serial"
Write-Output "external vEthernet kept"
