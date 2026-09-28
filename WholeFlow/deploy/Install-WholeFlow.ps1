<#
.SYNOPSIS
    Installs (or upgrades, or removes) WholeFlow on a client PC as the Windows
    service "WholeFlow", so it starts at every boot and runs hidden in the
    background with no console window.

.DESCRIPTION
    Put this script, Install-WholeFlow.cmd and wholeflow.exe (optionally a .env)
    in one folder on the client PC and double-click Install-WholeFlow.cmd.
    The script asks for Administrator rights (UAC), then:

      1. copies wholeflow.exe (and .env if present) to C:\Program Files\WholeFlow
      2. registers and starts the Windows service (delayed automatic start,
         restart on failure) — or updates it in place if it already exists
      3. opens http://127.0.0.1:8080 so you can create the admin account and
         configure Cloud Sync (see docs/SYNC_SETUP.md)

    Run again with a newer wholeflow.exe to upgrade. -Uninstall removes the
    service and the program folder; data in C:\ProgramData\WholeFlow is kept
    unless -PurgeData is given.

.PARAMETER InstallDir
    Where the executable is installed. Default: C:\Program Files\WholeFlow

.PARAMETER Uninstall
    Remove the service and the program folder.

.PARAMETER PurgeData
    With -Uninstall: also delete C:\ProgramData\WholeFlow (config, state, logs).

.PARAMETER NoBrowser
    Do not open the web app after installing.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'WholeFlow'),
    [switch]$Uninstall,
    [switch]$PurgeData,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- self-elevate -------------------------------------------------------------
if (-not (Test-Admin)) {
    Write-Host 'Administrator rights are needed to install the Windows service; asking for them (UAC)...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value) { $argList += "-$($kv.Key)" } }
        else { $argList += "-$($kv.Key)"; $argList += ('"{0}"' -f $kv.Value) }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait
    } catch {
        Write-Host 'Elevation was refused. Without Administrator rights use instead:' -ForegroundColor Yellow
        Write-Host '    wholeflow.exe autostart' -ForegroundColor Yellow
        Write-Host '(starts WholeFlow hidden at every logon of this Windows user; see README.md)'
        exit 1
    }
    exit 0
}

$exeName = 'wholeflow.exe'
$target = Join-Path $InstallDir $exeName
$dataDir = Join-Path $env:ProgramData 'WholeFlow'

function Invoke-WholeFlow {
    param([string[]]$CommandArgs)
    # Show the exe's output; return only its exit code.
    & $target @CommandArgs | Out-Host
    return $LASTEXITCODE
}

try {
    # ---- uninstall ------------------------------------------------------------
    if ($Uninstall) {
        if (Test-Path $target) {
            Write-Host "Removing the Windows service..."
            $null = Invoke-WholeFlow @('uninstall')
            Write-Host "Removing $InstallDir"
            Remove-Item -Recurse -Force $InstallDir
        } else {
            Write-Host "Nothing installed at $InstallDir"
        }
        if ($PurgeData -and (Test-Path $dataDir)) {
            Write-Host "Deleting $dataDir (config, state, logs)"
            Remove-Item -Recurse -Force $dataDir
        } else {
            Write-Host "Data in $dataDir kept (add -PurgeData to delete it)."
        }
        Write-Host 'Done. Cloud data is untouched.' -ForegroundColor Green
        exit 0
    }

    # ---- install / upgrade ----------------------------------------------------
    $source = Join-Path $PSScriptRoot $exeName
    if (-not (Test-Path $source)) {
        throw "$exeName not found next to this script ($PSScriptRoot). Copy it here first."
    }

    New-Item -ItemType Directory -Force $InstallDir | Out-Null

    $newVersion = (& $source version) -replace '^wholeflow\s+(\S+).*$', '$1'
    $isUpgrade = Test-Path $target
    if ($isUpgrade) {
        $oldVersion = (& $target version) -replace '^wholeflow\s+(\S+).*$', '$1'
        Write-Host "Upgrading WholeFlow $oldVersion -> $newVersion"
        Write-Host 'Stopping the running WholeFlow...'
        $null = Invoke-WholeFlow @('stop')   # "not running" is fine
    } else {
        Write-Host "Installing WholeFlow $newVersion"
    }

    # Windows keeps the exe locked for a moment after the process exits: retry.
    Write-Host "Copying $exeName to $InstallDir"
    $copied = $false
    for ($i = 1; $i -le 30 -and -not $copied; $i++) {
        try { Copy-Item -Force $source $target -ErrorAction Stop; $copied = $true }
        catch { Start-Sleep -Seconds 1 }
    }
    if (-not $copied) {
        throw "Could not replace $target (still in use). Close any WholeFlow window, run 'wholeflow.exe stop' as Administrator, then run this installer again."
    }
    $envFile = Join-Path $PSScriptRoot '.env'
    if (Test-Path $envFile) {
        Write-Host 'Copying .env'
        Copy-Item -Force $envFile (Join-Path $InstallDir '.env')
    }

    Write-Host 'Registering and starting the Windows service "WholeFlow"...'
    $code = Invoke-WholeFlow @('install')
    if ($code -ne 0) { throw "wholeflow.exe install failed (exit $code). See $dataDir\logs\app.log and startup-error.txt." }

    Write-Host ''
    if ($isUpgrade) {
        Write-Host "WholeFlow upgraded to $newVersion and running again. Settings, admin login and sync state are unchanged." -ForegroundColor Green
    } else {
        Write-Host "WholeFlow $newVersion is installed and running in the background. It starts automatically at every boot." -ForegroundColor Green
    }
    Write-Host "  Program:  $target"
    Write-Host "  Data:     $dataDir"
    Write-Host '  Web app:  http://127.0.0.1:8080   (admin login; Cloud Sync setup at /#/sync)'
    Write-Host ''
    Start-Sleep -Seconds 2
    $null = Invoke-WholeFlow @('status')
    Write-Host ''
    if (-not $isUpgrade) {
        Write-Host 'Next: create the admin account in the browser (first run), then configure Cloud Sync.'
    }
    Write-Host 'Manage later from an Administrator console:  wholeflow.exe status | stop | start | restart | uninstall'

    if ($isUpgrade) { $NoBrowser = $true }   # nothing to set up after an upgrade
    if (-not $NoBrowser) {
        Start-Sleep -Seconds 1
        Start-Process 'http://127.0.0.1:8080'
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($Host.Name -eq 'ConsoleHost' -and -not $env:WHOLEFLOW_NO_PAUSE) {
        Write-Host ''
        Write-Host 'Press Enter to close this window.'
        [void](Read-Host)
    }
}
