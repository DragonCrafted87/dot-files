# Idempotent winget installer. Package IDs live in windows/packages/*.list
# the same way Linux roles declare packages in setup/roles.conf.
#
# The chosen role is written to %USERPROFILE%\.config\dot-files\windows-role
# so later bare winget-install-packages / winget-upgrade-packages use it.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 work
#   powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 personal
#   powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 -Upgrade

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("work", "personal")]
    [string]$Role,

    [switch]$Upgrade
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDir = Join-Path $Here "packages"
$RoleFile = Join-Path $HOME ".config\dot-files\windows-role"

function Read-SavedRole {
    if (-not (Test-Path $RoleFile)) {
        return $null
    }
    $saved = (Get-Content $RoleFile -TotalCount 1).Trim()
    if ($saved -in @("work", "personal")) {
        return $saved
    }
    return $null
}

function Save-Role([string]$Value) {
    $dir = Split-Path $RoleFile -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $RoleFile -Value $Value -Encoding ascii
    Write-Host "==> saved windows role $Value -> $RoleFile"
}

function Read-PackageList([string]$Name) {
    $path = Join-Path $PackageDir $Name
    if (-not (Test-Path $path)) {
        throw "missing package list $path"
    }
    Get-Content $path | ForEach-Object {
        $line = ($_ -replace '#.*$', '').Trim()
        if ($line) { $line }
    }
}

function Test-WingetPackage([string]$Id) {
    $out = & winget list --id $Id -e --accept-source-agreements 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    return ($out -join "`n") -match [regex]::Escape($Id)
}

function Ensure-WingetPackage([string]$Id) {
    $installed = Test-WingetPackage $Id
    if ($installed -and -not $Upgrade) {
        Write-Host "==> already installed $Id"
        return
    }
    if ($installed -and $Upgrade) {
        Write-Host "==> winget upgrade $Id"
        & winget upgrade --id $Id -e --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    no upgrade available or upgrade skipped for $Id"
        }
        return
    }
    Write-Host "==> winget install $Id"
    & winget install --id $Id -e --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for $Id (exit $LASTEXITCODE)"
    }
}

if (-not $Role) {
    $Role = Read-SavedRole
}
if (-not $Role) {
    throw "no windows role given and none saved at $RoleFile (pass work or personal once)"
}
Save-Role $Role

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is required. Install App Installer from the Microsoft Store first."
}

$ids = New-Object System.Collections.Generic.List[string]
foreach ($id in (Read-PackageList "common.list")) {
    if (-not $ids.Contains($id)) { $ids.Add($id) }
}
foreach ($id in (Read-PackageList "$Role.list")) {
    if (-not $ids.Contains($id)) { $ids.Add($id) }
}

Write-Host "==> windows role $Role ($($ids.Count) packages)"
foreach ($id in $ids) {
    Ensure-WingetPackage $id
}
