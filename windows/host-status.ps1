# Publish one retained host status payload for calligraphy-wyrm.
# Windows 10 has no hostname(1) publisher. This script sends MQTT 3.1.1
# itself. Mosquitto is not installed here, because that package starts
# a broker.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\host-status.ps1 -Register
#   powershell -ExecutionPolicy Bypass -File .\windows\host-status.ps1 -Once

[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$Register
)

$ErrorActionPreference = "Stop"

function Test-HostStatusSkipInterface([string]$Name) {
    if ($Name -match "Loopback") { return $true }
    if ($Name -match "Bluetooth") { return $true }
    if ($Name -match "WSL") { return $true }
    if ($Name -eq "vEthernet (Default Switch)") { return $true }
    return $false
}

function ConvertFrom-DiskInfoText([string]$Text) {
    $disks = @()
    $current = $null
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match "^\s*Model\s*:\s*(.+?)\s*$") {
            if ($null -ne $current) {
                $disks += $current
            }
            $current = [ordered]@{
                model         = $Matches[1]
                health        = $null
                temperature_c = $null
            }
        }
        elseif ($null -ne $current -and $line -match "^\s*Health Status\s*:\s*(.+?)\s*$") {
            $health = $Matches[1]
            $current.health = $health
            if ($health -match "\((\d+)%\)") {
                $current.health_percent = [int]$Matches[1]
            }
        }
        elseif ($null -ne $current -and $line -match "^\s*Temperature\s*:\s*(-?\d+)") {
            $current.temperature_c = [int]$Matches[1]
        }
    }
    if ($null -ne $current) {
        $disks += $current
    }
    return ,$disks
}

