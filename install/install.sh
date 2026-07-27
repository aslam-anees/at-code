#!/usr/bin/env bash
# @code installer for macOS, Linux, and WSL.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aslam-anees/at-code/src/install/install.sh | bash
#
# What it does:
#   1. Detects OS/arch.
#   2. Installs the @code binary ("at") to ~/.atcode/bin — from GitHub releases
#      when available, otherwise from the prebuilt binaries committed in this
#      repository (bin/at-<os>-<arch>).
#   3. Installs the server build (with a compatible fallback).
#   4. Adds ~/.atcode/bin to PATH.
#   The @0.1 model auto-downloads to ~/.atcode/model on first run.
set -euo pipefail

# ---- Configuration ----------------------------------------------------------
REPO="${AT_INSTALL_REPO:-aslam-anees/at-code}"
BRANCH="${AT_INSTALL_BRANCH:-src}"
INSTALL_DIR="${AT_INSTALL_DIR:-$HOME/.atcode/bin}"
LLAMA_REPO="ggml-org/llama.cpp"
PRISM_REPO="${AT_PRISM_REPO:-PrismML-Eng/llama.cpp}"
PRISM_DIR="${AT_PRISM_DIR:-$HOME/.atcode/prism-llama.cpp}"
# -----------------------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33mwarn:\033[0m %s\n' "$1" >&2; }
error() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux)  os="linux" ;;
    *) error "Unsupported OS: $(uname -s). On Windows, use install.ps1 instead." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) error "Unsupported architecture: $(uname -m)" ;;
  esac
  echo "${os}-${arch}"
}

download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --progress-bar "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 "$url" -O "$dest"
  else
    error "curl or wget is required to install @code"
  fi
}

# Fetch a URL's body to stdout with whichever downloader exists.
fetch() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url" 2>/dev/null
  fi
}

# Fetch the download URL of the first release asset whose name matches $1.
latest_asset_url() {
  local repo="$1" pattern="$2"
  fetch "https://api.github.com/repos/${repo}/releases/latest" |
    grep -o '"browser_download_url": *"[^"]*"' |
    cut -d'"' -f4 |
    grep -m1 "$pattern" || true
}

install_at() {
  local platform="$1" tmp_dir="$2" asset_url raw_url

  asset_url="$(latest_asset_url "$REPO" "at-${platform}")"
  if [[ -n "$asset_url" ]]; then
    info "Downloading @code (${platform}) from GitHub releases"
    download "$asset_url" "$tmp_dir/at"
  else
    raw_url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/bin/at-${platform}"
    info "Downloading @code (${platform})"
    download "$raw_url" "$tmp_dir/at" ||
      error "Could not download the @code binary for ${platform}."
  fi

  install -m 0755 "$tmp_dir/at" "$INSTALL_DIR/at"
  ln -sf "$INSTALL_DIR/at" "$INSTALL_DIR/@"
  ln -sf "$INSTALL_DIR/at" "$INSTALL_DIR/@code"
  ln -sf "$INSTALL_DIR/at" "$INSTALL_DIR/atcode"

  # Smoke-test the installed binary so a truncated download or wrong-arch
  # binary fails loudly here instead of confusing the user later.
  if ! "$INSTALL_DIR/at" --version >/dev/null 2>&1; then
    error "The installed @code binary failed to run (platform ${platform}). Re-run the installer; if it persists, report it at https://github.com/${REPO}/issues"
  fi
  info "Verified: $("$INSTALL_DIR/at" --version)"
}

install_upstream_llama_server() {
  # Already present? Done.
  if command -v llama-server >/dev/null 2>&1 || [[ -x "$INSTALL_DIR/llama-server" ]]; then
    info "Server already installed"
    return
  fi

  # macOS: Homebrew is the best-maintained path (Metal build, auto-updates).
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    info "Installing server"
    brew install llama.cpp && return
    warn "Homebrew install failed; falling back to GitHub release binaries"
  fi

  local pattern
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)          pattern='bin-macos-arm64\.tar\.gz' ;;
    Darwin-x86_64)         pattern='bin-macos-x64\.tar\.gz' ;;
    Linux-x86_64)          pattern='bin-ubuntu-x64\.tar\.gz' ;;
    Linux-arm64|Linux-aarch64) pattern='bin-ubuntu-arm64\.tar\.gz' ;;
    *) warn "No prebuilt llama-server for this platform; install llama.cpp manually (https://github.com/${LLAMA_REPO})"; return ;;
  esac

  local url tmp_archive extract_dir server_bin
  url="$(latest_asset_url "$LLAMA_REPO" "$pattern")"
  [[ -n "$url" ]] || { warn "Could not find a llama.cpp release asset; install it manually"; return; }

  info "Downloading server"
  tmp_archive="$(mktemp -d)/llama.tar.gz"
  download "$url" "$tmp_archive"
  extract_dir="$(mktemp -d)"
  if ! tar -xzf "$tmp_archive" -C "$extract_dir"; then
    warn "Server archive could not be extracted"
    rm -rf "$extract_dir" "$(dirname "$tmp_archive")"
    return
  fi
  # Release archives place binaries under build/bin/ (layout has varied); find it.
  server_bin="$(find "$extract_dir" -name llama-server -type f | head -1)"
  [[ -n "$server_bin" ]] || { warn "llama-server not found inside the release archive; install llama.cpp manually"; rm -rf "$extract_dir" "$(dirname "$tmp_archive")"; return; }
  # Copy every sibling binary + shared libs so llama-server's dylib/so lookups work.
  cp -R "$(dirname "$server_bin")/." "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/llama-server"
  rm -rf "$extract_dir" "$(dirname "$tmp_archive")"
  info "Installed server"
}

