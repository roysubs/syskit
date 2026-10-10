#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10

# firewall-baseline.sh — apply a deny-by-default firewall baseline (Linux),
# or turn on the built-in Application Firewall (macOS).
#
# SAFETY: this can lock you out of a remote machine if your SSH port isn't
# detected and allowed correctly. Before applying anything, it:
#   - detects sshd's configured Port line(s) (default 22 if none set)
#   - detects the port THIS SSH session is actually using, if run over SSH
#   - allows the union of both, plus anything you list on the command line
#   - prints the exact plan and requires you to type 'yes' to proceed
#   - supports --dry-run to only print the plan
#
# Even so: keep a second session open, or console/physical access, before
# running this for real on a remote box.
#
# Usage:
#   firewall-baseline.sh [extra-port ...] [--dry-run]

set -uo pipefail

BOLD="\033[1m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
NC="\033[0m"

DRY_RUN=false
EXTRA_PORTS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [extra-port ...] [--dry-run]"
            exit 0
            ;;
        *) EXTRA_PORTS+=("$arg") ;;
    esac
done

detect_ssh_ports() {
    local ports=()
    local sshd_conf=""
    for p in /etc/ssh/sshd_config /usr/local/etc/ssh/sshd_config; do
        [[ -f "$p" ]] && sshd_conf="$p" && break
    done
    if [[ -n "$sshd_conf" ]]; then
        while IFS= read -r p; do ports+=("$p"); done < <(grep -iE '^\s*Port\s+[0-9]+' "$sshd_conf" 2>/dev/null | awk '{print $2}')
    fi
    # The port this session is actually using, if connected over SSH (4th field of SSH_CONNECTION)
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ports+=("$(awk '{print $4}' <<<"$SSH_CONNECTION")")
    fi
    if [[ ${#ports[@]} -eq 0 ]]; then
        ports=(22)
    fi
    printf '%s\n' "${ports[@]}" | sort -un
}

# --- macOS: a different model entirely (per-app, not per-port). Lighter touch. ---
if [[ "$(uname)" == "Darwin" ]]; then
    FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
    echo -e "${BOLD}macOS uses a per-application firewall, not port-based rules.${NC}"
    echo "This can only offer to turn on the built-in Application Firewall:"
    echo "  sudo $FW --setglobalstate on"
    CURRENT=$("$FW" --getglobalstate 2>/dev/null)
    echo "Current state: $CURRENT"
    if $DRY_RUN; then
        echo "(dry run: not changing anything)"
        exit 0
    fi
    read -r -p "Turn it on? [Y/n] " yn
    if [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]; then
        sudo "$FW" --setglobalstate on
    fi
    exit 0
fi

mapfile -t SSH_PORTS < <(detect_ssh_ports)
ALLOW_PORTS=("${SSH_PORTS[@]}" "${EXTRA_PORTS[@]}")

echo -e "${BOLD}Plan:${NC}"
echo "  Default policy:    deny incoming, allow outgoing"
echo "  SSH port(s) found: ${SSH_PORTS[*]}"
[[ ${#EXTRA_PORTS[@]} -gt 0 ]] && echo "  Extra ports:        ${EXTRA_PORTS[*]}"
echo "  Will explicitly allow: ${ALLOW_PORTS[*]}"
echo

if command -v ufw &>/dev/null; then
    BACKEND="ufw"
elif command -v firewall-cmd &>/dev/null; then
    BACKEND="firewalld"
else
    echo -e "${RED}✖ Neither ufw nor firewall-cmd found. Install one first (see check-firewall.sh --tips).${NC}" >&2
    exit 1
fi
echo "  Backend: $BACKEND"
echo

if $DRY_RUN; then
    echo -e "${YELLOW}Dry run: showing commands only, nothing will be changed.${NC}"
    echo
    if [[ "$BACKEND" == "ufw" ]]; then
        echo "sudo ufw default deny incoming"
        echo "sudo ufw default allow outgoing"
        for p in "${ALLOW_PORTS[@]}"; do echo "sudo ufw allow $p"; done
        echo "sudo ufw --force enable"
    else
        echo "sudo systemctl enable --now firewalld"
        echo "sudo firewall-cmd --permanent --add-service=ssh"
        for p in "${EXTRA_PORTS[@]}"; do echo "sudo firewall-cmd --permanent --add-port=${p}/tcp"; done
        echo "sudo firewall-cmd --reload"
    fi
    exit 0
fi

echo -e "${RED}${BOLD}This changes the firewall on this machine. If the SSH port shown above is${NC}"
echo -e "${RED}${BOLD}wrong, you can lock yourself out. Keep a second session open if you can.${NC}"
read -r -p "Type 'yes' to proceed: " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cancelled."
    exit 1
fi

if [[ "$BACKEND" == "ufw" ]]; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    for p in "${ALLOW_PORTS[@]}"; do sudo ufw allow "$p"; done
    sudo ufw --force enable
    sudo ufw status verbose
else
    sudo systemctl enable --now firewalld
    # firewalld's default zone already denies everything not explicitly allowed;
    # this only ensures ssh and any extra ports are in that allow list.
    sudo firewall-cmd --permanent --add-service=ssh
    for p in "${EXTRA_PORTS[@]}"; do sudo firewall-cmd --permanent --add-port="${p}/tcp"; done
    sudo firewall-cmd --reload
    sudo firewall-cmd --list-all
fi

echo
echo -e "${GREEN}✓ Done. Verify you can still reach this machine before closing any other session.${NC}"
