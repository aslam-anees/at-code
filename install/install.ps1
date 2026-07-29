# @code installer for Windows PowerShell 5.1+.
#
# Usage:
#   Invoke-RestMethod https://raw.githubusercontent.com/aslam-anees/at-code/src/install/install.ps1 | Invoke-Expression

$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
$ProgressPreference = 'SilentlyContinue'

$Repository = if ($env:ATCODE_INSTALL_REPO) { $env:ATCODE_INSTALL_REPO }
              elseif ($env:AT_INSTALL_REPO) { $env:AT_INSTALL_REPO }
              else { 'aslam-anees/at-code' }
$Branch = if ($env:ATCODE_INSTALL_BRANCH) { $env:ATCODE_INSTALL_BRANCH }
          elseif ($env:AT_INSTALL_BRANCH) { $env:AT_INSTALL_BRANCH }
          else { 'src' }
$InstallDir = if ($env:ATCODE_INSTALL_DIR) { $env:ATCODE_INSTALL_DIR }
               elseif ($env:AT_INSTALL_DIR) { $env:AT_INSTALL_DIR }
               else { Join-Path $env:USERPROFILE '.atcode\bin' }
$EngineDir = if ($env:ATCODE_ENGINE_DIR) { $env:ATCODE_ENGINE_DIR }
              else { Join-Path $env:USERPROFILE '.atcode\engine' }
$EngineRepository = if ($env:ATCODE_ENGINE_REPO) { $env:ATCODE_ENGINE_REPO }
                     else { 'ggml-org/llama.cpp' }
$GitHubApi = if ($env:ATCODE_GITHUB_API) { $env:ATCODE_GITHUB_API }
              else { 'https://api.github.com' }
$BinaryBaseUrl = if ($env:ATCODE_BINARY_BASE_URL) { $env:ATCODE_BINARY_BASE_URL.TrimEnd('/') }
                  else { "https://raw.githubusercontent.com/$Repository/$Branch/bin" }

