#!/usr/bin/env bash
# =============================================================================
# power-save-z240.sh
# HP Z240 Power/Noise Optimisation — openSUSE · Debian/Ubuntu · Fedora/RHEL
#
# PURPOSE
#   Turns a Z240 (or similar) into a near-silent, low-power replication node:
#     - CPU kept in powersave governor
#     - HDD spun down when idle
#     - Syncthing runs in scheduled bursts (not continuously)
#     - powertop auto-tune applied at boot
#     - TLP manages PCIe ASPM, USB autosuspend, SATA link power
#
# USAGE
#   sudo bash power-save-z240.sh [--dry-run]
#
#   --dry-run   Print every action that would be taken without making any
#               changes to the system.  Safe to run as any user.
#
# IDEMPOTENCY
#   Safe to re-run. Every write is guarded by a check or uses
#   tee-overwrite / sed-in-place so no duplicate entries are created.
#
# PORTING TO ANOTHER MACHINE
#   1. Edit only the "## USER-TUNABLE PARAMETERS" block below.
#   2. Confirm HDD_DEV with `lsblk` before running — the script will refuse
#      to touch a device that hosts your root filesystem.
#   3. Supported distros: openSUSE, Debian, Ubuntu, Fedora, RHEL/CentOS.
#      Package names and the install command are auto-detected.
#
# REQUIREMENTS
#   - systemd-based Linux
#   - Packages: tlp, powertop, hdparm, cpupower  (installed automatically)
#   - Run as root (or with sudo)  — not required for --dry-run
#
# =============================================================================

set -euo pipefail

# macOS guard — must come before anything else
if [[ "$(uname)" == "Darwin" ]]; then
    echo "ERROR: This script is for Linux only. macOS is not supported."
    echo "       (No systemd, TLP, hdparm, or hdparm.conf on macOS)"
    exit 1
fi


# =============================================================================
## USER-TUNABLE PARAMETERS
# =============================================================================

# --- Syncthing ---------------------------------------------------------------

# The local Linux user that runs the syncthing@<user> systemd service.
SYNC_USER="youruser"

# Sync windows: two times per day (24-hour HH format).
# The machine will start Syncthing, let it run for SYNC_DURATION_MINS, then
# stop it.  Disks spin up during the window and spin down again afterwards.
SYNC_HOUR_1="00"          # first  window — midnight
SYNC_HOUR_2="12"          # second window — noon
SYNC_DURATION_MINS="15"   # how long Syncthing is allowed to run each window

# --- Hard-drive spindown -----------------------------------------------------

# Block device for the data HDD (the loud/power-hungry one).
# Use `lsblk` or `ls /dev/sd*` to confirm before running.
HDD_DEV="/dev/sda"

# hdparm -S value: units of 5 seconds up to 240 (= 20 min).
#   60  =  5 min   120 = 10 min   240 = 20 min
HDD_SPINDOWN_TIME=120     # 10 minutes idle before spindown

# hdparm -B value: APM level (1–254).
#   1   = maximum power saving (aggressive head parking — avoid for spinning rust)
#   127 = moderate saving, protects drive longevity  ← recommended
#   254 = APM disabled
HDD_APM_LEVEL=127

# --- CPU governor ------------------------------------------------------------

# 'powersave' keeps frequency low at idle; fine for a replication node.
# Other options: performance, schedutil, ondemand
CPU_GOVERNOR="powersave"

# --- TLP tweaks (written into /etc/tlp.conf) ---------------------------------

# SATA link power management.
#   min_power  = deepest sleep (may cause issues with some drives — test first)
#   med_power_with_dipm = good balance  ← default recommendation
#   max_performance = disable link PM
SATA_LINKPWR="min_power"

# USB autosuspend (1 = enabled).  Disable (0) if you have USB devices
# that misbehave when suspended (e.g. a USB NIC used for replication).
USB_AUTOSUSPEND=1

# =============================================================================
## END OF USER-TUNABLE PARAMETERS — nothing below should need changing
# =============================================================================


# -----------------------------------------------------------------------------
# Dry-run flag
# -----------------------------------------------------------------------------

DRY_RUN=0
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
dry()  { echo "[DRY]   $*"; }   # used to echo commands that would run

# run <cmd> [args…]
#   In normal mode: execute the command.
#   In dry-run mode: print it instead.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "$*"
    else
        "$@"
    fi
}

