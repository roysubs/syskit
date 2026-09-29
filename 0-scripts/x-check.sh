#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-09
# X11 & Desktop Environment Diagnostic & Control Tool (x-check.sh)
#
# Inspects:
#   - X11 / Wayland installation status and versions
#   - Display managers (LightDM, GDM, SDDM, etc.) and systemd target
#   - Installed desktop environments (XFCE, GNOME, KDE, MATE, LXDE, etc.)
#   - Active X displays, sockets, and session users
#   - Resource usage (CPU%, Memory, PIDs) for X, Desktops, and rogue screensavers
#   - Graceful shutdown / startup interactive controls with [y/N] safety defaults

# --- Colors & Styles ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

print_header() {
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}        X11 & Desktop Environment Diagnostic & Control Tool        ${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -s, --status              Non-interactive status check only (no prompts)
  --stop                    Stop X / Display Manager without prompting
  --start                   Start X / Display Manager without prompting
  --kill-screensavers       Kill rogue screensaver processes (polyhedra, etc.) immediately
  -h, --help                Show this help message and exit
EOF
    exit 0
}

# --- Parse Arguments ---
MODE_INTERACTIVE=true
ACTION_STOP=false
ACTION_START=false
ACTION_KILL_SAVERS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--status)
            MODE_INTERACTIVE=false
            shift
            ;;
        --stop)
            MODE_INTERACTIVE=false
            ACTION_STOP=true
            shift
            ;;
        --start)
            MODE_INTERACTIVE=false
            ACTION_START=true
            shift
            ;;
        --kill-screensavers)
            MODE_INTERACTIVE=false
            ACTION_KILL_SAVERS=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

print_header

# ====================================================================
# 1. INSTALLATION & ENVIRONMENT AUDIT
# ====================================================================
print_section "1. Installation & Environment Audit"

# A. X Server Installation
X_BIN=""
if command -v Xorg &>/dev/null; then
    X_BIN="$(command -v Xorg)"
elif command -v X &>/dev/null; then
    X_BIN="$(command -v X)"
elif [[ -x "/usr/lib/xorg/Xorg" ]]; then
    X_BIN="/usr/lib/xorg/Xorg"
fi

if [[ -n "$X_BIN" ]]; then
    X_VER=$("$X_BIN" -version 2>&1 | grep -E -i 'x.org|xorg|release' | head -n 1 | sed 's/^[[:space:]]*//')
    echo -e "  ${GREEN}✔ X11 Server:${NC}        Installed at ${BOLD}$X_BIN${NC}"
    [[ -n "$X_VER" ]] && echo -e "     ${DIM}Version: $X_VER${NC}"
else
    echo -e "  ${YELLOW}✖ X11 Server:${NC}        Not installed or not in PATH"
fi