function Info([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Warn([string]$Message) {
    Write-Host "warn: $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    throw $Message
}

function Get-AtCodeArchitecture {
    try {
        $runtimeArchitecture =
            [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        if ($runtimeArchitecture -eq 'Arm64') { return 'arm64' }
        if ($runtimeArchitecture -eq 'X64') { return 'amd64' }
    } catch {}

    $architecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    } else {
        $env:PROCESSOR_ARCHITECTURE
    }
    if ($architecture -eq 'ARM64') { return 'arm64' }
    if ($architecture -eq 'AMD64') { return 'amd64' }
    Fail "Unsupported Windows architecture: $architecture"
}

function Get-ExpectedChecksum {
    param(
        [string]$ManifestPath,
        [string]$FileName
    )
    foreach ($line in Get-Content -Path $ManifestPath) {
        $parts = $line.Trim() -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $FileName) {
            return $parts[0].ToLowerInvariant()
        }
    }
    Fail "No checksum is published for $FileName"
}

function Install-RepositoryBinary {
    param(
        [string]$SourceName,
        [string]$InstalledName
    )
    $downloaded = Join-Path $TempDir $SourceName
    Invoke-WebRequest -Uri "$BinaryBaseUrl/$SourceName" -OutFile $downloaded -UseBasicParsing
    $expected = Get-ExpectedChecksum -ManifestPath $ChecksumManifest -FileName $SourceName
    $actual = (Get-FileHash -Path $downloaded -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Fail "Checksum verification failed for $SourceName"
    }
    Copy-Item -Path $downloaded -Destination (Join-Path $InstallDir $InstalledName) -Force
}

function Get-AvailablePath {
    param([string]$Preferred)
    $candidate = $Preferred
    $index = 2
    while (Test-Path $candidate) {
        $candidate = "$Preferred-$index"
        $index++
    }
    return $candidate
}

function Move-LegacyEngine {
    # Preserve installations created before the generic engine layout.
    $legacyRoot = Join-Path $env:USERPROFILE '.atcode\prism-llama.cpp'
    if (Test-Path $legacyRoot -PathType Container) {
        $destination = $EngineDir
        if (Test-Path $destination) {
            $destination = Get-AvailablePath -Preferred (Join-Path $EngineDir 'compat-runtime')
        }
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Move-Item -Path $legacyRoot -Destination $destination
    }

    $legacyServers = @((Join-Path $InstallDir 'llama-server.exe'))
    if (Test-Path $EngineDir -PathType Container) {
        $legacyServers += @(
            Get-ChildItem -Path $EngineDir -Recurse -Filter 'llama-server.exe' -File |
                ForEach-Object { $_.FullName }
        )
    }
    foreach ($oldPath in $legacyServers) {
        if (Test-Path $oldPath -PathType Leaf) {
            $newPath = Join-Path (Split-Path $oldPath -Parent) 'atcode-server.exe'
            if (Test-Path $newPath) {
                $newPath = Get-AvailablePath -Preferred (
                    Join-Path (Split-Path $oldPath -Parent) 'atcode-server-compat.exe'
                )
            }
            Move-Item -Path $oldPath -Destination $newPath
        }
    }
}

function Find-InstalledEngine {
    foreach ($candidate in @(
        (Join-Path $EngineDir 'atcode-server.exe'),
        (Join-Path $EngineDir 'bin\atcode-server.exe'),
        (Join-Path $EngineDir 'build\bin\atcode-server.exe')
    )) {
        if (Test-Path $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Install-AtCodeEngine {
    param([string]$Architecture)

    $installedEngine = Find-InstalledEngine
    if ($installedEngine) {
        Info "Verified engine: $installedEngine"
        return
    }
    $release = Invoke-RestMethod `
        -Uri "$($GitHubApi.TrimEnd('/'))/repos/$EngineRepository/releases/latest" `
        -Headers @{ Accept = 'application/vnd.github+json' } `
        -TimeoutSec 30
    $assetPattern = if ($Architecture -eq 'arm64') {
        'bin-win-cpu-arm64\.zip$'
    } else {
        'bin-win-cpu-x64\.zip$'
    }
    $asset = $release.assets |
        Where-Object { $_.name -match $assetPattern } |
        Select-Object -First 1
    if (-not $asset) {
        Fail "Could not resolve an @code engine for windows-$Architecture"
    }

    $engineArchive = Join-Path $TempDir 'atcode-engine.zip'
    $engineExtract = Join-Path $TempDir 'engine-extract'
    Info 'Downloading the @code engine'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $engineArchive -UseBasicParsing
    Expand-Archive -Path $engineArchive -DestinationPath $engineExtract -Force
    $sourceServer = Get-ChildItem -Path $engineExtract -Recurse -Filter 'llama-server.exe' -File |
        Select-Object -First 1
    if (-not $sourceServer) {
        Fail 'The @code engine archive was incomplete'
    }

    New-Item -ItemType Directory -Path $EngineDir -Force | Out-Null
    Copy-Item -Path $sourceServer.FullName `
        -Destination (Join-Path $EngineDir 'atcode-server.exe') -Force
    Get-ChildItem -Path $sourceServer.DirectoryName -Filter '*.dll' -File |
        Copy-Item -Destination $EngineDir -Force

    $targetServer = Join-Path $EngineDir 'atcode-server.exe'
    try {
        & $targetServer --version *> $null
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    } catch {
        Fail 'The installed @code engine failed its verification check'
    }
    Info "Verified engine: $targetServer"
}

function Add-AtCodeToPath {
    $currentEntries = @($env:Path -split [IO.Path]::PathSeparator)
    if ($currentEntries -notcontains $InstallDir) {
        $env:Path = "$InstallDir$([IO.Path]::PathSeparator)$env:Path"
    }
    if ($env:ATCODE_NO_PATH_UPDATE -eq '1') {
        Info "Add $InstallDir to PATH to run @code from any directory"
        return
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @($userPath -split [IO.Path]::PathSeparator)
    if ($userEntries -notcontains $InstallDir) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $InstallDir
        } else {
            "$InstallDir$([IO.Path]::PathSeparator)$userPath"
        }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Info "Added $InstallDir to your user PATH"
    }
}

if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    Fail 'USERPROFILE is not set'
}

$Architecture = Get-AtCodeArchitecture
$Platform = "windows-$Architecture"
$TempDir = Join-Path ([IO.Path]::GetTempPath()) (
    'atcode-install-' + [Guid]::NewGuid().ToString('N')
)
$ChecksumManifest = Join-Path $TempDir 'SHA256SUMS'

try {
    Info "Detected platform: $Platform"
    New-Item -ItemType Directory -Path $TempDir, $InstallDir -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $env:USERPROFILE '.atcode\model'
    ) -Force | Out-Null
    Invoke-WebRequest -Uri "$BinaryBaseUrl/SHA256SUMS" `
        -OutFile $ChecksumManifest -UseBasicParsing

    Install-RepositoryBinary -SourceName "at-$Platform.exe" -InstalledName 'at.exe'
    Copy-Item (Join-Path $InstallDir 'at.exe') `
        (Join-Path $InstallDir 'atcode.exe') -Force
    Copy-Item (Join-Path $InstallDir 'at.exe') `
        (Join-Path $InstallDir '@code.exe') -Force
    Copy-Item (Join-Path $InstallDir 'at.exe') `
        (Join-Path $InstallDir '@.exe') -Force
    Set-Content -Path (Join-Path $InstallDir '@code.cmd') `
        -Value "@echo off`r`n`"%~dp0@code.exe`" %*" -Encoding ASCII
    Set-Content -Path (Join-Path $InstallDir '@.cmd') `
        -Value "@echo off`r`n`"%~dp0@.exe`" %*" -Encoding ASCII

    Install-RepositoryBinary `
        -SourceName "atcode-windows-command-runner-$Platform.exe" `
        -InstalledName 'atcode-windows-command-runner.exe'
    Install-RepositoryBinary `
        -SourceName "atcode-windows-sandbox-setup-$Platform.exe" `
        -InstalledName 'atcode-windows-sandbox-setup.exe'

    try {
        $version = (& (Join-Path $InstallDir 'at.exe') --version) 2>&1
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    } catch {
        Fail "The installed @code binary failed to run on $Platform"
    }
    Info "Verified: $version"

    if ($env:ATCODE_SKIP_ENGINE -ne '1') {
        Move-LegacyEngine
        Install-AtCodeEngine -Architecture $Architecture
    }
    Add-AtCodeToPath

    if (-not (Get-Command 'npx' -ErrorAction SilentlyContinue)) {
        Warn 'Node.js 18+ is recommended for built-in MCP and browser automation tools'
    }
    Write-Host ''
    Info 'Installation complete. Run "atcode" or "at".'
    Info 'In cmd.exe, "@code" and "@" are also available.'
    Info 'On first run, @code downloads its local model.'
} finally {
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
}