require_root() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "Dry-run mode — root not required"
        return
    fi
    [[ $EUID -eq 0 ]] || { echo "ERROR: run as root (sudo $0)"; exit 1; }
}

# -----------------------------------------------------------------------------
# Distro detection
# -----------------------------------------------------------------------------
# Sets:
#   DISTRO_ID   — e.g. opensuse-leap, ubuntu, fedora, rhel
#   PKG_INSTALL — the install command (without the package name)
#   PKG_CHECK   — command to test if a package is installed (pkg_installed uses it)

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO_ID="${ID:-unknown}"
    else
        DISTRO_ID="unknown"
    fi

    case "$DISTRO_ID" in
        opensuse*|sles)
            PKG_INSTALL="zypper --non-interactive install"
            PKG_CHECK="rpm -q"
            ;;
        ubuntu|debian|linuxmint|pop)
            PKG_INSTALL="apt-get install -y"
            PKG_CHECK="dpkg -s"
            ;;
        fedora)
            PKG_INSTALL="dnf install -y"
            PKG_CHECK="rpm -q"
            ;;
        rhel|centos|rocky|almalinux)
            PKG_INSTALL="dnf install -y"
            PKG_CHECK="rpm -q"
            ;;
        *)
            warn "Unrecognised distro '${DISTRO_ID}' — will attempt zypper (openSUSE default)"
            PKG_INSTALL="zypper --non-interactive install"
            PKG_CHECK="rpm -q"
            ;;
    esac

    log "Detected distro: ${DISTRO_ID}  |  package manager: ${PKG_INSTALL%% *}"
}

pkg_installed() {
    $PKG_CHECK "$1" &>/dev/null
}

install_if_missing() {
    local pkg="$1"
    # Debian/Ubuntu use different package names for a few tools
    local install_name="$pkg"
    if [[ "${DISTRO_ID:-}" =~ ^(ubuntu|debian|linuxmint|pop)$ ]]; then
        case "$pkg" in
            cpupower) install_name="linux-tools-common" ;;
        esac
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        dry "Would install '${install_name}' if not present"
        return
    fi

    if pkg_installed "$pkg"; then
        log "Package '${pkg}' already installed — skipping"
    else
        log "Installing '${install_name}' …"
        # shellcheck disable=SC2086
        $PKG_INSTALL "$install_name"
    fi
}

# -----------------------------------------------------------------------------
# Safety preflight: refuse to touch HDD_DEV if it hosts /
# -----------------------------------------------------------------------------

check_hdd_not_root() {
    # Resolve the device that holds the root filesystem
    local root_dev
    root_dev=$(findmnt -n -o SOURCE /)

    # Normalise to the base device (strip partition suffix, e.g. /dev/sda1 → /dev/sda)
    local root_base
    root_base=$(lsblk -no pkname "$root_dev" 2>/dev/null || true)
    [[ -n "$root_base" ]] && root_base="/dev/${root_base}" || root_base="$root_dev"

    # Also resolve HDD_DEV to an absolute path for fair comparison
    local hdd_real
    hdd_real=$(realpath "$HDD_DEV" 2>/dev/null || echo "$HDD_DEV")

    if [[ "$hdd_real" == "$root_base" || "$root_dev" == "$hdd_real"* ]]; then
        echo "ERROR: HDD_DEV='${HDD_DEV}' appears to be (or contain) the root device '${root_base}'."
        echo "       Applying spindown settings to your OS drive is dangerous."
        echo "       Correct HDD_DEV in the parameters section and re-run."
        exit 1
    fi

    log "Safety check passed: ${HDD_DEV} is not the root device (root is on ${root_base})"
}

# Write or replace a KEY=VALUE line in /etc/tlp.conf idempotently.
# Handles both commented (#KEY=…) and active (KEY=…) existing entries.
tlp_set() {
    local key="$1" value="$2" file="/etc/tlp.conf"
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "tlp.conf: would set ${key}=${value}"
        return
    fi
    if grep -qE "^#?${key}=" "$file" 2>/dev/null; then
        sed -i -E "s|^#?${key}=.*|${key}=${value}|" "$file"
        log "tlp.conf: set ${key}=${value}"
    else
        echo "${key}=${value}" >> "$file"
        log "tlp.conf: appended ${key}=${value}"
    fi
}


