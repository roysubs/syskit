#!/usr/bin/env bash
# =============================================================================
# power-save-z240.sh
# HP Z240 Power/Noise Optimisation — openSUSE (Leap / Tumbleweed)
#
# PURPOSE
#   Turns a Z240 into a near-silent, low-power replication node:
#     - CPU kept in powersave governor
#     - HDD spun down when idle
#     - Syncthing runs in scheduled bursts (not continuously)
#     - powertop auto-tune applied at boot
#     - TLP manages PCIe ASPM, USB autosuspend, SATA link power
#
# USAGE
#   sudo bash power-save-z240.sh
#
# IDEMPOTENCY
#   Safe to re-run. Every write is guarded by a check or uses
#   tee-overwrite / sed-in-place so no duplicate entries are created.
#
# PORTING TO ANOTHER Z240
#   Edit only the "## USER-TUNABLE PARAMETERS" block below.
#   Everything else is derived from those values.
#
# REQUIREMENTS
#   - openSUSE with systemd
#   - Packages: tlp, powertop, hdparm, cpupower  (installed below if missing)
#   - Run as root (or with sudo)
#
# =============================================================================

set -euo pipefail


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
# Helpers
# -----------------------------------------------------------------------------

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }

require_root() {
    [[ $EUID -eq 0 ]] || { echo "ERROR: run as root (sudo $0)"; exit 1; }
}

pkg_installed() { rpm -q "$1" &>/dev/null; }

install_if_missing() {
    local pkg="$1"
    if pkg_installed "$pkg"; then
        log "Package '$pkg' already installed — skipping"
    else
        log "Installing '$pkg' …"
        zypper --non-interactive install "$pkg"
    fi
}

# Write or replace a KEY=VALUE line in /etc/tlp.conf idempotently.
# Handles both commented (#KEY=…) and active (KEY=…) existing entries.
tlp_set() {
    local key="$1" value="$2" file="/etc/tlp.conf"
    if grep -qE "^#?${key}=" "$file" 2>/dev/null; then
        # Replace the existing line (commented or not)
        sed -i -E "s|^#?${key}=.*|${key}=${value}|" "$file"
        log "tlp.conf: set ${key}=${value}"
    else
        # Append
        echo "${key}=${value}" >> "$file"
        log "tlp.conf: appended ${key}=${value}"
    fi
}

write_unit() {
    # write_unit <path> <content>
    # Overwrites the unit file and reloads the daemon.
    local path="$1"; shift
    log "Writing systemd unit: $path"
    tee "$path" > /dev/null <<< "$*"
    # We reload below in a single batch — no-op here.
}


# =============================================================================
# 1. PACKAGES
# =============================================================================

require_root

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

systemctl enable --now tlp
log "TLP enabled and started"


# =============================================================================
# 3. POWERTOP — auto-tune at boot
# =============================================================================

log "=== 3/6  Installing powertop.service ==="

POWERTOP_UNIT="/etc/systemd/system/powertop.service"

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

# Run immediately so we don't need a reboot
systemctl start powertop.service
log "powertop auto-tune applied and service enabled"


# =============================================================================
# 4. CPU GOVERNOR
# =============================================================================

log "=== 4/6  Setting CPU governor to '${CPU_GOVERNOR}' ==="

# Apply now (cpupower)
cpupower frequency-set -g "$CPU_GOVERNOR" \
    && log "CPU governor set to ${CPU_GOVERNOR}" \
    || warn "cpupower command failed — governor will be applied by TLP at next boot"


# =============================================================================
# 5. HDD SPINDOWN  (hdparm)
# =============================================================================

log "=== 5/6  Configuring HDD spindown for ${HDD_DEV} ==="

# Apply immediately
hdparm -S "$HDD_SPINDOWN_TIME" -B "$HDD_APM_LEVEL" "$HDD_DEV"
log "hdparm: spindown=${HDD_SPINDOWN_TIME} ($(( HDD_SPINDOWN_TIME * 5 / 60 )) min), APM=${HDD_APM_LEVEL}"

# Persist via /etc/hdparm.conf
#   We write the whole stanza; if a stanza for this device already exists
#   we remove it first to stay idempotent.
HDPARM_CONF="/etc/hdparm.conf"
[[ -f "$HDPARM_CONF" ]] || touch "$HDPARM_CONF"

# Strip any existing stanza for this device
python3 - "$HDD_DEV" "$HDPARM_CONF" <<'PYEOF'
import sys, re, pathlib
dev  = sys.argv[1]
path = pathlib.Path(sys.argv[2])
text = path.read_text()
# Remove block:  /dev/sdX {\n ... \n}
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


# =============================================================================
# 6. SYNCTHING — scheduled burst sync
# =============================================================================

log "=== 6/6  Configuring Syncthing scheduled sync windows ==="

# Validate that the syncthing user service exists
if ! systemctl list-unit-files "syncthing@${SYNC_USER}.service" &>/dev/null; then
    warn "syncthing@${SYNC_USER}.service not found — make sure Syncthing is installed"
    warn "and the service has been set up for user '${SYNC_USER}'"
    warn "Skipping Syncthing timer setup."
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

log "Syncthing timer installed: windows at ${SYNC_HOUR_1}:00 and ${SYNC_HOUR_2}:00 (${SYNC_DURATION_MINS} min each)"
log "NOTE: In the Syncthing web UI, set each folder's Rescan Interval to 0"
log "      and uncheck 'Watch for Changes' to prevent disk spin-up between windows."

fi  # end syncthing block


# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "============================================================"
echo "  power-save-z240.sh — COMPLETE"
echo "============================================================"
echo ""
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
echo "  REBOOT recommended to confirm all settings survive restart."
echo "============================================================"
