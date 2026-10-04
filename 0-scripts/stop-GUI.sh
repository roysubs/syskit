#!/usr/bin/env bash
# stop-GUI.sh — nerve gas for everything graphical on a Linux box.
#
# For a machine that should be a server: stops X11 and Wayland servers, compositors and window
# managers, desktop sessions, screensavers/lockers, VNC/RDP/NoMachine/TeamViewer/AnyDesk/RustDesk
# agents, desktop helper daemons — and then anything still holding a connection to a display
# socket. Never touches containers, sshd/tmux/screen, audio, your keyring, dbus, or --keep matches.
#
#   stop-GUI.sh            preview, then ask (type KILL)
#   stop-GUI.sh --dry-run  preview only
#   stop-GUI.sh --yes      no prompt
#   stop-GUI.sh --disable  also disable display managers / remote-desktop services and boot to
#                          multi-user.target, so nothing graphical returns after a reboot
#   stop-GUI.sh --sessions also terminate logind graphical sessions (warning: takes tmux/screen
#                          servers started from a desktop terminal with them)
#   stop-GUI.sh --deep     also gvfsd, tracker, xdg-desktop-portal, at-spi, ibus/fcitx
#   stop-GUI.sh --keep RE  spare processes whose name matches RE (extended regex)
#
# Why it exists: closing a VNC/RDP viewer does NOT stop the server. The X server, the whole
# desktop and every app on it keep running headless — forever — eating CPU on the box that's
# supposed to be serving files. And a deadlocked X server ignores a polite TERM.

set -u
ORIG=("$@")
DRY=0 YES=0 DISABLE=0 SESSIONS=0 DEEP=0 KEEP_RE=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY=1 ;;
    --yes|-y) YES=1 ;;
    --disable) DISABLE=1 ;;
    --sessions) SESSIONS=1 ;;
    --deep) DEEP=1 ;;
    --keep) shift; KEEP_RE="${1:-}" ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

if [[ -t 1 ]]; then R=$'\e[31m' Y=$'\e[33m' G=$'\e[32m' B=$'\e[1m' D=$'\e[2m' N=$'\e[0m'; else R='' Y='' G='' B='' D='' N=''; fi
say()  { printf '%s\n' "$*"; }
warn() { printf '%s[!] %s%s\n' "$Y" "$*" "$N"; }

if [[ "$(uname)" == "Darwin" ]]; then
  echo "stop-GUI.sh targets Linux display servers (X11/Wayland) and session management — not applicable on macOS." >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  if [[ $DRY -eq 1 ]]; then
    warn "not root: the preview can only see YOUR processes and display connections. Run with sudo for the real picture."
  else
    say "${D}Needs root to see and stop other users' graphical processes — re-running with sudo.${N}"
    exec sudo "$0" "${ORIG[@]}"
  fi
fi

# ─── what counts as graphical ───────────────────────────────────────────────────────────────
# Matched against the process's executable basename (not comm, which truncates at 15 chars).
RE_SERVERS='^(Xorg|X|Xvfb|Xephyr|Xwayland|Xnest|Xdummy|Xvnc|Xtigervnc|Xtightvnc|Xrealvnc|Xvncserver|x11vnc|wayvnc|Xrdp)$'
RE_COMPOSITORS='^(gnome-shell|mutter|kwin_x11|kwin_wayland|kwin|plasmashell|sway|weston|Hyprland|hyprland|wayfire|river|labwc|cage|xfwm4|openbox|i3|dwm|awesome|bspwm|fluxbox|icewm|xmonad|marco|muffin|cinnamon|budgie-wm|budgie-panel|enlightenment|metacity|compiz|gala|kwin_wayland_wrapper)$'
RE_SESSIONS='^(xfce4-session|gnome-session|gnome-session-binary|plasma_session|startplasma-x11|startplasma-wayland|lxsession|lxqt-session|mate-session|cinnamon-session|startx|xinit|vncserver|tigervncserver|vncsession|xrdp|xrdp-sesman|xrdp-chansrv|Xsession|x-session-manager|dbus-run-session)$'
RE_LOCKERS='^(xscreensaver|xscreensaver-systemd|xss-lock|light-locker|xfce4-screensaver|gnome-screensaver|mate-screensaver|cinnamon-screensaver|i3lock|swaylock|slock|xautolock|hypridle|swayidle|xsecurelock|xlock|physlock)$'
RE_REMOTE='^(vino-server|gnome-remote-desktop-daemon|krfb|krfb-virtualmonitor|nxserver|nxnode|nxagent|nxclient|nxd|teamviewerd|TeamViewer|anydesk|rustdesk|sunshine|x2goagent|x2gostartagent|x2gocleansessions|remote-viewer|chrome-remote-desktop|chrome-remote-desktop-host|remoting_host|xpra|Xpra|waypipe)$'
RE_HELPERS='^(xfce4-panel|xfce4-power-manager|xfce4-notifyd|xfsettingsd|xfdesktop|xfce4-display-settings|polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|lxpolkit|gsd-[a-z-]+|kded5|kded6|kglobalaccel5|kglobalaccel6|plasma-[a-z-]+|kactivitymanagerd|ksmserver|kwalletd5|kwalletd6|dunst|mako|swaybg|waybar|polybar|picom|compton|nm-applet|blueman-applet|pasystray|volumeicon|clipit|parcellite|redshift|gammastep|xbindkeys|sxhkd|xdg-autostart|wrapper-2\.0|panel-[0-9]+-[a-z]+|conky|tint2|lxpanel|lxqt-panel|mate-panel|nautilus|thunar|pcmanfm|dolphin|caja|nemo)$'
RE_DEEP='^(gvfsd|gvfsd-[a-z0-9-]+|gvfs-udisks2-volume-monitor|gvfs-[a-z0-9-]+|tracker-miner-fs-3|tracker-extract-3|tracker-[a-z0-9-]+|xdg-desktop-portal|xdg-desktop-portal-[a-z]+|xdg-document-portal|xdg-permission-store|at-spi2-registryd|at-spi-bus-launcher|ibus-daemon|ibus-[a-z-]+|fcitx|fcitx5|evolution-[a-z-]+|goa-daemon|goa-identity-service|zeitgeist-[a-z]+)$'