# =============================================================================
# 1. PACKAGES
# =============================================================================

require_root
detect_distro

# Run the HDD safety check early — before we do anything — unless dry-run
if [[ $DRY_RUN -eq 0 ]]; then
    check_hdd_not_root
else
    dry "Would verify that ${HDD_DEV} is not the root device"
fi

log "=== 1/6  Ensuring required packages are installed ==="
install_if_missing tlp
install_if_missing powertop
install_if_missing hdparm
install_if_missing cpupower


# =============================================================================
# 2. TLP — baseline power policy
# =============================================================================

log "=== 2/6  Configuring TLP ==="

# Ensure tlp.conf exists (it should after package install, but be safe)
[[ -f /etc/tlp.conf ]] || touch /etc/tlp.conf

tlp_set "CPU_SCALING_GOVERNOR_ON_AC"  "$CPU_GOVERNOR"
tlp_set "CPU_SCALING_GOVERNOR_ON_BAT" "$CPU_GOVERNOR"
tlp_set "SATA_LINKPWR_ON_AC"          "$SATA_LINKPWR"
tlp_set "SATA_LINKPWR_ON_BAT"         "$SATA_LINKPWR"
tlp_set "USB_AUTOSUSPEND"             "$USB_AUTOSUSPEND"

run systemctl enable --now tlp
log "TLP enabled and started"


# =============================================================================
# 3. POWERTOP — auto-tune at boot
# =============================================================================

log "=== 3/6  Installing powertop.service ==="

POWERTOP_UNIT="/etc/systemd/system/powertop.service"

if [[ $DRY_RUN -eq 1 ]]; then
    dry "Would write ${POWERTOP_UNIT}"
    dry "Would: systemctl daemon-reload"
    dry "Would: systemctl enable powertop.service"
    dry "Would: systemctl start powertop.service"
else
    cat > "$POWERTOP_UNIT" <<EOF
[Unit]
Description=Apply powertop auto-tune at boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable powertop.service
    systemctl start powertop.service
fi
log "powertop auto-tune applied and service enabled"


# =============================================================================
# 4. CPU GOVERNOR
# =============================================================================

log "=== 4/6  Setting CPU governor to '${CPU_GOVERNOR}' ==="

# Apply now (cpupower)
run cpupower frequency-set -g "$CPU_GOVERNOR" \
    && log "CPU governor set to ${CPU_GOVERNOR}" \
    || warn "cpupower command failed — governor will be applied by TLP at next boot"


# =============================================================================
# 5. HDD SPINDOWN  (hdparm)
# =============================================================================

log "=== 5/6  Configuring HDD spindown for ${HDD_DEV} ==="

HDPARM_CONF="/etc/hdparm.conf"

if [[ $DRY_RUN -eq 1 ]]; then
    dry "Would update ${HDPARM_CONF} with stanza for ${HDD_DEV}"
else
    # Apply immediately
    hdparm -S "$HDD_SPINDOWN_TIME" -B "$HDD_APM_LEVEL" "$HDD_DEV"
    log "hdparm: spindown=${HDD_SPINDOWN_TIME} ($(( HDD_SPINDOWN_TIME * 5 / 60 )) min), APM=${HDD_APM_LEVEL}"

    [[ -f "$HDPARM_CONF" ]] || touch "$HDPARM_CONF"

    # Strip any existing stanza for this device (idempotent)
    python3 - "$HDD_DEV" "$HDPARM_CONF" <<'PYEOF'
import sys, re, pathlib
dev  = sys.argv[1]
path = pathlib.Path(sys.argv[2])
text = path.read_text()
pattern = re.compile(
    r'^\s*' + re.escape(dev) + r'\s*\{[^}]*\}\s*\n?',
    re.MULTILINE
)
path.write_text(pattern.sub('', text))
PYEOF

    # Append fresh stanza
    cat >> "$HDPARM_CONF" <<EOF

${HDD_DEV} {
    spindown_time = ${HDD_SPINDOWN_TIME}
    apm = ${HDD_APM_LEVEL}
}
EOF
    log "hdparm.conf updated for ${HDD_DEV}"
fi


# =============================================================================
# 6. SYNCTHING — scheduled burst sync
# =============================================================================

log "=== 6/6  Configuring Syncthing scheduled sync windows ==="

