# @code installer for Windows (PowerShell 5.1+).
#
# Usage (PowerShell):
#   Invoke-RestMethod https://raw.githubusercontent.com/aslam-anees/at-code/src/install/install.ps1 | Invoke-Expression
#
# What it does:
#   1. Installs at.exe to %USERPROFILE%\.atcode\bin — from GitHub releases when
#      available, otherwise from the prebuilt binaries committed in this repo.
#   2. Installs the server build, with a compatible fallback.
#   3. Adds the bin directory to the user PATH.
#   The @0.1 model auto-downloads to %USERPROFILE%\.atcode\model on first run.

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 defaults to TLS 1.0 on older systems, which GitHub
# rejects; force TLS 1.2+. Hiding the progress bar also makes
# Invoke-WebRequest downloads dramatically faster on 5.1.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$ProgressPreference = 'SilentlyContinue'

$Repo       = if ($env:AT_INSTALL_REPO)   { $env:AT_INSTALL_REPO }   else { 'aslam-anees/at-code' }
$Branch     = if ($env:AT_INSTALL_BRANCH) { $env:AT_INSTALL_BRANCH } else { 'src' }
$InstallDir = if ($env:AT_INSTALL_DIR)    { $env:AT_INSTALL_DIR }    else { Join-Path $env:USERPROFILE '.atcode\bin' }
$LlamaRepo  = 'ggml-org/llama.cpp'
$PrismRepo  = if ($env:AT_PRISM_REPO) { $env:AT_PRISM_REPO } else { 'PrismML-Eng/llama.cpp' }
$PrismDir   = if ($env:AT_PRISM_DIR)  { $env:AT_PRISM_DIR }  else { Join-Path $env:USERPROFILE '.atcode\prism-llama.cpp' }

function Info($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg)  { Write-Host "warn: $msg" -ForegroundColor Yellow }
# throw (not exit): this script is usually run via `irm | iex`, where exit
# would close the user's whole PowerShell session.
function Fail($msg)  { Write-Host "error: $msg" -ForegroundColor Red; throw $msg }

function Get-LatestAssetUrl($repo, $pattern) {
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
        return ($release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1).browser_download_url
    } catch { return $null }
}

# Architecture
$arch = if ([Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
} else { Fail '@code requires 64-bit Windows.' }
Info "Detected platform: windows-$arch"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE '.atcode\model') | Out-Null

# ---- at.exe ------------------------------------------------------------------
$atExe = Join-Path $InstallDir 'at.exe'
$atUrl = Get-LatestAssetUrl $Repo "at-windows-$arch"
if (-not $atUrl) {
    $atUrl = "https://raw.githubusercontent.com/$Repo/$Branch/bin/at-windows-$arch.exe"
}
Info 'Downloading @code'
try {
    Invoke-WebRequest -Uri $atUrl -OutFile $atExe
} catch {
    Fail "Could not download the @code binary for windows-$arch."
}
# PowerShell reserves `@` at the start of a token for language syntax.  The
# portable Windows commands are therefore `atcode` and `at`; `@code` and `@`
# remain available to cmd.exe users.
Copy-Item -Path $atExe -Destination (Join-Path $InstallDir 'atcode.exe') -Force
Copy-Item -Path $atExe -Destination (Join-Path $InstallDir '@code.exe') -Force
Set-Content -Path (Join-Path $InstallDir '@code.cmd') -Value "@echo off`r`n`"%~dp0@code.exe`" %*" -Encoding ASCII
Set-Content -Path (Join-Path $InstallDir '@.cmd') -Value "@echo off`r`n`"%~dp0@code.exe`" %*" -Encoding ASCII
Info 'Installed @code'

# Smoke-test the installed binary so a truncated download or wrong-arch
# binary fails loudly here instead of confusing the user later.
try {
    $ver = (& $atExe --version) 2>&1
    if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    Info "Verified: $ver"
} catch {
    Fail "The installed @code binary failed to run (windows-$arch). Re-run the installer; if it persists, report it at https://github.com/$Repo/issues"
}

# ---- llama-server --------------------------------------------------------------
function Install-LlamaArchive($url, $label) {
    if (-not $url) { return $false }
    Info "Downloading $label"
    $zip = Join-Path $env:TEMP "llama-$(Get-Random).zip"
    $extract = Join-Path $env:TEMP "llama-extract-$(Get-Random)"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $serverBin = Get-ChildItem -Path $extract -Recurse -Filter 'llama-server.exe' | Select-Object -First 1
        if (-not $serverBin) { return $false }
        $prismBin = Join-Path $PrismDir 'build\bin'
        New-Item -ItemType Directory -Force -Path $prismBin | Out-Null
        # Keep the full sibling directory: llama-server needs its DLLs beside it.
        Copy-Item -Path (Join-Path $serverBin.DirectoryName '*') -Destination $prismBin -Recurse -Force
        Copy-Item -Path (Join-Path $serverBin.DirectoryName '*') -Destination $InstallDir -Recurse -Force
        Info 'Installed server'
        return $true
    } catch {
        Warn "Could not install $label; trying the fallback engine"
        return $false
    } finally {
        Remove-Item -Force $zip -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $extract -ErrorAction SilentlyContinue
    }
}

$prismServer = Join-Path $PrismDir 'build\bin\llama-server.exe'
$llamaExisting = Get-Command llama-server -ErrorAction SilentlyContinue
if (Test-Path $prismServer) {
    Info 'Server already installed'
} else {
    # Prefer a Prism CUDA build for NVIDIA, then Prism's CPU build. The CPU
    # release is also used on ARM64 Windows; it is the only published ARM build.
    $hasNvidia = $null -ne (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'NVIDIA' })
    $pattern = if ($arch -eq 'arm64') { 'llama-bin-win-cpu-arm64\.zip' }
               elseif ($hasNvidia)    { 'llama-prism-.*bin-win-cuda-12\.4-x64\.zip' }
               else                   { 'llama-bin-win-cpu-x64\.zip' }
    $prismUrl = Get-LatestAssetUrl $PrismRepo $pattern
    $installed = Install-LlamaArchive $prismUrl 'server'
    if (-not $installed -and -not $llamaExisting -and -not (Test-Path (Join-Path $InstallDir 'llama-server.exe'))) {
        Warn 'Server release unavailable; trying a compatible fallback'
        $fallbackPattern = if ($arch -eq 'arm64') { 'bin-win-cpu-arm64\.zip' }
                           elseif ($hasNvidia)    { 'bin-win-cuda.*x64\.zip' }
                           else                   { 'bin-win-cpu-x64\.zip' }
        $llamaUrl = Get-LatestAssetUrl $LlamaRepo $fallbackPattern
        if (-not (Install-LlamaArchive $llamaUrl 'server')) {
            Warn "Could not find a llama.cpp release asset; install it manually (https://github.com/$LlamaRepo)"
        }
    } elseif (-not $installed) {
        Info 'Existing server detected; keeping it as the fallback'
    }
}

# ---- PATH ----------------------------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$InstallDir;$userPath", 'User')
    Info 'Added @code commands to your user PATH'
}
# Update this PowerShell process too. Without this, `at` resolves to Windows'
# deprecated system scheduler command until the user opens a new terminal.
if ($env:Path -notlike "*$InstallDir*") { $env:Path = "$InstallDir;$env:Path" }
Info 'Open a new terminal to refresh PATH for other programs'

Write-Host ''
Info 'Installation complete. Run "atcode" to get started.'
Info 'In cmd.exe, "@code", "@", and "at" are also available.'
Info 'On first run the @0.1 model auto-downloads (~4.8 GB).'
