# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# build-traxion-server.ps1
#
# Builds the Traxion dedicated-server binary (Linux x64) headlessly using Unity.
#
# Usage:
#   pwsh build-traxion-server.ps1 [-OutputPath <path>]
#
# Parameters:
#   -OutputPath   Where to write the server binary.
#                 Default: <repo>/Builds/TraxionServer/TraxionServer
#
# Prerequisites:
#   • Unity editor (2021.3 LTS or newer) must be on the system PATH, OR set
#     the UNITY_PATH environment variable to the full path of Unity.exe / Unity.
#   • Linux Dedicated Server Build Support module installed in that Unity version.

param(
    [string]$OutputPath = ""
)

$ROOT_DIR    = Resolve-Path "$PSScriptRoot\.."
$PROJECT_DIR = "$ROOT_DIR\GameLiftPlugin\Samples~\Traxion"
$LOG_DIR     = "$ROOT_DIR\Temp\build"
$LOG_FILE    = "$LOG_DIR\TraxionServerBuildLog.txt"
$BUILD_TIMEOUT_SECONDS = 600

if (-not $OutputPath) {
    $OutputPath = "$ROOT_DIR\Builds\TraxionServer\TraxionServer"
}

# ── Locate Unity ──────────────────────────────────────────────────────────────

$UnityExe = $env:UNITY_PATH

if (-not $UnityExe) {
    # Common install locations
    $candidates = @(
        "Unity",                                              # on PATH
        "C:\Program Files\Unity\Hub\Editor\*\Editor\Unity.exe",
        "/Applications/Unity/Hub/Editor/*/Unity.app/Contents/MacOS/Unity",
        "/opt/unity/editor/Unity"
    )
    foreach ($c in $candidates) {
        $resolved = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($resolved) { $UnityExe = $resolved.FullName; break }
    }
}

if (-not $UnityExe -or -not (Get-Command $UnityExe -ErrorAction SilentlyContinue)) {
    Write-Host @"
ERROR: Cannot find the Unity editor executable.
Set the UNITY_PATH environment variable to the full path of Unity, e.g.:

  Windows:  `$env:UNITY_PATH = "C:\Program Files\Unity\Hub\Editor\2022.3.0f1\Editor\Unity.exe"
  Linux:    export UNITY_PATH=/opt/unity/editor/Unity
  macOS:    export UNITY_PATH="/Applications/Unity/Hub/Editor/2022.3.0f1/Unity.app/Contents/MacOS/Unity"
"@ -ForegroundColor Red
    exit 1
}

Write-Host "Unity: $UnityExe" -ForegroundColor Cyan
Write-Host "Project: $PROJECT_DIR"
Write-Host "Output:  $OutputPath"
Write-Host "Log:     $LOG_FILE"
Write-Host ""

# ── Ensure log directory exists ───────────────────────────────────────────────

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR | Out-Null
}

# ── Run Unity in batch mode ───────────────────────────────────────────────────

Write-Host "Building Traxion server (this may take several minutes)..." -ForegroundColor Yellow

$unityArgs = @(
    "-batchmode",
    "-quit",
    "-projectPath", $PROJECT_DIR,
    "-logFile",     $LOG_FILE,
    "-executeMethod", "TraxionServerBuildScript.Build",
    "--",
    "-outputPath",  $OutputPath
)

$proc = Start-Process -FilePath $UnityExe -ArgumentList $unityArgs -PassThru -NoNewWindow
$proc | Wait-Process -Timeout $BUILD_TIMEOUT_SECONDS -ErrorAction SilentlyContinue

if (-not $proc.HasExited) {
    Write-Host "ERROR: Build timed out after $BUILD_TIMEOUT_SECONDS seconds." -ForegroundColor Red
    $proc | Stop-Process -Force
    exit 1
}

# ── Check result ──────────────────────────────────────────────────────────────

if ($proc.ExitCode -eq 0 -and (Test-Path $OutputPath)) {
    $sizeMB = [math]::Round((Get-Item $OutputPath).Length / 1MB, 1)
    Write-Host ""
    Write-Host "Build succeeded!  ($sizeMB MB)" -ForegroundColor Green
    Write-Host "Server binary:    $OutputPath"
    Write-Host ""
    Write-Host "Next step — upload to AWS GameLift:" -ForegroundColor Cyan
    Write-Host "  aws gamelift upload-build \"
    Write-Host "    --name TraxionServer \"
    Write-Host "    --build-version 1.0.0 \"
    Write-Host "    --build-root `"$(Split-Path $OutputPath)`" \"
    Write-Host "    --operating-system AMAZON_LINUX_2023 \"
    Write-Host "    --region <your-region>"
    exit 0
}
else {
    Write-Host ""
    Write-Host "Build FAILED (exit code $($proc.ExitCode))." -ForegroundColor Red
    Write-Host "Check the log for details: $LOG_FILE" -ForegroundColor DarkYellow

    # Print last 30 lines of the log to the console for quick diagnosis
    if (Test-Path $LOG_FILE) {
        Write-Host ""
        Write-Host "--- Last 30 lines of build log ---" -ForegroundColor DarkYellow
        Get-Content $LOG_FILE -Tail 30
    }
    exit 1
}