# Never, no matter what.
RE_NEVER='^(sshd|sshd-session|ssh|tmux|tmux:.*|screen|SCREEN|systemd|systemd-[a-z]+|init|dbus-daemon|dbus-broker|dbus-broker-launch|pipewire|pipewire-pulse|wireplumber|pulseaudio|gnome-keyring-daemon|ssh-agent|gpg-agent|dockerd|containerd|containerd-shim|containerd-shim-runc-v2|docker-proxy|podman|conmon|crun|runc|lxc-start|lxd|qemu-system-[a-z0-9_]+|libvirtd|virtqemud|smbd|nmbd|winbindd|nfsd|rpc\.[a-z]+|tailscaled|cron|crond|atd)$'

# systemd units: display managers and remote-desktop servers.
RE_UNITS='^(gdm|gdm3|lightdm|sddm|lxdm|xdm|slim|greetd|ly|emptty|nodm|xrdp|xrdp-sesman|x11vnc|vncserver|tigervncserver|vncserver-x11-serviced|teamviewerd|anydesk|rustdesk|chrome-remote-desktop|nxserver|nxnode|sunshine|x2goserver|x2gocleansessions|gnome-remote-desktop|wayvnc|xpra)(@[^.]*)?\.service$'

# ─── discovery ──────────────────────────────────────────────────────────────────────────────
# Every array is initialised: under `set -u`, bash treats a declared-but-never-assigned array
# as unset, and ${#arr[@]} then aborts the script on a machine with nothing to stop.
declare -a KPID=() KUSER=() KNAME=() KWHY=() SKIPPED=()
declare -A SEEN=()
ME=$$; ANC=""; p=$ME
while [[ -n "$p" && "$p" != "0" && "$p" != "1" ]]; do ANC="$ANC $p"; p=$(awk '/^PPid:/{print $2}' /proc/$p/status 2>/dev/null); done

in_container() { grep -qE 'docker|containerd|libpod|lxc|machine\.slice|kubepods|podman' "/proc/$1/cgroup" 2>/dev/null; }
exe_name()     { local e; e=$(readlink "/proc/$1/exe" 2>/dev/null); e=${e% (deleted)}; [[ -n "$e" ]] && basename "$e" || awk '{print $1}' "/proc/$1/comm" 2>/dev/null; }
proc_user()    { stat -c %U "/proc/$1" 2>/dev/null; }

add() { # pid name why
  local pid=$1 name=$2 why=$3
  [[ -n "${SEEN[$pid]:-}" ]] && return
  [[ " $ANC " == *" $pid "* ]] && return
  [[ "$name" =~ $RE_NEVER ]] && return
  [[ -n "$KEEP_RE" && "$name" =~ $KEEP_RE ]] && { SKIPPED+=("$pid $name (--keep)"); SEEN[$pid]=1; return; }
  if in_container "$pid"; then SKIPPED+=("$pid $name (inside a container)"); SEEN[$pid]=1; return; fi
  SEEN[$pid]=1
  KPID+=("$pid"); KUSER+=("$(proc_user "$pid")"); KNAME+=("$name"); KWHY+=("$why")
}

