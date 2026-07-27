# @code

@code by [Aistatine](https://www.aistatine.com)

The autonomous coding agent that runs entirely on your device. No cloud, no API keys, no data leaving your machine.

## Install

**macOS / Linux / WSL**

```sh
curl -fsSL https://raw.githubusercontent.com/aslam-anees/at-code/src/install/install.sh | bash
```

**Windows (PowerShell)**

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/aslam-anees/at-code/src/install/install.ps1 | Invoke-Expression
```

Then just type:

```sh
@
```

`@code`, `atcode`, `at`, and `sonut` also work as aliases. On Windows
PowerShell, use `atcode`: PowerShell reserves a leading `@` as language
syntax. In `cmd.exe`, `@code` and `@` are available too.

## Repository layout

- `install/install.sh` — macOS / Linux / WSL installer
- `install/install.ps1` — Windows installer
- `bin/` — prebuilt @code binaries:
  - `at-darwin-arm64` (Apple Silicon)
  - `@code-darwin-arm64` (Apple Silicon alias)
  - `at-darwin-amd64` (Intel Mac)
  - `@code-darwin-amd64` (Intel Mac alias)
  - `at-linux-amd64`
  - `@code-linux-amd64`
  - `at-linux-arm64`
  - `@code-linux-arm64`
  - `at-windows-amd64.exe`
  - `@code-windows-amd64.exe`

## Requirements

- 8 GB+ RAM
- ~4.8 GB free disk space (binary + model)
- macOS 12+, Windows 10+ (64-bit), or a modern Linux distro

## Support

- Website: [www.aistatine.com](https://www.aistatine.com)
- Contact: ceo@aistatine.com
- Book a meeting: https://cal.com/ceo-aistatine/30min
