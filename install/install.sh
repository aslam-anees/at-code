#!/usr/bin/env bash
# @code installer for macOS, Linux, and WSL.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aslam-anees/at-code/src/install/install.sh | bash
set -euo pipefail

ATCODE_REPOSITORY="${ATCODE_INSTALL_REPO:-${AT_INSTALL_REPO:-aslam-anees/at-code}}"
ATCODE_BRANCH="${ATCODE_INSTALL_BRANCH:-${AT_INSTALL_BRANCH:-src}}"
ATCODE_INSTALL_DIR="${ATCODE_INSTALL_DIR:-${AT_INSTALL_DIR:-$HOME/.atcode/bin}}"
ATCODE_ENGINE_DIR="${ATCODE_ENGINE_DIR:-$HOME/.atcode/engine}"
ATCODE_ENGINE_REPOSITORY="${ATCODE_ENGINE_REPO:-ggml-org/llama.cpp}"
ATCODE_GITHUB_API="${ATCODE_GITHUB_API:-https://api.github.com}"
ATCODE_BINARY_BASE_URL="${ATCODE_BINARY_BASE_URL:-https://raw.githubusercontent.com/${ATCODE_REPOSITORY}/${ATCODE_BRANCH}/bin}"

info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33mwarn:\033[0m %s\n' "$1" >&2
}

fail() {
  printf '\033[1;31merror:\033[0m %s\n' "$1" >&2
  exit 1
}

download() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --show-error --silent "$url" --output "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=3 "$url" --output-document="$output"
  else
    fail "curl or wget is required"
  fi
}

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) fail "Unsupported operating system: $(uname -s). Use install.ps1 on Windows." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
  esac
  printf '%s-%s\n' "$os" "$arch"
}

calculate_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{print $NF}'
  else
    fail "sha256sum, shasum, or openssl is required to verify @code"
  fi
}

verify_download() {
  local source_name="$1"
  local path="$2"
  local expected actual
  expected="$(awk -v name="$source_name" '$2 == name { print $1; exit }' "$checksum_manifest")"
  [ -n "$expected" ] || fail "No checksum is published for $source_name"
  actual="$(calculate_sha256 "$path")"
  [ "$actual" = "$expected" ] || fail "Checksum verification failed for $source_name"
}

install_repository_binary() {
  local source_name="$1"
  local installed_name="$2"
  local downloaded="$tmp_dir/$source_name"
  download "${ATCODE_BINARY_BASE_URL%/}/$source_name" "$downloaded"
  verify_download "$source_name" "$downloaded"
  cp "$downloaded" "$ATCODE_INSTALL_DIR/$installed_name"
  chmod 755 "$ATCODE_INSTALL_DIR/$installed_name"
}

latest_engine_asset_url() {
  local pattern="$1"
  local metadata="$tmp_dir/engine-release.json"
  download "${ATCODE_GITHUB_API%/}/repos/${ATCODE_ENGINE_REPOSITORY}/releases/latest" "$metadata"
  sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata" |
    grep -E -m1 "$pattern" || true
}

next_available_path() {
  local preferred="$1"
  local candidate="$preferred"
  local index=2
  while [ -e "$candidate" ]; do
    candidate="${preferred}-${index}"
    index=$((index + 1))
  done
  printf '%s\n' "$candidate"
}

migrate_legacy_engine() {
  # Preserve installations created before the generic engine layout.
  local legacy_root="$HOME/.atcode/prism-llama.cpp"
  if [ -d "$legacy_root" ]; then
    local destination="$ATCODE_ENGINE_DIR"
    if [ -e "$destination" ]; then
      destination="$(next_available_path "$ATCODE_ENGINE_DIR/compat-runtime")"
    fi
    mkdir -p "$(dirname "$destination")"
    mv "$legacy_root" "$destination"
  fi

  local old_path new_path
  while IFS= read -r old_path; do
    [ -n "$old_path" ] || continue
    new_path="$(dirname "$old_path")/atcode-server"
    if [ -e "$new_path" ]; then
      new_path="$(next_available_path "$(dirname "$old_path")/atcode-server-compat")"
    fi
    mv "$old_path" "$new_path"
  done < <(
    {
      [ -f "$ATCODE_INSTALL_DIR/llama-server" ] && printf '%s\n' "$ATCODE_INSTALL_DIR/llama-server"
      find "$ATCODE_ENGINE_DIR" -type f -name llama-server -print 2>/dev/null || true
    }
  )
}

