#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10

# backup-rclone-sync.sh — offsite sync of a local folder to any rclone remote.
#
# Safe by default: uses 'rclone copy', which only adds and updates files at the
# destination. It never deletes anything there. --mirror switches to 'rclone sync'
# (deletes files at the destination that are no longer in the source), and asks
# for a typed confirmation first, since that's a destructive, easy-to-regret option.
#
# Usage:
#   backup-rclone-sync.sh <source-dir> <remote:path> [--mirror] [--dry-run]
#   backup-rclone-sync.sh --list-remotes

set -euo pipefail

BOLD="\033[1m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
NC="\033[0m"

print_usage() {
    cat <<EOF
Usage: $(basename "$0") <source-dir> <remote:path> [options]
       $(basename "$0") --list-remotes

Options:
  --mirror     Use 'rclone sync' instead of 'copy': makes the destination an exact
               mirror of the source, DELETING anything at the destination that
               isn't in the source. Asks for a typed confirmation first.
  --dry-run    Show what would happen without transferring or deleting anything.
  -h, --help   Show this help.

Examples:
  $(basename "$0") ~/Documents gdrive:Backups/Documents
  $(basename "$0") ~/Documents gdrive:Backups/Documents --dry-run
  $(basename "$0") --list-remotes
EOF
}

pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else
        echo "No supported package manager found (brew/apt/zypper/dnf)." >&2
        echo "Official installer: curl https://rclone.org/install.sh | sudo bash" >&2
        exit 1
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

if ! command -v rclone &>/dev/null; then
    echo -e "${YELLOW}rclone not found.${NC}"
    read -r -p "Install it now? [Y/n] " yn
    if [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]; then
        pkg_install rclone
    else
        echo "rclone is required. Exiting." >&2
        exit 1
    fi
fi

if [[ "${1:-}" == "--list-remotes" ]]; then
    REMOTES=$(rclone listremotes)
    if [[ -z "$REMOTES" ]]; then
        echo "No rclone remotes configured yet. Set one up with: rclone config"
    else
        echo "Configured remotes:"
        echo "$REMOTES" | sed 's/^/  /'
    fi
    exit 0
fi

SOURCE_DIR="${1:-}"
DEST_REMOTE="${2:-}"
MIRROR=false
DRY_RUN=false
shift 2 2>/dev/null || true
for arg in "$@"; do
    case "$arg" in
        --mirror)  MIRROR=true ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown option: $arg" >&2; print_usage; exit 1 ;;
    esac
done

if [[ -z "$SOURCE_DIR" || -z "$DEST_REMOTE" ]]; then
    print_usage
    exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo -e "${RED}✖ Source directory not found: $SOURCE_DIR${NC}" >&2
    exit 1
fi

if [[ "$DEST_REMOTE" != *:* ]]; then
    echo -e "${RED}✖ Destination doesn't look like 'remote:path' (no colon found): $DEST_REMOTE${NC}" >&2
    exit 1
fi
REMOTE_NAME="${DEST_REMOTE%%:*}:"
if ! rclone listremotes | grep -qxF "$REMOTE_NAME"; then
    echo -e "${RED}✖ No rclone remote named '$REMOTE_NAME'.${NC}" >&2
    echo "Configured remotes:" >&2
    rclone listremotes | sed 's/^/  /' >&2
    echo "Set one up with: rclone config" >&2
    exit 1
fi

RCLONE_CMD=(rclone copy)
MODE_DESC="copy (safe: adds/updates only, never deletes at the destination)"
if $MIRROR; then
    RCLONE_CMD=(rclone sync)
    MODE_DESC="sync (DESTRUCTIVE: deletes anything at the destination not present in the source)"
fi
$DRY_RUN && RCLONE_CMD+=(--dry-run)
RCLONE_CMD+=(--progress --stats=5s "$SOURCE_DIR" "$DEST_REMOTE")

echo -e "${BOLD}Source:${NC}      $SOURCE_DIR"
echo -e "${BOLD}Destination:${NC} $DEST_REMOTE"
echo -e "${BOLD}Mode:${NC}        $MODE_DESC"
$DRY_RUN && echo -e "${YELLOW}Dry run: nothing will actually be transferred or deleted.${NC}"
echo

if $MIRROR && ! $DRY_RUN; then
    echo -e "${RED}${BOLD}--mirror will delete files at the destination that aren't in the source.${NC}"
    read -r -p "Type 'mirror' to confirm, anything else cancels: " confirm
    if [[ "$confirm" != "mirror" ]]; then
        echo "Cancelled."
        exit 1
    fi
fi

echo "Running: ${RCLONE_CMD[*]}"
"${RCLONE_CMD[@]}"

echo
echo -e "${GREEN}✓ Done.${NC}"