function ConvertTo-JsonString([string]$Value) {
    if ($null -eq $Value) {
        return "null"
    }
    $escaped = $Value.Replace("\", "\\").Replace('"', '\"')
    return '"' + $escaped + '"'
}

function ConvertTo-JsonNumber($Value, [switch]$Decimal) {
    if ($null -eq $Value) {
        return "null"
    }
    if ($Decimal) {
        return ("{0:0.0}" -f [double]$Value)
    }
    return ([int]$Value).ToString()
}

function ConvertTo-HostStatusJson($Cpu, $Memory, $Temperature, $Primary, $Rx, $Tx, $Net, $Disks) {
    $netJson = @()
    foreach ($row in @($Net)) {
        if ($null -eq $row) { continue }
        $netJson += ("{0}:{1},{2}:{3},{4}:{5}" -f `
            (ConvertTo-JsonString "name"), (ConvertTo-JsonString $row.name), `
            (ConvertTo-JsonString "rx_bps"), (ConvertTo-JsonNumber $row.rx_bps), `
            (ConvertTo-JsonString "tx_bps"), (ConvertTo-JsonNumber $row.tx_bps))
    }
    $netBody = ""
    if ($netJson.Count -gt 0) {
        $netBody = "{" + ($netJson -join "},{") + "}"
    }
    $diskJson = @()
    foreach ($disk in @($Disks)) {
        if ($null -eq $disk) { continue }
        $fields = @(
            ("{0}:{1}" -f (ConvertTo-JsonString "model"), (ConvertTo-JsonString $disk.model)),
            ("{0}:{1}" -f (ConvertTo-JsonString "health"), (ConvertTo-JsonString $disk.health)),
            ("{0}:{1}" -f (ConvertTo-JsonString "temperature_c"), (ConvertTo-JsonNumber $disk.temperature_c))
        )
        if ($disk.Contains("health_percent")) {
            $fields += ("{0}:{1}" -f (ConvertTo-JsonString "health_percent"), (ConvertTo-JsonNumber $disk.health_percent))
        }
        $diskJson += ($fields -join ",")
    }
    $diskBody = ""
    if ($diskJson.Count -gt 0) {
        $diskBody = "{" + ($diskJson -join "},{") + "}"
    }
    return ("{0}{1}:{2},{3}:{4},{5}:{6},{7}:{8},{9}:{10},{11}:{12},{13}:[{14}],{15}:[{16}]{17}" -f `
        "{", `
        (ConvertTo-JsonString "cpu_percent"), (ConvertTo-JsonNumber $Cpu -Decimal), `
        (ConvertTo-JsonString "memory_percent"), (ConvertTo-JsonNumber $Memory -Decimal), `
        (ConvertTo-JsonString "temperature_c"), (ConvertTo-JsonNumber $Temperature -Decimal), `
        (ConvertTo-JsonString "primary"), (ConvertTo-JsonString $Primary), `
        (ConvertTo-JsonString "rx_bps"), (ConvertTo-JsonNumber $Rx), `
        (ConvertTo-JsonString "tx_bps"), (ConvertTo-JsonNumber $Tx), `
        (ConvertTo-JsonString "net"), $netBody, `
        (ConvertTo-JsonString "disks"), $diskBody, `
        "}")
}

function Select-LhmTemperature($Sensors) {
    $rank = @{
        "CPU Package"       = 0
        "Core (Tctl/Tdie)"  = 1
        "CPU (Tctl/Tdie)"   = 2
    }
    $best = $null
    $bestRank = 99
    foreach ($sensor in $Sensors) {
        if (-not $rank.ContainsKey([string]$sensor.name)) { continue }
        if ($null -eq $sensor.value) { continue }
        $place = $rank[[string]$sensor.name]
        if ($place -lt $bestRank) {
            $best = [double]$sensor.value
            $bestRank = $place
        }
    }
    return $best
}

function Get-LhmTemperature($Node) {
    $sensors = @()
    $pending = @($Node)
    while ($pending.Count -gt 0) {
        $item = $pending[0]
        if ($pending.Count -eq 1) {
            $pending = @()
        }
        else {
            $pending = $pending[1..($pending.Count - 1)]
        }
        if ($null -eq $item) { continue }
        $text = [string]$item.Text
        $value = [string]$item.Value
        $type = [string]$item.Type
        if (($type -eq "" -or $type -eq "Temperature") -and $value -match "(-?\d+(?:\.\d+)?)") {
            $sensors += [ordered]@{ name = $text; value = [double]$Matches[1] }
        }
        if ($item.Children) {
            $pending += @($item.Children)
        }
    }
    return Select-LhmTemperature $sensors
}

function Get-LhmLibraryTemperature {
    if (-not $script:LhmComputer) {
        $dll = Get-ChildItem -Path @(
            "C:\Program Files\LibreHardwareMonitor\LibreHardwareMonitorLib.dll"
            "C:\Users\*\AppData\Local\Microsoft\WinGet\Packages\LibreHardwareMonitor.LibreHardwareMonitor_*\LibreHardwareMonitorLib.dll"
        ) -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $dll) { return $null }
        [void][Reflection.Assembly]::LoadFrom($dll.FullName)
        $computer = New-Object LibreHardwareMonitor.Hardware.Computer
        $computer.IsCpuEnabled = $true
        $computer.Open()
        $script:LhmComputer = $computer
    }
    $sensors = @()
    foreach ($hardware in $script:LhmComputer.Hardware) {
        $hardware.Update()
        foreach ($sensor in $hardware.Sensors) {
            if ([string]$sensor.SensorType -ne "Temperature") { continue }
            if ($null -eq $sensor.Value) { continue }
            $sensors += [ordered]@{ name = [string]$sensor.Name; value = [double]$sensor.Value }
        }
    }
    return Select-LhmTemperature $sensors
}

function Get-LhmSensorNames($Node) {
    $names = @()
    $pending = @($Node)
    while ($pending.Count -gt 0) {
        $item = $pending[0]
        if ($pending.Count -eq 1) {
            $pending = @()
        }
        else {
            $pending = $pending[1..($pending.Count - 1)]
        }
        if ($null -eq $item) { continue }
        if ($item.Text) {
            $names += [string]$item.Text
        }
        if ($item.Children) {
            $pending += @($item.Children)
        }
    }
    return $names
}

function ConvertTo-MqttRemaining([int]$Length) {
    $bytes = New-Object System.Collections.Generic.List[byte]
    do {
        $encoded = $Length % 128
        $Length = [math]::Floor($Length / 128)
        if ($Length -gt 0) {
            $encoded = $encoded -bor 128
        }
        $bytes.Add([byte]$encoded)
    } while ($Length -gt 0)
    Write-Output -NoEnumerate $bytes.ToArray()
}

function New-MqttPublishPacket([string]$Topic, [string]$Payload) {
    $topicBytes = [System.Text.Encoding]::UTF8.GetBytes($Topic)
    $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $body = New-Object System.Collections.Generic.List[byte]
    $body.Add([byte](($topicBytes.Length -shr 8) -band 255))
    $body.Add([byte]($topicBytes.Length -band 255))
    $body.AddRange($topicBytes)
    $body.AddRange($payloadBytes)
    $packet = New-Object System.Collections.Generic.List[byte]
    $packet.Add([byte]0x31)
    $packet.AddRange([byte[]](ConvertTo-MqttRemaining $body.Count))
    $packet.AddRange($body)
    Write-Output -NoEnumerate $packet.ToArray()
}

function Send-HostStatusMqtt([string]$Broker, [string]$Topic, [string]$Payload) {
    $clientId = "host-status-" + $env:COMPUTERNAME
    $idBytes = [System.Text.Encoding]::UTF8.GetBytes($clientId)
    $variable = New-Object System.Collections.Generic.List[byte]
    $proto = [System.Text.Encoding]::UTF8.GetBytes("MQTT")
    $variable.Add(0)
    $variable.Add(4)
    $variable.AddRange($proto)
    $variable.Add(4)
    $variable.Add(2)
    $variable.Add(0)
    $variable.Add(30)
    $variable.Add([byte](($idBytes.Length -shr 8) -band 255))
    $variable.Add([byte]($idBytes.Length -band 255))
    $variable.AddRange($idBytes)
    $connect = New-Object System.Collections.Generic.List[byte]
    $connect.Add(0x10)
    $connect.AddRange([byte[]](ConvertTo-MqttRemaining $variable.Count))
    $connect.AddRange($variable)
    $publish = New-MqttPublishPacket $Topic $Payload
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($Broker, 1883)
    $stream = $tcp.GetStream()
    $stream.Write($connect.ToArray(), 0, $connect.Count)
    $ack = New-Object byte[] 4
    [void]$stream.Read($ack, 0, 4)
    $stream.Write($publish, 0, $publish.Length)
    $stream.Flush()
    $tcp.Close()
}

function Get-HostStatusName {
    if ($env:HOST_STATUS_HOST) {
        return $env:HOST_STATUS_HOST
    }
    # COMPUTERNAME is the NetBIOS name and stops at 15 characters, so
    # this host reports calligraphy-wyr. The dashboard topic is the
    # DNS name.
    $name = $env:COMPUTERNAME
    if (-not $name) {
        return "calligraphy-wyrm"
    }
    $name = $name.ToLower()
    if ($name -eq "calligraphy-wyr") {
        return "calligraphy-wyrm"
    }
    return $name
}

function Get-DiskInfoText {
    if ($env:HOST_STATUS_DISKINFO) {
        return [System.IO.File]::ReadAllText($env:HOST_STATUS_DISKINFO)
    }
    $exe = "C:\Program Files\CrystalDiskInfo\DiskInfo64.exe"
    $report = "C:\Program Files\CrystalDiskInfo\DiskInfo.txt"
    & $exe /CopyExit | Out-Null
    return [System.IO.File]::ReadAllText($report)
}

function Get-HostStatusSample {
    $cpu = (Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue
    $availableMb = (Get-Counter "\Memory\Available MBytes").CounterSamples[0].CookedValue
    $total = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $memory = (($total - ($availableMb * 1MB)) / $total) * 100
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, InterfaceMetric |
        Select-Object -First 1
    $primary = ""
    $rx = 0
    $tx = 0
    $net = @()
    if ($route) {
        $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapter) {
            $primary = $adapter.Name
        }
    }
    $received = Get-Counter "\Network Interface(*)\Bytes Received/sec"
    $sent = Get-Counter "\Network Interface(*)\Bytes Sent/sec"
    $sentBy = @{}
    foreach ($sample in $sent.CounterSamples) {
        $sentBy[$sample.InstanceName] = [int]$sample.CookedValue
    }
    foreach ($sample in $received.CounterSamples) {
        $name = $sample.InstanceName
        if (Test-HostStatusSkipInterface $name) { continue }
        $rowRx = [int]$sample.CookedValue
        $rowTx = 0
        if ($sentBy.ContainsKey($name)) { $rowTx = $sentBy[$name] }
        $net += [ordered]@{ name = $name; rx_bps = $rowRx; tx_bps = $rowTx }
        if ($name -eq $primary) {
            $rx = $rowRx
            $tx = $rowTx
        }
    }
    $temperature = $null
    try {
        $lhm = Invoke-RestMethod -Uri "http://127.0.0.1:8085/data.json" -TimeoutSec 3
        $temperature = Get-LhmTemperature $lhm
    }
    catch {
        $temperature = $null
    }
    if ($null -eq $temperature) {
        try {
            $temperature = Get-LhmLibraryTemperature
        }
        catch {
            $temperature = $null
        }
    }
    $disks = ConvertFrom-DiskInfoText (Get-DiskInfoText)
    $hostName = Get-HostStatusName
    $payload = ConvertTo-HostStatusJson $cpu $memory $temperature $primary $rx $tx $net $disks
    return [ordered]@{ host = $hostName; payload = $payload; temperature = $temperature }
}

function Register-HostStatusTask {
    $script = $MyInvocation.ScriptName
    if (-not $script) {
        $script = $PSCommandPath
    }
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName "HomelabHostStatus" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

if ($MyInvocation.InvocationName -ne ".") {
    if ($Register) {
        Register-HostStatusTask
    }
    else {
        $broker = $env:HOST_STATUS_BROKER
        if (-not $broker) {
            $broker = "192.168.8.21"
        }
        $interval = 30
        if ($env:HOST_STATUS_INTERVAL) {
            $interval = [int]$env:HOST_STATUS_INTERVAL
        }

        do {
            $sample = Get-HostStatusSample
            $topic = "homelab/status/" + $sample.host
            if ($env:HOST_STATUS_BROKER -eq "") {
                Write-Output $sample.payload
            }
            else {
                Send-HostStatusMqtt $broker $topic $sample.payload
            }
            if ($Once) { break }
            Start-Sleep -Seconds $interval
        } while ($true)
    }
}