find_installed_engine() {
  local candidate
  for candidate in \
    "$ATCODE_ENGINE_DIR/atcode-server" \
    "$ATCODE_ENGINE_DIR/bin/atcode-server" \
    "$ATCODE_ENGINE_DIR/build/bin/atcode-server"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_engine() {
  local platform="$1"
  local installed_engine
  if installed_engine="$(find_installed_engine)"; then
    info "Verified engine: $installed_engine"
    return
  fi
  local pattern
  case "$platform" in
    darwin-arm64) pattern='bin-macos-arm64\.tar\.gz$' ;;
    darwin-amd64) pattern='bin-macos-x64\.tar\.gz$' ;;
    linux-arm64) pattern='bin-ubuntu-arm64\.tar\.gz$' ;;
    linux-amd64) pattern='bin-ubuntu-x64\.tar\.gz$' ;;
    *) fail "No @code engine is available for $platform" ;;
  esac

  local engine_url engine_archive engine_extract source_server source_dir
  engine_url="$(latest_engine_asset_url "$pattern")"
  [ -n "$engine_url" ] || fail "Could not resolve an @code engine for $platform"
  engine_archive="$tmp_dir/atcode-engine.tar.gz"
  engine_extract="$tmp_dir/engine-extract"
  mkdir -p "$engine_extract"
  info "Downloading the @code engine"
  download "$engine_url" "$engine_archive"
  tar -xzf "$engine_archive" -C "$engine_extract" ||
    fail "The @code engine archive could not be extracted"
  source_server="$(find "$engine_extract" -type f -name llama-server -print -quit)"
  [ -n "$source_server" ] || fail "The @code engine archive was incomplete"
  source_dir="$(dirname "$source_server")"

  mkdir -p "$ATCODE_ENGINE_DIR"
  cp "$source_server" "$ATCODE_ENGINE_DIR/atcode-server"
  chmod 755 "$ATCODE_ENGINE_DIR/atcode-server"
  find "$source_dir" -maxdepth 1 \( -type f -o -type l \) \
    \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \) \
    -exec cp -P {} "$ATCODE_ENGINE_DIR/" \;

  "$ATCODE_ENGINE_DIR/atcode-server" --version >/dev/null 2>&1 ||
    fail "The installed @code engine failed its verification check"
  info "Verified engine: $ATCODE_ENGINE_DIR/atcode-server"
}

setup_path() {
  case ":$PATH:" in
    *":$ATCODE_INSTALL_DIR:"*) return ;;
  esac
  if [ "${ATCODE_NO_PATH_UPDATE:-0}" = "1" ]; then
    info "Add $ATCODE_INSTALL_DIR to PATH to run @code from any directory"
    return
  fi

  local shell_rc path_line
  case "$(basename "${SHELL:-}")" in
    zsh) shell_rc="$HOME/.zshrc" ;;
    bash) shell_rc="$HOME/.bashrc" ;;
    *) shell_rc="$HOME/.profile" ;;
  esac
  path_line="export PATH=\"$ATCODE_INSTALL_DIR:\$PATH\""
  if [ ! -f "$shell_rc" ] || ! grep -Fqx "$path_line" "$shell_rc"; then
    {
      printf '\n'
      printf '%s\n' '# Added by @code installer'
      printf '%s\n' "$path_line"
    } >>"$shell_rc"
  fi
  export PATH="$ATCODE_INSTALL_DIR:$PATH"
  info "Added $ATCODE_INSTALL_DIR to PATH in $shell_rc"
}

main() {
  [ -n "${HOME:-}" ] || fail "\$HOME is not set"
  command -v uname >/dev/null 2>&1 || fail "uname is required"
  command -v awk >/dev/null 2>&1 || fail "awk is required"
  command -v tar >/dev/null 2>&1 || fail "tar is required"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/atcode-install.XXXXXX")"
  trap 'rm -rf "$tmp_dir"' EXIT
  checksum_manifest="$tmp_dir/SHA256SUMS"

  local platform
  platform="$(detect_platform)"
  info "Detected platform: $platform"
  mkdir -p "$ATCODE_INSTALL_DIR" "$HOME/.atcode/model"

  download "${ATCODE_BINARY_BASE_URL%/}/SHA256SUMS" "$checksum_manifest"
  install_repository_binary "at-${platform}" at
  ln -sfn at "$ATCODE_INSTALL_DIR/atcode"
  ln -sfn at "$ATCODE_INSTALL_DIR/@code"
  ln -sfn at "$ATCODE_INSTALL_DIR/@"

  case "$platform" in
    linux-*)
      install_repository_binary "atcode-linux-sandbox-${platform}" atcode-linux-sandbox
      install_repository_binary "atcode-seccomp-${platform}" atcode-seccomp
      ;;
  esac

  if ! "$ATCODE_INSTALL_DIR/at" --version >/dev/null 2>&1; then
    fail "The installed @code binary failed to run on $platform"
  fi
  info "Verified: $("$ATCODE_INSTALL_DIR/at" --version)"

  if [ "${ATCODE_SKIP_ENGINE:-0}" != "1" ]; then
    migrate_legacy_engine
    install_engine "$platform"
  fi
  setup_path

  if ! command -v npx >/dev/null 2>&1; then
    warn "Node.js 18+ is recommended for built-in MCP and browser automation tools"
  fi
  printf '\n'
  info "Installation complete. Run '@code', '@', 'atcode', or 'at'."
  info "On first run, @code downloads its local model."
}

main "$@"
