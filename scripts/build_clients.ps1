# Builds every desktop/mobile client that the current machine can produce and
# drops the artifacts into downloads/ (served by nginx at /downloads).
#   - Windows:  only when Visual Studio C++ tools are installed
#   - Android:  only when the Android SDK is installed
# macOS / iOS / Linux need their native OSes: use scripts/build_clients.sh.
# The web client is optional and not packaged here.
#Requires -Version 5
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $out = Join-Path $root 'downloads'
    New-Item -ItemType Directory -Force -Path $out | Out-Null

    Write-Host '==> Windows'
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = $null
    if (Test-Path $vswhere) {
        $vs = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
    }
    if ($vs) {
        flutter config --enable-windows-desktop | Out-Null
        if (-not (Test-Path 'windows')) { flutter create --platforms=windows . | Out-Null }
        flutter build windows --release
        Compress-Archive -Path 'build/windows/x64/runner/Release/*' `
            -DestinationPath (Join-Path $out 'graphical_editor-windows.zip') -Force
    } else {
        Write-Host '   Visual Studio C++ tools not found - skipping Windows.'
    }

    Write-Host '==> Android'
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
           else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    if (Test-Path $sdk) {
        flutter build apk --release
        Copy-Item 'build/app/outputs/flutter-apk/app-release.apk' `
            (Join-Path $out 'graphical_editor.apk') -Force
    } else {
        Write-Host '   Android SDK not found - skipping Android.'
    }

    Write-Host ''
    Write-Host "Artifacts in $out :"
    Get-ChildItem $out | Format-Table Name, Length
} finally {
    Pop-Location
}