install_prism_llama_server() {
  local platform="$1" pattern url tmp_archive extract_dir server_bin server_dir prism_bin
  prism_bin="$PRISM_DIR/build/bin"

  if [[ -x "$prism_bin/llama-server" || -x "$prism_bin/llama-server.exe" ]]; then
    info "Server already installed"
    return 0
  fi

  case "$platform" in
    darwin-arm64) pattern='llama-prism-.*-bin-macos-arm64\.tar\.gz' ;;
    darwin-amd64) pattern='llama-prism-.*-bin-macos-x64\.tar\.gz' ;;
    linux-amd64)  pattern='llama-prism-.*-bin-ubuntu-x64\.tar\.gz' ;;
    linux-arm64)  pattern='llama-prism-.*-bin-ubuntu-arm64\.tar\.gz' ;;
    *)
      warn "No server release for ${platform}; trying a compatible fallback"
      install_upstream_llama_server
      return
      ;;
  esac

  url="$(latest_asset_url "$PRISM_REPO" "$pattern")"
  if [[ -z "$url" ]]; then
    warn "Could not find a server release for ${platform}; trying a compatible fallback"
    install_upstream_llama_server
    return
  fi

  info "Downloading server"
  tmp_archive="$(mktemp -d)/prism-llama.tar.gz"
  extract_dir="$(mktemp -d)"
  if ! download "$url" "$tmp_archive"; then
    warn "Server download failed; trying a compatible fallback"
    rm -rf "$extract_dir" "$(dirname "$tmp_archive")"
    install_upstream_llama_server
    return
  fi
  if ! tar -xzf "$tmp_archive" -C "$extract_dir"; then
    warn "Server archive could not be extracted; trying a compatible fallback"
    rm -rf "$extract_dir" "$(dirname "$tmp_archive")"
    install_upstream_llama_server
    return
  fi
  server_bin="$(find "$extract_dir" -type f -name 'llama-server' | head -1)"
  [[ -n "$server_bin" ]] || {
    warn "Server was not found in the archive; trying a compatible fallback"
    rm -rf "$extract_dir" "$(dirname "$tmp_archive")"
    install_upstream_llama_server
    return
  }
  server_dir="$(dirname "$server_bin")"
  mkdir -p "$prism_bin"
  cp -R "$server_dir/." "$prism_bin/"
  # Keep the Prism binary on the install PATH as well. This covers non-TUI
  # entry points and Windows, where the executable suffix is .exe.
  cp -R "$server_dir/." "$INSTALL_DIR/"
  chmod +x "$prism_bin/llama-server" "$INSTALL_DIR/llama-server"
  rm -rf "$extract_dir" "$(dirname "$tmp_archive")"
  info "Installed server"
}

setup_path() {
  [[ ":$PATH:" == *":${INSTALL_DIR}:"* ]] && return
  local shell_rc
  case "$(basename "${SHELL:-}")" in
    zsh)  shell_rc="$HOME/.zshrc" ;;
    bash) shell_rc="$HOME/.bashrc" ;;
    *)    shell_rc="$HOME/.profile" ;;
  esac
  {
    echo ''
    echo '# Added by @code installer'
    echo "export PATH=\"${INSTALL_DIR}:\$PATH\""
  } >> "$shell_rc"
  info "Added @code commands to your PATH"
  info "Open a new terminal, then type '@code', '@', or 'atcode'"
}

main() {
  [[ -n "${HOME:-}" ]] || error "\$HOME is not set; cannot pick an install directory"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local platform
  platform="$(detect_platform)"
  info "Detected platform: ${platform}"

  mkdir -p "$INSTALL_DIR" "$HOME/.atcode/model"

  install_at "$platform" "$tmp_dir"
  install_prism_llama_server "$platform"
  setup_path

  echo ""
  info "Installation complete. Just type '@', '@code', or 'atcode' to get started."
  info "On first run the @0.1 model auto-downloads (~4.8 GB)."
}

main "$@"