# Wayland
if command -v wayland-info &>/dev/null || pgrep -x Xwayland &>/dev/null || [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
    echo -e "  ${CYAN}✔ Wayland:${NC}           Wayland presence detected"
else
    echo -e "  ${DIM}○ Wayland:${NC}           Not active"
fi

# B. Display Managers
INSTALLED_DMS=()
ACTIVE_DM=""
ENABLED_DM=""

for dm in lightdm gdm gdm3 sddm lxdm nodm slim xdm; do
    if command -v "$dm" &>/dev/null || systemctl list-unit-files "$dm.service" &>/dev/null; then
        INSTALLED_DMS+=("$dm")
        if systemctl is-active "$dm" &>/dev/null; then
            ACTIVE_DM="$dm"
        fi
        if systemctl is-enabled "$dm" &>/dev/null; then
            ENABLED_DM="$dm"
        fi
    fi
done

if [[ ${#INSTALLED_DMS[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}✔ Display Managers:${NC}  ${INSTALLED_DMS[*]}"
    if [[ -n "$ACTIVE_DM" ]]; then
        echo -e "     ${GREEN}Active Service:${NC}   ${BOLD}$ACTIVE_DM${NC} (running)"
    else
        echo -e "     ${DIM}Active Service:   None currently running${NC}"
    fi
    if [[ -n "$ENABLED_DM" ]]; then
        echo -e "     ${CYAN}Enabled at Boot:${NC}  $ENABLED_DM"
    fi
else
    echo -e "  ${DIM}○ Display Managers:  None installed${NC}"
fi

# C. Desktop Environments & Window Managers
INSTALLED_DESKTOPS=()

# XFCE
if command -v xfce4-session &>/dev/null || command -v xfwm4 &>/dev/null; then
    xfce_ver=$(xfce4-session --version 2>&1 | head -n 1)
    INSTALLED_DESKTOPS+=("XFCE (${xfce_ver:-detected})")
fi

# GNOME
if command -v gnome-shell &>/dev/null || command -v gnome-session &>/dev/null; then
    gnome_ver=$(gnome-shell --version 2>/dev/null || gnome-session --version 2>/dev/null | head -n 1)
    INSTALLED_DESKTOPS+=("GNOME (${gnome_ver:-detected})")
fi

# KDE Plasma
if command -v plasmashell &>/dev/null || command -v startplasma-x11 &>/dev/null; then
    kde_ver=$(plasmashell --version 2>&1 | head -n 1)
    INSTALLED_DESKTOPS+=("KDE Plasma (${kde_ver:-detected})")
fi

# MATE
if command -v mate-session &>/dev/null; then
    mate_ver=$(mate-session --version 2>&1 | head -n 1)
    INSTALLED_DESKTOPS+=("MATE (${mate_ver:-detected})")
fi

# LXDE / LXQt
if command -v lxsession &>/dev/null; then
    INSTALLED_DESKTOPS+=("LXDE")
fi
if command -v lxqt-session &>/dev/null; then
    INSTALLED_DESKTOPS+=("LXQt")
fi

# Cinnamon
if command -v cinnamon-session &>/dev/null; then
    INSTALLED_DESKTOPS+=("Cinnamon")
fi

# Standalone Window Managers
for wm in openbox i3 bspwm awesome fluxbox dwm xmonad; do
    if command -v "$wm" &>/dev/null; then
        INSTALLED_DESKTOPS+=("WM:$wm")
    fi
done

if [[ ${#INSTALLED_DESKTOPS[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}✔ Desktop Environments:${NC}"
    for d in "${INSTALLED_DESKTOPS[@]}"; do
        echo -e "     - ${BOLD}$d${NC}"
    done
else
    echo -e "  ${YELLOW}○ Desktop Environments:${NC} None detected (pure CLI/headless environment)"
fi

# D. Boot Target
if command -v systemctl &>/dev/null; then
    BOOT_TARGET=$(systemctl get-default 2>/dev/null)
    if [[ "$BOOT_TARGET" == "graphical.target" ]]; then
        echo -e "  ${YELLOW}⚠ System Boot Target:${NC} ${BOLD}graphical.target${NC} (GUI starts automatically on boot)"
    else
        echo -e "  ${GREEN}✔ System Boot Target:${NC} ${BOLD}${BOOT_TARGET:-unknown}${NC} (Headless console boot)"
    fi
fi


# ====================================================================
# 2. RUNTIME STATUS & ACTIVE SESSIONS
# ====================================================================
print_section "2. Runtime Status & Active Displays"

# Check X Server processes
X_PIDS=$(pgrep -f -d ' ' '/Xorg|/X |Xwayland|Xvfb' 2>/dev/null || true)
X_SOCKETS=$(ls -1 /tmp/.X11-unix/ 2>/dev/null | tr '\n' ' ' || true)

X_IS_RUNNING=false
if [[ -n "$X_PIDS" ]] || [[ -n "$ACTIVE_DM" ]]; then
    X_IS_RUNNING=true
fi

if [[ "$X_IS_RUNNING" == true ]]; then
    echo -e "  ${GREEN}● X Server Status:${NC}   ${BOLD}${GREEN}RUNNING${NC}"
    [[ -n "$X_PIDS" ]] && echo -e "  ${CYAN}  X Server PIDs:${NC}     $X_PIDS"
    [[ -n "$X_SOCKETS" ]] && echo -e "  ${CYAN}  Active Sockets:${NC}    $X_SOCKETS (in /tmp/.X11-unix/)"
    
    # Active GUI sessions via loginctl
    if command -v loginctl &>/dev/null; then
        mapfile -t SESSIONS < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')
        if [[ ${#SESSIONS[@]} -gt 0 ]]; then
            echo -e "  ${CYAN}  Login Sessions:${NC}"
            for s in "${SESSIONS[@]}"; do
                s_user=$(loginctl show-session "$s" -p Name --value 2>/dev/null)
                s_type=$(loginctl show-session "$s" -p Type --value 2>/dev/null)
                s_state=$(loginctl show-session "$s" -p State --value 2>/dev/null)
                s_disp=$(loginctl show-session "$s" -p Display --value 2>/dev/null)
                echo -e "     - Session ${BOLD}$s${NC}: User=${BOLD}$s_user${NC}, Type=${BOLD}$s_type${NC}, Display=${BOLD}${s_disp:-none}${NC}, State=$s_state"
            done
        fi
    fi
else
    echo -e "  ${DIM}○ X Server Status:${NC}   ${BOLD}STOPPED${NC} (no active display servers or display managers)"
fi


# ====================================================================
# 3. PROCESS & RESOURCE HUNTER (CPU, RAM, ROGUE SCREENSAVERS)
# ====================================================================
print_section "3. Process & Resource Hunter"

# Known patterns
SCREENSAVER_PATTERNS="polyhedra|highvoltage|glmatrix|antinspect|flurry|xanalogtv|apple2|glslideshow|electricsheep|xscreensaver|xfce4-screensaver|gnome-screensaver|mate-screensaver|kscreenlocker"
X_CORE_PATTERNS="Xorg|Xwayland|Xvfb|lightdm|gdm|gdm3|sddm|lxdm|nodm"
DESKTOP_PATTERNS="xfce4-session|xfwm4|xfce4-panel|xfdesktop|xfsettingsd|gnome-shell|gnome-session|kwin|plasmashell|mate-session|lxsession|cinnamon|openbox|i3|picom|compton"
DESKTOP_DAEMON_PATTERNS="tumblerd|gvfsd|at-spi2-registryd|xfce4-notifyd|polkit-gnome|tracker-miner"

COMBINED_PATTERNS="$SCREENSAVER_PATTERNS|$X_CORE_PATTERNS|$DESKTOP_PATTERNS|$DESKTOP_DAEMON_PATTERNS"

# Collect process details
mapfile -t MATCHED_PIDS < <(pgrep -f -E "$COMBINED_PATTERNS" 2>/dev/null | grep -v "$$" || true)

ROGUE_SAVERS=()
TOTAL_CPU=0
TOTAL_RES_KB=0

printf "${BOLD}%-8s %-10s %-7s %-7s %-10s %-14s %-25s${NC}\n" "PID" "USER" "%CPU" "%MEM" "RAM(MB)" "CATEGORY" "COMMAND"
echo "──────────────────────────────────────────────────────────────────────────────────"

if [[ ${#MATCHED_PIDS[@]} -eq 0 ]]; then
    echo -e "  ${DIM}No active X, desktop, or screensaver processes found.${NC}"
else
    for pid in "${MATCHED_PIDS[@]}"; do
        # Ignore self or ps
        [[ "$pid" == "$$" ]] && continue
        
        proc_info=$(ps -p "$pid" -o pid=,user=,%cpu=,%mem=,rss=,comm=,args= 2>/dev/null || true)
        [[ -z "$proc_info" ]] && continue
        
        r_pid=$(echo "$proc_info" | awk '{print $1}')
        r_user=$(echo "$proc_info" | awk '{print $2}')
        r_cpu=$(echo "$proc_info" | awk '{print $3}')
        r_mem=$(echo "$proc_info" | awk '{print $4}')
        r_rss=$(echo "$proc_info" | awk '{print $5}')
        r_comm=$(echo "$proc_info" | awk '{print $6}')
        r_args=$(echo "$proc_info" | awk '{$1=$2=$3=$4=$5=$6=""; print $0}' | sed 's/^[[:space:]]*//')
        
        # Convert RSS KB to MB
        r_mb=$((r_rss / 1024))
        TOTAL_RES_KB=$((TOTAL_RES_KB + r_rss))
        
        # Add to total CPU (using awk for floating point)
        TOTAL_CPU=$(awk "BEGIN {print $TOTAL_CPU + $r_cpu}")
        
        # Categorize
        category="Desktop"
        color="$NC"
        
        if echo "$r_comm $r_args" | grep -E -q "$SCREENSAVER_PATTERNS"; then
            category="SCREENSAVER!"
            color="${BOLD}${RED}"
            ROGUE_SAVERS+=("$r_pid:$r_comm")
        elif echo "$r_comm $r_args" | grep -E -q "$X_CORE_PATTERNS"; then
            category="X11/Display"
            color="${CYAN}"
        elif echo "$r_comm $r_args" | grep -E -q "$DESKTOP_PATTERNS"; then
            category="Desktop-Env"
            color="${GREEN}"
        elif echo "$r_comm $r_args" | grep -E -q "$DESKTOP_DAEMON_PATTERNS"; then
            category="Daemon"
            color="${DIM}"
        fi
        
        # Truncate command display
        display_cmd="${r_comm}"
        if [[ -n "$r_args" ]] && [[ "$r_args" != "$r_comm" ]]; then
            display_cmd="${r_comm} (${r_args:0:22})"
        fi
        
        printf "${color}%-8s %-10s %-7s %-7s %-10s %-14s %-25s${NC}\n" \
            "$r_pid" "$r_user" "$r_cpu%" "$r_mem%" "${r_mb} MB" "$category" "${display_cmd:0:25}"
    done
    
    echo "──────────────────────────────────────────────────────────────────────────────────"
    TOTAL_RES_MB=$((TOTAL_RES_KB / 1024))
    echo -e "${BOLD}Summary: Total CPU: ${YELLOW}${TOTAL_CPU}%${NC} | Total RAM: ${YELLOW}${TOTAL_RES_MB} MB${NC}"
fi

# Alert on Rogue Screensavers
if [[ ${#ROGUE_SAVERS[@]} -gt 0 ]]; then
    echo -e "\n${BOLD}${RED}🚨 ALERT: ${#ROGUE_SAVERS[@]} Rogue Screensaver Process(es) Detected!${NC}"
    echo -e "${RED}Headless servers running OpenGL screensavers (polyhedra, highvoltage, etc.) waste high CPU rasterizing 3D graphics.${NC}"
    for s in "${ROGUE_SAVERS[@]}"; do
        echo -e "   - PID: ${BOLD}${s%%:*}${NC} (${s##*:})"
    done
fi


# ====================================================================
# 4. ACTION HANDLERS
# ====================================================================

stop_x_session() {
    echo -e "\n${BOLD}${YELLOW}>> Initiating Graceful Shutdown of X & Desktop Sessions...${NC}"
    
    # 1. Terminate screensavers first
    echo -e "  [1/3] Terminating screensavers..."
    pkill -f -E "$SCREENSAVER_PATTERNS" 2>/dev/null || true
    
    # 2. Stop display manager service if running
    if [[ -n "$ACTIVE_DM" ]]; then
        echo -e "  [2/3] Stopping display manager service: ${BOLD}$ACTIVE_DM${NC}..."
        sudo systemctl stop "$ACTIVE_DM" 2>/dev/null || sudo systemctl stop display-manager 2>/dev/null || true
    elif systemctl is-active display-manager &>/dev/null; then
        echo -e "  [2/3] Stopping display-manager.service..."
        sudo systemctl stop display-manager 2>/dev/null || true
    else
        echo -e "  [2/3] No active display manager service found. Stopping standalone X sessions..."
    fi
    
    # 3. Graceful SIGTERM to any remaining Xorg / session processes
    echo -e "  [3/3] Sending graceful termination to remaining desktop processes..."
    pkill -TERM -f -E "$X_CORE_PATTERNS|$DESKTOP_PATTERNS" 2>/dev/null || true
    sleep 2
    
    # Check if still running
    rem_pids=$(pgrep -f -d ' ' '/Xorg|/X |lightdm|gdm|sddm|xfce4-session' 2>/dev/null || true)
    if [[ -n "$rem_pids" ]]; then
        echo -e "  ${YELLOW}Notice: Forcing remaining PIDs: $rem_pids${NC}"
        sudo kill -9 $rem_pids 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ X11 session and desktop processes stopped successfully.${NC}"
}

start_x_session() {
    echo -e "\n${BOLD}${BLUE}>> Starting X11 / Display Manager...${NC}"
    
    # Determine best DM to start
    target_dm="$ENABLED_DM"
    if [[ -z "$target_dm" ]] && [[ ${#INSTALLED_DMS[@]} -gt 0 ]]; then
        target_dm="${INSTALLED_DMS[0]}"
    fi
    
    if [[ -n "$target_dm" ]]; then
        echo -e "Executing: ${BOLD}sudo systemctl start $target_dm${NC}"
        sudo systemctl start "$target_dm"
        sleep 2
        if systemctl is-active "$target_dm" &>/dev/null; then
            echo -e "${GREEN}✅ Display manager ($target_dm) started successfully!${NC}"
        else
            echo -e "${RED}❌ Failed to start $target_dm. Check: systemctl status $target_dm${NC}"
        fi
    elif command -v startx &>/dev/null; then
        echo -e "${YELLOW}No display manager installed. You can start a local X session using 'startx'.${NC}"
    else
        echo -e "${RED}❌ No display manager or startx available to launch X.${NC}"
    fi
}

kill_screensavers_only() {
    echo -e "\n${BOLD}${YELLOW}>> Killing Rogue Screensavers...${NC}"
    pkill -9 -f -E "$SCREENSAVER_PATTERNS" 2>/dev/null || true
    echo -e "${GREEN}✅ Screensaver processes terminated.${NC}"
    
    # Also attempt to disable xscreensaver daemon if running
    if command -v xscreensaver-command &>/dev/null; then
        xscreensaver-command -exit 2>/dev/null || true
    fi
}

# --- Non-Interactive CLI Action Triggers ---
if [[ "$ACTION_STOP" == true ]]; then
    stop_x_session
    exit 0
fi

if [[ "$ACTION_START" == true ]]; then
    start_x_session
    exit 0
fi

if [[ "$ACTION_KILL_SAVERS" == true ]]; then
    kill_screensavers_only
    exit 0
fi

# ====================================================================
# 5. INTERACTIVE CONTROLS
# ====================================================================
if [[ "$MODE_INTERACTIVE" == true ]]; then
    print_section "4. Management & Controls"
    
    if [[ "$X_IS_RUNNING" == true ]] || [[ ${#MATCHED_PIDS[@]} -gt 0 ]]; then
        # 1. Kill Screensavers option (if rogue savers active)
        if [[ ${#ROGUE_SAVERS[@]} -gt 0 ]]; then
            read -r -p "Kill rogue screensavers ONLY (frees up CPU without stopping desktop)? [y/N]: " ans_saver
            if [[ "$ans_saver" =~ ^[Yy]$ ]]; then
                kill_screensavers_only
            fi
        fi
        
        # 2. Stop X option
        read -r -p "Gracefully stop X server and all desktop processes? [y/N]: " ans_stop
        if [[ "$ans_stop" =~ ^[Yy]$ ]]; then
            stop_x_session
            
            # Boot target recommendation for headless servers
            if [[ "$BOOT_TARGET" == "graphical.target" ]]; then
                echo -e "\n${YELLOW}Note: Your boot target is set to 'graphical.target', meaning X will start again on reboot.${NC}"
                read -r -p "Set default boot target to 'multi-user.target' (console only, saves CPU/RAM on reboot)? [y/N]: " ans_target
                if [[ "$ans_target" =~ ^[Yy]$ ]]; then
                    sudo systemctl set-default multi-user.target
                    echo -e "${GREEN}✅ Boot target changed to multi-user.target (console only).${NC}"
                fi
            fi
        fi
    else
        # X is stopped: Offer to start
        read -r -p "X is currently stopped. Do you want to start it up? [y/N]: " ans_start
        if [[ "$ans_start" =~ ^[Yy]$ ]]; then
            start_x_session
        else
            echo -e "${DIM}No changes made.${NC}"
        fi
    fi
fi
