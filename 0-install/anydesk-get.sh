#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05 (rewritten 2026-10-04 for cross-platform use)
#
# Installs AnyDesk:
#   macOS                           -> Homebrew cask (brew install --cask anydesk)
#   Debian, Ubuntu, Linux Mint      -> AnyDesk's official apt repository
#   openSUSE, RHEL, Fedora, others  -> prints the download page. AnyDesk ships RPMs there
#                                      rather than a package repo, so no URL is guessed.
#
# Usage: anydesk-get.sh [--dry-run] [--uninstall] [--help]

set -eo pipefail

KEY_URL="https://keys.anydesk.com/repos/DEB-GPG-KEY"
KEY_PATH="/etc/apt/keyrings/anydesk-stable-keyring.gpg"
REPO_FILE="/etc/apt/sources.list.d/anydesk-stable.list"
REPO_BASE="http://deb.anydesk.com/"
DOWNLOAD_PAGE="https://anydesk.com/en/downloads/linux"

DRY_RUN=false
UNINSTALL=false

log_info()  { echo "[INFO] $*"; }
log_warn()  { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: anydesk-get.sh [--dry-run] [--uninstall] [--help]

  --dry-run     Show what would be done without changing anything.
  --uninstall   Remove AnyDesk and its repository (where applicable).
  -h, --help    Show this help.
EOF
}

# Run a command, or only print it under --dry-run.
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

install_macos() {
  if [[ "$UNINSTALL" == "true" ]]; then
    run brew uninstall --cask anydesk
    return 0
  fi
  if [[ -d /Applications/AnyDesk.app ]]; then
    log_info "AnyDesk is already installed (/Applications/AnyDesk.app)."
    return 0
  fi
  command -v brew >/dev/null 2>&1 || log_error "Homebrew not found. Install it from https://brew.sh, then re-run."
  run brew install --cask anydesk
  log_info "AnyDesk installed. Open it from Applications."
  log_info "macOS may ask for Screen Recording and Accessibility permission the first time a session is hosted."
  log_info "Grant them in System Settings > Privacy & Security."
}

install_debian() {
  if [[ "$UNINSTALL" == "true" ]]; then
    run sudo apt-get remove --purge -y anydesk
    run sudo rm -f "$REPO_FILE" "$KEY_PATH"
    run sudo apt-get update
    log_info "AnyDesk removed."
    return 0
  fi

  # Install only what is missing. Re-running apt install on present packages would upgrade them.
  local pkg missing=()
  for pkg in ca-certificates curl gnupg; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if (( ${#missing[@]} > 0 )); then
    log_info "Installing missing prerequisites: ${missing[*]}"
    run sudo apt-get update
    run sudo apt-get install -y "${missing[@]}"
  fi
  run sudo install -d -m 0755 /etc/apt/keyrings

  # Download to a file first. A failed download then stops here, instead of silently
  # producing an empty keyring the way a pipe into gpg can.
  log_info "Fetching the AnyDesk signing key..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] curl -o <tmpfile> $KEY_URL; sudo gpg --dearmor -o $KEY_PATH <tmpfile>"
  else
    local tmp_key
    tmp_key="$(mktemp)"
    curl -fsSL "$KEY_URL" -o "$tmp_key"
    [[ -s "$tmp_key" ]] || log_error "The downloaded key is empty. Check access to $KEY_URL"
    sudo gpg --batch --yes --dearmor -o "$KEY_PATH" "$tmp_key"
    rm -f "$tmp_key"
  fi

  local arch
  arch="$(dpkg --print-architecture)"
  log_info "Writing the AnyDesk apt source for $arch..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] write $REPO_FILE: deb [arch=$arch signed-by=$KEY_PATH] $REPO_BASE all main"
  else
    echo "deb [arch=$arch signed-by=$KEY_PATH] $REPO_BASE all main" | sudo tee "$REPO_FILE" >/dev/null
  fi
  run sudo apt-get update

  if dpkg -s anydesk >/dev/null 2>&1; then
    log_info "AnyDesk is already installed."
  else
    run sudo apt-get install -y anydesk
  fi

  # The service lets this machine accept AnyDesk connections without anyone logging in
  # locally. Only enable it if that is what you want.
  if [[ "$DRY_RUN" != "true" ]] && ! systemctl cat anydesk.service >/dev/null 2>&1; then
    log_warn "No anydesk.service unit found. Start AnyDesk manually from the applications menu."
  else
    run sudo systemctl enable --now anydesk.service
    if [[ "$DRY_RUN" != "true" ]]; then
      if systemctl is-active --quiet anydesk.service; then
        log_info "anydesk.service is running."
      else
        log_warn "anydesk.service is not running. Check: sudo systemctl status anydesk.service"
      fi
    fi
    log_info "The service accepts connections at boot. Set an unattended-access password in AnyDesk"
    log_info "and review its permissions before relying on it."
  fi
}

install_rpm_hint() {
  if [[ "$UNINSTALL" == "true" ]]; then
    log_info "Remove it with: sudo zypper remove anydesk   (openSUSE)"
    log_info "                sudo dnf remove anydesk      (Fedora / RHEL)"
    return 0
  fi
  log_info "AnyDesk is not in a package repository for this system."
  log_info "1. Download the RPM for your architecture from: $DOWNLOAD_PAGE"
  log_info "2. Install the downloaded file:"
  log_info "     sudo zypper install ./<downloaded-file>.rpm     (openSUSE)"
  log_info "     sudo dnf install ./<downloaded-file>.rpm        (Fedora / RHEL)"
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    -h|--help)   usage; exit 0 ;;
    *)           log_error "Unknown option: $arg (try --help)" ;;
  esac
done

case "$(uname -s)" in
  Darwin)
    install_macos
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      install_debian
    elif command -v zypper >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
      install_rpm_hint
    else
      log_error "No supported package manager found. Download AnyDesk from $DOWNLOAD_PAGE"
    fi
    ;;
  *)
    log_error "Unsupported OS: $(uname -s)"
    ;;
esac

log_info "Done."
