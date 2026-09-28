<#
.SYNOPSIS
    Builds a WholeFlow release package for client PCs: runs the tests, builds
    wholeflow.exe and zips it with the installer.

.DESCRIPTION
    Run from anywhere on the development PC:

        powershell -ExecutionPolicy Bypass -File deploy\Build-Release.ps1

    Result (version taken from the exe, i.e. syncer.Version):

        dist\WholeFlow-<version>\          wholeflow.exe, Install-WholeFlow.cmd/.ps1,
                                            README.txt, .env.example, migrations\
        dist\WholeFlow-<version>.zip        the same folder, zipped: copy this to the client

    The exe is built straight into dist\, so a WholeFlow service running from
    bin\wholeflow.exe on this PC does not block the build.

.PARAMETER SkipTests
    Build without running go vet / go test (not recommended).
#>
[CmdletBinding()]
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot          # the WholeFlow folder
Set-Location $root

# Windows Application Control on the dev PC blocks test binaries in %TEMP%.
$env:GOTMPDIR = Join-Path $root 'bin\gotmp'
New-Item -ItemType Directory -Force $env:GOTMPDIR | Out-Null

try {
    if (-not $SkipTests) {
        Write-Host 'go vet ./...'
        go vet ./...
        if ($LASTEXITCODE -ne 0) { throw 'go vet failed' }
        Write-Host 'go test ./...'
        go test ./...
        if ($LASTEXITCODE -ne 0) { throw 'tests failed; nothing was packaged' }
    }

    $staging = Join-Path $root 'dist\staging'
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $staging | Out-Null
    $exe = Join-Path $staging 'wholeflow.exe'
    Write-Host 'go build'
    go build -trimpath -o $exe ./cmd/server
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }

    $version = ((& $exe version) -split '\s+')[1]
    if (-not $version) { throw 'could not read the version from the built exe' }

    $name = "WholeFlow-$version"
    $out = Join-Path $root "dist\$name"
    $zip = Join-Path $root "dist\$name.zip"
    Remove-Item -Recurse -Force $out, $zip -ErrorAction SilentlyContinue
    Rename-Item $staging $name

    Copy-Item (Join-Path $root 'deploy\Install-WholeFlow.cmd'), (Join-Path $root 'deploy\Install-WholeFlow.ps1') $out
    Copy-Item (Join-Path $root 'deploy\README.md') (Join-Path $out 'README.txt')
    Copy-Item (Join-Path $root '.env.example') $out
    Copy-Item -Recurse (Join-Path $root 'supabase\migrations') (Join-Path $out 'migrations')

    Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip
    $hash = (Get-FileHash -Algorithm SHA256 (Join-Path $out 'wholeflow.exe')).Hash

    Write-Host ''
    Write-Host "Release $version ready:" -ForegroundColor Green
    Write-Host "  $zip"
    Write-Host "  wholeflow.exe SHA-256 $hash"
    Write-Host ''
    Write-Host 'On each client PC: extract the zip, double-click Install-WholeFlow.cmd, accept the UAC prompt.'
    Write-Host 'Apply any new file in migrations\ to Supabase first (SQL Editor), once per Supabase project.'
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
