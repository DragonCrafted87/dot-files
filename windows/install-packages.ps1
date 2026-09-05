# Idempotent winget installer. Package IDs live in windows/packages/*.list
# the same way Linux roles declare packages in setup/roles.conf.
#
#   powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 work
#   powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 personal
#   powershell -ExecutionPolicy Bypass -File .\windows\install-packages.ps1 work -Upgrade

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("work", "personal")]
    [string]$Role,

    [switch]$Upgrade
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDir = Join-Path $Here "packages"

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