scan_names() {
  local pid name
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    name=$(exe_name "$pid") || continue
    [[ -z "$name" ]] && continue
    if   [[ "$name" =~ $RE_SERVERS ]];     then add "$pid" "$name" "X/Wayland server"
    elif [[ "$name" =~ $RE_COMPOSITORS ]]; then add "$pid" "$name" "compositor / window manager"
    elif [[ "$name" =~ $RE_SESSIONS ]];    then add "$pid" "$name" "session manager / launcher"
    elif [[ "$name" =~ $RE_LOCKERS ]];     then add "$pid" "$name" "screensaver / locker"
    elif [[ "$name" =~ $RE_REMOTE ]];      then add "$pid" "$name" "remote-control agent"
    elif [[ "$name" =~ $RE_HELPERS ]];     then add "$pid" "$name" "desktop helper"
    elif [[ $DEEP -eq 1 && "$name" =~ $RE_DEEP ]]; then add "$pid" "$name" "desktop plumbing (--deep)"
    fi
  done
}

# Anything with an open connection to a display socket is a GUI client, whatever it's called.
scan_sockets() {
  command -v ss >/dev/null || { warn "ss not found — skipping the display-socket sweep"; return; }
  local pid name
  while read -r pid; do
    [[ -z "$pid" || ! -d "/proc/$pid" ]] && continue
    name=$(exe_name "$pid") || continue
    add "$pid" "$name" "connected to an X11/Wayland display"
  done < <(ss -xp 2>/dev/null | grep -E '/tmp/\.X11-unix/X[0-9]+|@/tmp/\.X11-unix/X[0-9]+|/wayland-[0-9]+' | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
}

active_units() { systemctl list-units --type=service --state=active --no-legend --plain 2>/dev/null | awk '{print $1}' | grep -E "$RE_UNITS"; }
graphical_sessions() {
  local id type
  while read -r id _; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    type=$(loginctl show-session "$id" -p Type --value 2>/dev/null)
    [[ "$type" == x11 || "$type" == wayland || "$type" == mir ]] && echo "$id ($type, $(loginctl show-session "$id" -p Name --value 2>/dev/null))"
  done < <(loginctl list-sessions --no-legend 2>/dev/null)
}

load1() { cut -d' ' -f1 /proc/loadavg; }

# ─── preview ────────────────────────────────────────────────────────────────────────────────
say "${B}stop-GUI — nerve gas for everything graphical${N}   $(hostname) · load $(load1) · $(nproc) cores"
say "${D}Why: on a server every graphical process steals CPU from the services you actually want. A VNC/RDP"
say "session you disconnected from is NOT stopped — its X server, desktop and apps run headless forever.${N}"
say
say "${B}In this order:${N}"
say "  1. systemd services — display managers + remote-desktop servers → ${B}stop${N}$([[ $DISABLE -eq 1 ]] && echo " ${R}+ disable, boot to multi-user.target${N}")"
say "  2. logind graphical sessions → $([[ $SESSIONS -eq 1 ]] && echo "${R}terminate${N}" || echo "${D}left alone (add --sessions; it would take tmux/screen started from a desktop terminal)${N}")"
say "  3. processes by name → TERM, 3 s, then KILL: X/Wayland servers, compositors, sessions, lockers, remote agents, helpers$([[ $DEEP -eq 1 ]] && echo ", plumbing")"
say "  4. sweep → anything still connected to an X11/Wayland display socket"
say "  5. stale X locks in /tmp cleaned"
say "${B}Never:${N} containers (by cgroup), sshd/tmux/screen, audio, gnome-keyring/ssh-agent, dbus, smbd/nfsd/docker/tailscaled${KEEP_RE:+, --keep '$KEEP_RE'}"
say

UNITS=$(active_units || true)
SESS=$( [[ $SESSIONS -eq 1 ]] && graphical_sessions || true )
scan_names; scan_sockets

say "${B}Would stop:${N}"
if [[ -n "$UNITS" ]]; then while read -r u; do say "  service   $u"; done <<<"$UNITS"; fi
if [[ -n "$SESS" ]];  then while read -r s; do say "  session   $s"; done <<<"$SESS"; fi
if [[ ${#KPID[@]} -gt 0 ]]; then
  for i in "${!KPID[@]}"; do printf '  %-7s %-10s %-28s %s%s%s\n' "${KPID[$i]}" "${KUSER[$i]}" "${KNAME[$i]}" "$D" "${KWHY[$i]}" "$N"; done
fi
if [[ -z "$UNITS" && -z "$SESS" && ${#KPID[@]} -eq 0 ]]; then say "  ${G}nothing — this machine has no graphical processes running.${N}"; fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then say "${B}Sparing:${N}"; for s in "${SKIPPED[@]}"; do say "  $s"; done; fi
say

[[ $DRY -eq 1 ]] && { say "${D}--dry-run: nothing done.${N}"; exit 0; }
[[ -z "$UNITS" && -z "$SESS" && ${#KPID[@]} -eq 0 && $DISABLE -eq 0 ]] && exit 0
if [[ $YES -ne 1 ]]; then
  if [[ ! -t 0 ]]; then warn "no terminal to confirm on — re-run with --yes"; exit 1; fi
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then warn "you appear to be INSIDE a graphical session (DISPLAY is set). This will kill it. Run from SSH or a tty."; fi
  printf '%sType KILL to proceed: %s' "$B" "$N"; read -r ans; [[ "$ans" == KILL ]] || { say "aborted."; exit 1; }
fi

# ─── act ────────────────────────────────────────────────────────────────────────────────────
LOAD0=$(load1)
if [[ -n "$UNITS" ]]; then
  while read -r u; do
    say "  ${D}\$ systemctl stop $u${N}"; systemctl stop "$u" 2>&1 | sed 's/^/    /'
    if [[ $DISABLE -eq 1 ]]; then say "  ${D}\$ systemctl disable $u${N}"; systemctl disable "$u" 2>&1 | sed 's/^/    /'; fi
  done <<<"$UNITS"
fi
if [[ $DISABLE -eq 1 ]]; then
  say "  ${D}\$ systemctl set-default multi-user.target${N}"; systemctl set-default multi-user.target 2>&1 | sed 's/^/    /'
  say "    ${D}undo later with: systemctl set-default graphical.target && systemctl enable <display-manager>${N}"
fi
if [[ -n "$SESS" ]]; then
  while read -r s; do id=${s%% *}; say "  ${D}\$ loginctl terminate-session $id${N}"; loginctl terminate-session "$id"; done <<<"$SESS"
fi

kill_list() { # signal
  local sig=$1 pid
  for pid in "${KPID[@]}"; do [[ -d "/proc/$pid" ]] && kill "-$sig" "$pid" 2>/dev/null; done
}
if [[ ${#KPID[@]} -gt 0 ]]; then
  say "  ${D}TERM ${#KPID[@]} process(es)…${N}"; kill_list TERM; sleep 3
  left=(); for pid in "${KPID[@]}"; do [[ -d "/proc/$pid" ]] && left+=("$pid"); done
  if [[ ${#left[@]} -gt 0 ]]; then say "  ${D}KILL ${#left[@]} survivor(s): ${left[*]}${N}"; kill_list KILL; sleep 1; fi
fi

# Second sweep: children re-parented or spawned during shutdown.
KPID=(); KUSER=(); KNAME=(); KWHY=(); SEEN=()
scan_names; scan_sockets
if [[ ${#KPID[@]} -gt 0 ]]; then
  say "  ${D}second sweep: ${#KPID[@]} straggler(s)${N}"; kill_list TERM; sleep 2; kill_list KILL
fi

# Stale X locks: an X server that died hard leaves these, and the next one refuses to start.
for lock in /tmp/.X[0-9]*-lock; do
  [[ -e "$lock" ]] || continue
  lpid=$(tr -d ' ' <"$lock" 2>/dev/null)
  if [[ -z "$lpid" || ! -d "/proc/$lpid" ]]; then
    n=${lock#/tmp/.X}; n=${n%-lock}
    rm -f "$lock" "/tmp/.X11-unix/X$n" && say "  ${D}removed stale lock for display :$n${N}"
  fi
done

say
KPID=(); KUSER=(); KNAME=(); KWHY=(); SEEN=()
scan_names; scan_sockets
if [[ ${#KPID[@]} -gt 0 ]]; then
  warn "still running (something restarts them — a user service? try: systemctl --user -M <user>@ list-units | grep -iE 'vnc|desktop'):"
  for i in "${!KPID[@]}"; do printf '  %-7s %-10s %s\n' "${KPID[$i]}" "${KUSER[$i]}" "${KNAME[$i]}"; done
else
  say "${G}Clean: nothing graphical is running.${N}"
fi
say "${D}load: $LOAD0 → $(load1) (the 1-minute average takes a few minutes to settle)${N}"
[[ $DISABLE -eq 0 ]] && say "${D}Note: display managers / remote-desktop services will return at boot. Add --disable to make this permanent.${N}"
