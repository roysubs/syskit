#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10

# net-diag.sh — path tracing and inter-host bandwidth testing.
# Complements sys-bench.sh, which only tests loopback iperf3 and internet speed.

set -uo pipefail

BOLD="\033[1m"
YELLOW="\033[1;33m"
NC="\033[0m"

print_usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  trace <host>          Trace the network path to <host> (mtr if available, else traceroute)
  iperf-server           Start an iperf3 server on this machine (Ctrl-C to stop)
  iperf-client <host>    Run a 10s bandwidth test against an iperf3 server on <host>
  -h, --help             Show this help

On macOS, mtr needs sudo to run in report mode; this script will prefix it with
sudo automatically if mtr is installed. traceroute needs no special privileges.
EOF
}

pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else
        echo "No supported package manager found (brew/apt/zypper/dnf)." >&2
        exit 1
    fi
}

offer_install() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then return 0; fi
    echo -e "${YELLOW}'$cmd' not found.${NC}"
    read -r -p "Install '$pkg'? [Y/n] " yn
    if [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]; then
        pkg_install "$pkg"
    else
        return 1
    fi
}

cmd_trace() {
    local host="${1:-}"
    [[ -z "$host" ]] && { echo "Usage: $(basename "$0") trace <host>" >&2; exit 1; }

    if command -v mtr &>/dev/null || offer_install mtr; then
        echo -e "${BOLD}mtr report to $host:${NC}"
        if [[ "$(uname)" == "Darwin" ]]; then
            sudo mtr --report --report-cycles=10 "$host"
        else
            mtr --report --report-cycles=10 "$host" 2>/dev/null || sudo mtr --report --report-cycles=10 "$host"
        fi
    elif command -v traceroute &>/dev/null; then
        echo -e "${BOLD}traceroute to $host (mtr not installed):${NC}"
        traceroute "$host"
    else
        echo "Neither mtr nor traceroute is available, and mtr install was declined." >&2
        exit 1
    fi
}

cmd_iperf_server() {
    command -v iperf3 &>/dev/null || offer_install iperf3 || { echo "iperf3 is required." >&2; exit 1; }
    echo -e "${BOLD}Starting iperf3 server on this machine. Ctrl-C to stop.${NC}"
    echo "From another host, run: $(basename "$0") iperf-client <this-host's-address>"
    iperf3 -s
}

cmd_iperf_client() {
    local host="${1:-}"
    [[ -z "$host" ]] && { echo "Usage: $(basename "$0") iperf-client <host>" >&2; exit 1; }
    command -v iperf3 &>/dev/null || offer_install iperf3 || { echo "iperf3 is required." >&2; exit 1; }
    echo -e "${BOLD}10s bandwidth test against $host (needs: $(basename "$0") iperf-server running there):${NC}"
    iperf3 -c "$host" -t 10
}

case "${1:-}" in
    trace)         shift; cmd_trace "$@" ;;
    iperf-server)  cmd_iperf_server ;;
    iperf-client)  shift; cmd_iperf_client "$@" ;;
    -h|--help|"")  print_usage ;;
    *)             echo "Unknown command: $1" >&2; print_usage; exit 1 ;;
esac
