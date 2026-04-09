#!/usr/bin/env bash
# btrfs-snapshot.sh — friendly snapper wrapper for openSUSE
#
# Usage:
#   btrfs-snapshot.sh -save <name> [-desc <description>] [-config <cfg>]
#   btrfs-snapshot.sh -delete <name|snapshot-id>
#   btrfs-snapshot.sh -list [-config <cfg>]
#   btrfs-snapshot.sh -help
#
# Requirements: snapper (pre-installed on openSUSE with Btrfs root)
# Most operations on the root config require sudo / root privileges.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_CONFIG="root"     # snapper config to use (root = / partition)
SCRIPT_NAME="$(basename "$0")"

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
die()     { echo -e "${RED}[error]${RESET} $*" >&2; exit 1; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
require_snapper() {
    command -v snapper &>/dev/null || die "snapper not found. Install it with: sudo zypper in snapper"
}

require_root() {
    [[ $EUID -eq 0 ]] || die "This action requires root privileges. Re-run with sudo."
}

# ── Resolve a snapshot by name (userdata field) or numeric ID ─────────────────
# Prints the numeric snapshot ID, or exits with error.
resolve_snapshot_id() {
    local cfg="$1" needle="$2"

    # If it's purely numeric, trust it directly (but verify it exists)
    if [[ "$needle" =~ ^[0-9]+$ ]]; then
        snapper -c "$cfg" list --columns number \
            | tail -n +2 \
            | grep -qx "[[:space:]]*${needle}[[:space:]]*" \
            || die "Snapshot #${needle} not found in config '${cfg}'."
        echo "$needle"
        return
    fi

    # Otherwise search the userdata field for name=<needle>
    local match
    match=$(snapper -c "$cfg" list \
        | awk -F'|' -v n="$needle" '
            NR > 2 {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)   # id
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $8)   # userdata
                if ($8 ~ "name=" n "(,|$)") print $1
            }')

    local count
    count=$(echo "$match" | grep -c '[0-9]' || true)

    [[ $count -gt 0 ]] || die "No snapshot named '${needle}' found in config '${cfg}'."
    [[ $count -eq 1 ]] || die "Multiple snapshots match '${needle}' — delete by numeric ID instead:\n${match}"

    echo "$match"
}

# ── SAVE ───────────────────────────────────────────────────────────────────────
cmd_save() {
    local name="" desc="" config="$DEFAULT_CONFIG"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -name)    name="$2";   shift 2 ;;
            -desc)    desc="$2";   shift 2 ;;
            -config)  config="$2"; shift 2 ;;
            *) die "Unknown option for -save: $1" ;;
        esac
    done

    [[ -n "$name" ]] || die "-save requires a name. Usage: $SCRIPT_NAME -save <name> [-desc <text>]"

    # Validate: name must be a single word (no spaces, no pipes, no equals)
    [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] \
        || die "Name must contain only letters, numbers, underscores, dots or hyphens."

    # Check for duplicate name in this config
    local existing
    existing=$(snapper -c "$config" list \
        | awk -F'|' -v n="$name" '
            NR > 2 {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $8)
                if ($8 ~ "name=" n "(,|$)") print NR
            }' | wc -l)
    [[ $existing -eq 0 ]] || warn "A snapshot named '${name}' already exists in config '${config}'."

    local userdata="name=${name}"
    local snap_desc="${desc:-Manual snapshot: ${name}}"

    info "Creating snapshot in config '${config}'..."
    local snap_id
    snap_id=$(snapper -c "$config" create \
        --type single \
        --description "$snap_desc" \
        --userdata "$userdata" \
        --print-number)

    ok "Snapshot #${snap_id} created."
    echo -e "  ${BOLD}Name:${RESET}        ${name}"
    echo -e "  ${BOLD}Description:${RESET} ${snap_desc}"
    echo -e "  ${BOLD}Config:${RESET}      ${config}"
    echo -e "  ${BOLD}ID:${RESET}          ${snap_id}"
}

# ── DELETE ─────────────────────────────────────────────────────────────────────
cmd_delete() {
    local target="" config="$DEFAULT_CONFIG"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -config) config="$2"; shift 2 ;;
            *)       target="$1"; shift   ;;
        esac
    done

    [[ -n "$target" ]] || die "-delete requires a name or numeric ID."

    local snap_id
    snap_id=$(resolve_snapshot_id "$config" "$target")

    # Show what we're about to delete
    local snap_info
    snap_info=$(snapper -c "$config" list | awk -F'|' -v id="$snap_id" '
        NR > 2 {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            if ($1 == id) print $0
        }')

    echo -e "${YELLOW}About to permanently delete snapshot #${snap_id}:${RESET}"
    echo "$snap_info"
    echo
    read -rp "Confirm deletion? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { info "Aborted."; exit 0; }

    snapper -c "$config" delete "$snap_id"
    ok "Snapshot #${snap_id} deleted."
}