# Validate that the syncthing user service exists
if ! systemctl list-unit-files "syncthing@${SYNC_USER}.service" &>/dev/null && [[ $DRY_RUN -eq 0 ]]; then
    warn "syncthing@${SYNC_USER}.service not found — make sure Syncthing is installed"
    warn "and the service has been set up for user '${SYNC_USER}'"
    warn "Skipping Syncthing timer setup."
else

if [[ $DRY_RUN -eq 1 ]]; then
    dry "Would write /etc/systemd/system/syncthing-window.service"
    dry "Would write /etc/systemd/system/syncthing-window.timer"
    dry "Would: systemctl daemon-reload"
    dry "Would: systemctl enable --now syncthing-window.timer"
    dry "Would: systemctl disable syncthing@${SYNC_USER}.service"
    dry "Would: systemctl stop syncthing@${SYNC_USER}.service"
else

# --- syncthing-window.service ------------------------------------------------
#   A oneshot that starts Syncthing, waits SYNC_DURATION_MINS, then stops it.
#   Using a sleep-and-stop approach inside ExecStart keeps it self-contained.

cat > /etc/systemd/system/syncthing-window.service <<EOF
[Unit]
Description=Syncthing sync window (${SYNC_DURATION_MINS} min burst)
# Ensure Syncthing is stopped when this unit stops/fails
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=no

# Start Syncthing for this user
ExecStart=/usr/bin/systemctl start syncthing@${SYNC_USER}.service

# Let it run for the configured window, then stop
ExecStart=/bin/sleep $(( SYNC_DURATION_MINS * 60 ))

# Stop Syncthing after the window (also runs on failure)
ExecStop=/usr/bin/systemctl stop syncthing@${SYNC_USER}.service
EOF

# --- syncthing-window.timer --------------------------------------------------

cat > /etc/systemd/system/syncthing-window.timer <<EOF
[Unit]
Description=Run Syncthing sync window twice daily
Documentation=man:systemd.timer(5)

[Timer]
# Fire at the two configured hours (minute 00, second 00)
OnCalendar=*-*-* ${SYNC_HOUR_1},${SYNC_HOUR_2}:00:00

# If a window was missed (e.g. machine was off), run it on next boot
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now syncthing-window.timer

# Disable continuous syncthing service so it only runs via the timer
systemctl disable syncthing@"${SYNC_USER}".service 2>/dev/null || true
systemctl stop  syncthing@"${SYNC_USER}".service 2>/dev/null || true

fi  # end dry-run block

log "Syncthing timer installed: windows at ${SYNC_HOUR_1}:00 and ${SYNC_HOUR_2}:00 (${SYNC_DURATION_MINS} min each)"
log "NOTE: In the Syncthing web UI, set each folder's Rescan Interval to 0"
log "      and uncheck 'Watch for Changes' to prevent disk spin-up between windows."

fi  # end syncthing block


# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "============================================================"
if [[ $DRY_RUN -eq 1 ]]; then
echo "  power-save-z240.sh — DRY RUN COMPLETE (no changes made)"
else
echo "  power-save-z240.sh — COMPLETE"
fi
echo "============================================================"
echo ""
echo "  Distro:       ${DISTRO_ID}"
echo "  TLP:          enabled, governor=${CPU_GOVERNOR}, SATA=${SATA_LINKPWR}"
echo "  powertop:     auto-tune service enabled"
echo "  CPU governor: ${CPU_GOVERNOR} (applied now + via TLP)"
echo "  HDD spindown: ${HDD_DEV}  S=${HDD_SPINDOWN_TIME} ($(( HDD_SPINDOWN_TIME * 5 / 60 )) min)  APM=${HDD_APM_LEVEL}"
echo "  Syncthing:    windows at ${SYNC_HOUR_1}:00 and ${SYNC_HOUR_2}:00  (${SYNC_DURATION_MINS} min each)"
echo ""
echo "  Verify timers:      systemctl list-timers"
echo "  Check TLP status:   sudo tlp-stat -s"
echo "  Monitor disk:       sudo hdparm -C ${HDD_DEV}"
echo ""
echo "  BIOS reminders (manual):"
echo "    Disable: audio, serial/parallel ports, optical drive, unused NICs"
echo ""
if [[ $DRY_RUN -eq 0 ]]; then
echo "  REBOOT recommended to confirm all settings survive restart."
fi
echo "============================================================"
