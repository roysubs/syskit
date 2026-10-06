#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Installs Docker on openSUSE (Tumbleweed, Leap) from the official repositories, then:
#   1. installs the docker and docker-compose packages
#   2. enables and starts the docker service (systemctl)
#   3. adds you to the docker group
#   4. runs tests: daemon, hello-world, and a Compose project
# get.docker.com has no openSUSE support, so this uses zypper instead.
# Each change asks first. Run with -y to accept every prompt.
# IDEMPOTENT: safe to run multiple times.

set -u
set -o pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ASSUME_YES=false
[[ "${1:-}" == "-y" ]] && ASSUME_YES=true
FAILS=0

if [[ "$(uname)" != "Linux" ]] || ! command -v zypper &>/dev/null; then
    echo "This script is for openSUSE (zypper). On macOS use setup-docker-desktop-on-macos.sh; on Debian-family Linux use setup-docker-on-deb-variants.sh." >&2
    exit 1
fi

step() { echo -e "\n${BOLD}${CYAN}==> $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✖ $1${NC}" >&2; }

# Ask before a change. Returns 0 for yes (default), 1 for no.
confirm() {
    $ASSUME_YES && return 0
    local reply
    read -r -p "    $1 [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
}

# Run docker directly if this shell is in the docker group, otherwise through sudo.
# A user added to the group needs a new login before the current shell sees it.
dk() {
    if id -nG | grep -qw docker; then docker "$@"; else sudo docker "$@"; fi
}

# --- 1. Packages ---
step "1. Docker and Compose packages"
if rpm -q docker docker-compose &>/dev/null; then
    ok "docker and docker-compose are installed"
elif confirm "Install docker and docker-compose from the openSUSE repositories?"; then
    sudo zypper --non-interactive refresh || { fail "zypper refresh failed."; exit 1; }
    sudo zypper --non-interactive install docker docker-compose || { fail "zypper install failed."; exit 1; }
    ok "Installed docker and docker-compose"
else
    fail "Docker is required for the rest of this script. Stopping."
    exit 1
fi
ok "$(docker --version)"

# --- 2. Service ---
step "2. Docker service (systemctl)"
enabled=$(systemctl is-enabled docker 2>/dev/null)
active=$(systemctl is-active docker 2>/dev/null)
echo "    enabled: ${enabled:-unknown}   active: ${active:-unknown}"
if [[ "$enabled" != enabled || "$active" != active ]]; then
    if confirm "Enable and start the docker service now (sudo systemctl enable --now docker)?"; then
        sudo systemctl enable --now docker
    fi
fi
if systemctl is-active --quiet docker; then
    ok "docker service is running and $(systemctl is-enabled docker 2>/dev/null) at boot"
else
    fail "docker service is not running. Check: sudo journalctl -u docker -n 50"
    exit 1
fi

# --- 3. Group ---
step "3. Docker group"
if id -nG "$USER" | grep -qw docker; then
    ok "$USER is in the docker group"
elif confirm "Add $USER to the docker group (docker without sudo)? Note: this is root-equivalent access."; then
    sudo usermod -aG docker "$USER"
    ok "Added $USER to the docker group"
fi
if id -nG | grep -qw docker; then
    ok "This shell can use docker without sudo"
else
    warn "This shell is not in the docker group yet. Log out and back in; the tests below use sudo for now."
fi

# --- 4. Tests ---
step "4. Tests"

echo "  a) Daemon answers"
if dk info --format '    {{.ServerVersion}} (storage driver: {{.Driver}})' 2>/dev/null; then
    ok "docker info works"
else
    fail "docker info failed"; FAILS=$((FAILS + 1))
fi

echo "  b) hello-world container"
if dk run --rm hello-world >/dev/null 2>&1; then
    ok "hello-world ran"
else
    fail "hello-world failed (check the network and the docker service)"; FAILS=$((FAILS + 1))
fi

echo "  c) Compose project"
if ! docker compose version &>/dev/null; then
    fail "docker compose plugin not found (expected /usr/lib/docker/cli-plugins/docker-compose)"
    FAILS=$((FAILS + 1))
else
    TEST_DIR=$(mktemp -d)
    cat > "$TEST_DIR/compose.yaml" <<'EOF'
services:
  test:
    image: alpine:3
    command: echo "compose test ok"
EOF
    if dk compose -f "$TEST_DIR/compose.yaml" -p syskit-docker-test up --abort-on-container-exit --exit-code-from test 2>&1 | sed 's/^/    /'; then
        ok "docker compose up ran a container"
    else
        fail "docker compose up failed"; FAILS=$((FAILS + 1))
    fi
    dk compose -f "$TEST_DIR/compose.yaml" -p syskit-docker-test down --remove-orphans >/dev/null 2>&1
    rm -rf "$TEST_DIR"
fi

# --- Summary ---
step "Summary"
rpm -q docker docker-compose | sed 's/^/    /'
echo "    service: $(systemctl is-active docker) / $(systemctl is-enabled docker)"
echo "    compose: $(docker compose version 2>/dev/null)"
if (( FAILS == 0 )); then
    ok "All tests passed"
else
    fail "$FAILS test(s) failed"
fi

echo
echo "Tests leave two images behind (hello-world and alpine:3). Remove them with:"
echo "    sudo docker image rm hello-world alpine:3"
echo "If you were just added to the docker group, log out and back in before using docker without sudo."
exit $(( FAILS > 0 ))