# ── LIST ───────────────────────────────────────────────────────────────────────
cmd_list() {
    local config="$DEFAULT_CONFIG"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -config) config="$2"; shift 2 ;;
            *) die "Unknown option for -list: $1" ;;
        esac
    done

    info "Snapshots in config '${BOLD}${config}${RESET}':"
    echo

    # Print the full snapper list, then append a cleaner "named snapshots" block
    snapper -c "$config" list

    echo
    echo -e "${BOLD}Named snapshots (created via $SCRIPT_NAME):${RESET}"

    local found=0
    while IFS='|' read -r id type pre date user cleanup desc userdata; do
        # Strip whitespace
        id="${id// /}"; userdata="${userdata// /}"
        [[ "$id" =~ ^[0-9]+$ ]] || continue
        if [[ "$userdata" =~ name=([A-Za-z0-9_.-]+) ]]; then
            local sname="${BASH_REMATCH[1]}"
            date="${date#"${date%%[![:space:]]*}"}"   # ltrim
            date="${date%"${date##*[![:space:]]}"}"   # rtrim
            desc="${desc#"${desc%%[![:space:]]*}"}"
            desc="${desc%"${desc##*[![:space:]]}"}"
            printf "  ${GREEN}%-4s${RESET}  ${BOLD}%-25s${RESET}  %-30s  %s\n" \
                "#${id}" "${sname}" "${date}" "${desc}"
            found=1
        fi
    done < <(snapper -c "$config" list | tail -n +3)

    [[ $found -eq 1 ]] || echo "  (none — use '$SCRIPT_NAME -save <name>' to create one)"
    echo
}

# ── HELP ───────────────────────────────────────────────────────────────────────
cmd_help() {
    cat <<EOF

${BOLD}${SCRIPT_NAME}${RESET} — friendly snapper wrapper for openSUSE Btrfs snapshots

${BOLD}USAGE${RESET}
  $SCRIPT_NAME -save <name> [-desc <text>] [-config <cfg>]
  $SCRIPT_NAME -delete <name|id>           [-config <cfg>]
  $SCRIPT_NAME -list                       [-config <cfg>]
  $SCRIPT_NAME -help

${BOLD}COMMANDS${RESET}
  ${CYAN}-save <name>${RESET}     Create a snapshot tagged with <name>.
                   Name: letters, numbers, underscores, dots, hyphens only.
  ${CYAN}-desc <text>${RESET}     Optional human-readable description (used with -save).
  ${CYAN}-delete <n>${RESET}      Delete snapshot by name or numeric ID. Asks for confirmation.
  ${CYAN}-list${RESET}            List all snapshots; highlights named ones at the bottom.
  ${CYAN}-config <cfg>${RESET}    Snapper config to use (default: root).
                   Run 'snapper list-configs' to see available configs.

${BOLD}EXAMPLES${RESET}
  # Snapshot before a risky config change
  sudo $SCRIPT_NAME -save pre-nginx-edit -desc "Before editing nginx.conf"

  # Snapshot of the home partition (if you have a home snapper config)
  sudo $SCRIPT_NAME -save dotfiles-backup -config home

  # List everything
  sudo $SCRIPT_NAME -list

  # Delete by name
  sudo $SCRIPT_NAME -delete pre-nginx-edit

  # Delete by snapper numeric ID
  sudo $SCRIPT_NAME -delete 42

${BOLD}NOTES${RESET}
  • Snapshots of / require root. Use sudo.
  • This script wraps 'snapper'. Your snapshots are fully visible in
    'sudo snapper list' and YaST → Filesystem Snapshots.
  • To boot from a snapshot (system rollback), reboot and select the
    snapshot from the GRUB menu → "Start Bootloader from a read-only snapshot".
  • Descriptions and names are stored in snapper's own metadata — no
    sidecar files needed.

EOF
}

# ── Entry point ────────────────────────────────────────────────────────────────
require_snapper

[[ $# -gt 0 ]] || { cmd_help; exit 0; }

case "$1" in
    -save)
        require_root
        shift
        # Allow: -save myname [-desc ...] or -save -name myname [-desc ...]
        if [[ $# -gt 0 && "$1" != -* ]]; then
            cmd_save -name "$@"
        else
            cmd_save "$@"
        fi
        ;;
    -delete)
        require_root
        shift
        cmd_delete "$@"
        ;;
    -list)
        shift
        cmd_list "$@"
        ;;
    -help|--help|-h)
        cmd_help
        ;;
    *)
        die "Unknown command: $1\nRun '$SCRIPT_NAME -help' for usage."
        ;;
esac
