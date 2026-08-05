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

On macOS, Linux, and WSL, `@code` and `atcode` also work. On Windows
PowerShell, type `atcode`: PowerShell reserves a leading `@` as language
syntax. The `at` command remains available as a compatibility alias.

The installer verifies every download, installs the platform sandbox helpers,
and places the inference runtime under the generic
`~/.atcode/engine/atcode-server` name. Existing installations using the older
runtime layout are migrated without deleting models or settings.

When a verified native voice helper is published for the detected platform,
the installer adds it automatically. Otherwise the core @code installation
continues normally and voice can be set up later.

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

The installer also sets up `terminal-browser` when the upstream distribution
supports the host. On Linux, Windows, Intel macOS, and WSL it silently skips
that optional integration and keeps the existing browser tools available. Set
`ATCODE_SKIP_TERMINAL_BROWSER=1` to skip the setup everywhere.

## Support

- Website: [www.aistatine.com](https://www.aistatine.com)
- Contact: ceo@aistatine.com
- Book a meeting: https://cal.com/ceo-aistatine/30min
