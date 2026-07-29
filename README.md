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

`@code`, `atcode`, and `at` also work. On Windows PowerShell, use `atcode` or
`at`: PowerShell reserves a leading `@` as language syntax. In `cmd.exe`,
`@code` and `@` are available too.

The installer verifies every download, installs the platform sandbox helpers,
and places the inference runtime under the generic
`~/.atcode/engine/atcode-server` name. Existing installations using the older
runtime layout are migrated without deleting models or settings.

## Repository layout

- `install/install.sh` — macOS / Linux / WSL installer
- `install/install.ps1` — Windows installer
- `bin/` — checksum-verified prebuilt @code binaries and required sandbox
  helpers for:
  - macOS: Apple Silicon and Intel
  - Linux and WSL: ARM64 and x86-64
  - Windows: ARM64 and x86-64
- `bin/SHA256SUMS` — integrity manifest consumed by both installers

## Requirements

- 8 GB+ RAM
- ~4.8 GB free disk space (binary + model)
- macOS 12+, Windows 10+ (64-bit), or a modern Linux distribution
- Node.js 18+ is recommended for the built-in MCP and browser automation tools

## Support

- Website: [www.aistatine.com](https://www.aistatine.com)
- Contact: ceo@aistatine.com
- Book a meeting: https://cal.com/ceo-aistatine/30min
