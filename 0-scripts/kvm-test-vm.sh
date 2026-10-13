#!/usr/bin/env bash
# kvm-test-vm.sh — stock Linux test machines for netscrew, as KVM virtual machines on this host, each
# with its own address on the LAN (so the Mac, mina and Windows PCs see it like any other
# machine: mDNS, n access <host>, xrdp, Samba…). Official cloud images, nothing pre-configured
# for n — finding what's missing is n's job.
#
#   ./kvm-test-vm.sh [--distro D] [--desktop[=gnome|xfce]] [--password PW]
#                                                        create it, or bring it back up; every
#                                                        step checks first, so a re-run only
#                                                        does what's missing
#   ./kvm-test-vm.sh [--distro D] --status               state and address
#   ./kvm-test-vm.sh [--distro D] --console [lines]      its boot log (or a screenshot)
#   ./kvm-test-vm.sh [--distro D] --destroy              delete the VM and its disk
#   ./kvm-test-vm.sh [--distro D] --fresh                a VM like a fresh desktop install, to test
#                                                        n add: no ssh server, ssh blocked, no keys
#                                                        (named D-fresh; password logins allowed)
#   ./kvm-test-vm.sh [--distro D] --fresh --type-add     "type" n add's one line in it — run as root
#                                                        through the guest agent, no ssh needed
#   ./kvm-test-vm.sh --list                              the test VMs here
#   ./kvm-test-vm.sh --bridge                            put this host on a bridge (br0), so it can
#                                                        reach its own VMs too (once; undoes itself
#                                                        if the network doesn't come back)
#   ./kvm-test-vm.sh --unbridge                          undo that (or a cable given to the VMs)
#
#   D: rocky9 (default) · fedora · debian12 · debian13 · ubuntu24 · opensuse
#
# Each VM: the distro's own defaults (Rocky/Fedora: firewalld on, SELinux enforcing; Debian and
# Ubuntu: no firewall, AppArmor), SSH on with your keys from ~/.ssh/authorized_keys (password
# logins refused), your user name with sudo (password: changeme, or --password; any length — a
# test VM's password-quality checker only warns).
# --desktop adds a desktop (GNOME by default), to test remote-screen paths; it takes a while.
#
# Host: openSUSE, Fedora/RHEL, Debian/Ubuntu/Mint. Needs Intel VT-x / AMD-V on in the BIOS. With a
# wired port the VM joins the LAN directly: through the bridge after --bridge (everything,
# this host included, reaches it), else macvtap (every machine but this host). On a Wi-Fi-only
# host it falls back to libvirt's private network: the VM then isn't visible on the LAN (Wi-Fi
# access points drop traffic from extra MAC addresses; reach it through this host: ssh -J).
set -euo pipefail

DISTRO="rocky9"
DESKTOP=""
PASSWORD="changeme"
ACTION="create"
FRESH=""
LINES=40
while [ $# -gt 0 ]; do
  case "$1" in
    --distro) DISTRO="${2:?--distro needs a name}"; shift ;;
    --distro=*) DISTRO="${1#*=}" ;;
    --password) PASSWORD="${2:?--password needs a value}"; shift ;;
    --password=*) PASSWORD="${1#*=}" ;;
    --fresh) FRESH=1 ;;
    --type-add) ACTION="type-add" ;;
    --desktop) DESKTOP="gnome" ;;
    --desktop=*) DESKTOP="${1#*=}" ;;
    --status|--console|--destroy|--list|--bridge|--unbridge) ACTION="${1#--}"
      if [ "$1" = --console ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then LINES="$2"; shift; fi ;;
    -h|--help) sed -n '2,/^# --desktop adds/p' "$0"; exit 0 ;;
    *) echo "unknown option $1 (--help)" >&2; exit 1 ;;
  esac
  shift
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
skip() { printf '    \033[2m%s (already done)\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

# ─── the distros: image, where it lives, its checksum file, VM type, MAC ───
case "$DISTRO" in
  rocky9|rocky)
    NAME=rocky9; OSV=rocky9; IDX=01
    BASE_URL="https://dl.rockylinux.org/pub/rocky/9/images/x86_64"
    BASE_IMG="Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"; SUMS="$BASE_IMG.CHECKSUM" ;;
  fedora)
    NAME=fedora; IDX=02
    FEDORA_REL=""
    for v in $(curl -fsSL https://dl.fedoraproject.org/pub/fedora/linux/releases/ | grep -oE 'href="[0-9]+/"' | grep -oE '[0-9]+' | sort -rn); do
      BASE_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/$v/Cloud/x86_64/images"
      listing="$(curl -fsSL "$BASE_URL/" 2>/dev/null || true)"
      BASE_IMG="$(grep -oE 'Fedora-Cloud-Base-Generic-[^"<>]+\.x86_64\.qcow2' <<<"$listing" | head -1)"
      SUMS="$(grep -oE 'Fedora-Cloud-[^"<>]+-CHECKSUM' <<<"$listing" | head -1)"
      if [ -n "$BASE_IMG" ] && [ -n "$SUMS" ]; then FEDORA_REL="$v"; break; fi
    done
    [ -n "$FEDORA_REL" ] || die "couldn't find Fedora's cloud image"
    OSV="fedora$FEDORA_REL" ;;
  debian12|debian)
    NAME=debian12; OSV=debian12; IDX=03
    BASE_URL="https://cloud.debian.org/images/cloud/bookworm/latest"
    BASE_IMG="debian-12-genericcloud-amd64.qcow2"; SUMS="SHA512SUMS" ;;
  debian13)
    NAME=debian13; OSV=debian13; IDX=04
    BASE_URL="https://cloud.debian.org/images/cloud/trixie/latest"
    BASE_IMG="debian-13-genericcloud-amd64.qcow2"; SUMS="SHA512SUMS" ;;
  ubuntu24|ubuntu)
    NAME=ubuntu24; OSV=ubuntu24.04; IDX=05
    BASE_URL="https://cloud-images.ubuntu.com/noble/current"
    BASE_IMG="noble-server-cloudimg-amd64.img"; SUMS="SHA256SUMS" ;;
  opensuse|tumbleweed)
    NAME=opensuse; OSV=opensusetumbleweed; IDX=06
    BASE_URL="https://download.opensuse.org/tumbleweed/appliances"
    BASE_IMG="openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2"; SUMS="$BASE_IMG.sha256" ;;
  *) [ "$ACTION" = list ] || die "unknown distro $DISTRO (rocky9, fedora, debian12, debian13, ubuntu24, opensuse)"
     NAME="" ;;
esac

# --fresh: its own VM beside the normal one (D-fresh, its own MAC and screen port), set up the way
# a desktop install leaves it — the ssh server removed and blocked, so n add has everything to do
if [ -n "$FRESH" ] && [ -n "$NAME" ]; then
  NAME="$NAME-fresh"; IDX="1${IDX#0}"
  case "$NAME" in
    rocky9*|fedora*) NOSSH='systemctl disable --now sshd; dnf -y remove openssh-server; firewall-cmd --permanent --remove-service=ssh; firewall-cmd --reload' ;;
    debian*|ubuntu*) NOSSH='systemctl disable --now ssh; DEBIAN_FRONTEND=noninteractive apt-get purge -y openssh-server' ;;
    opensuse*)       NOSSH='systemctl disable --now sshd; zypper --non-interactive remove openssh-server; command -v firewall-cmd && firewall-cmd --permanent --remove-service=ssh && firewall-cmd --reload' ;;
  esac
fi

RAM_MB=4096; CPUS=2; DISK_GB=30
[ -n "$DESKTOP" ] && { RAM_MB=6144; DISK_GB=40; }
MAC="52:54:00:4e:53:${IDX:-00}"   # fixed per distro, so the network settings match this exact card
IMG_DIR="/var/lib/libvirt/images"
CONSOLE_LOG="/var/log/libvirt/qemu/$NAME-console.log"
USER_NAME="$(id -un)"
V="virsh -c qemu:///system"   # the libvirt group is enough; sudo only when it isn't (yet)
$V list >/dev/null 2>&1 || V="sudo virsh -c qemu:///system"

# ─── this host's network, and where its VMs go ───
#   cable only, host on it        → bridge (asked once: this host can then reach its VMs too)
#   Wi-Fi + cable, host on Wi-Fi  → the cable (macvtap); this host reaches them through the router
#   Wi-Fi + cable, host on cable  → asked: bridge, give the cable to the VMs, or leave it
#   Wi-Fi only / no cable in      → libvirt's private network (reach it through this host: ssh -J)
is_wifi() { [ -d "/sys/class/net/$1/wireless" ] || [[ "$1" == wl* ]]; }
is_port() { [ -e "/sys/class/net/$1/device" ] && ! is_wifi "$1"; }   # a real wired port
OUT="$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')"   # how this host gets out
BRIDGE=""; [ -n "$OUT" ] && [ -d "/sys/class/net/$OUT/bridge" ] && BRIDGE="$OUT"
CABLE="${NIC:-}"   # NIC=… overrides: the wired port the VMs use
if [ -z "$CABLE" ]; then
  for d in /sys/class/net/*; do
    n="${d##*/}"
    if is_port "$n" && [ "$(cat "$d/carrier" 2>/dev/null)" = 1 ] && [ ! -e "$d/master" ]; then CABLE="$n"; break; fi
  done
fi
PORT_NO_CABLE=""
for d in /sys/class/net/*; do n="${d##*/}"; is_port "$n" && [ "$(cat "$d/carrier" 2>/dev/null)" != 1 ] && PORT_NO_CABLE="$n"; done
WIFI=""; for d in /sys/class/net/*; do n="${d##*/}"; is_wifi "$n" && { WIFI="$n"; break; }; done
CHOICE_FILE="$HOME/.config/test-vm/network"   # "keep": asked once, and the answer was leave it
RESULT_FILE="/tmp/test-vm-net.result"   # the switch writes its outcome here (world-readable)

have_nm() { command -v nmcli >/dev/null && systemctl is-active --quiet NetworkManager; }
saved_wifi() { nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2 ~ /wireless/ {print $1; exit}'; }

# VMNET: bridge:br0 | direct:<port> | nat — and what it means for reaching the VMs, in words
decide_network() {
  if [ -n "$BRIDGE" ]; then
    VMNET="bridge:$BRIDGE"; REACH="on your LAN through the bridge $BRIDGE — every machine, this one included, reaches it"
  elif [ -n "$CABLE" ] && [ "$OUT" != "$CABLE" ]; then
    VMNET="direct:$CABLE"; REACH="on your LAN through the cable ($CABLE); this host (out through ${OUT:-nothing}) reaches it via your router"
  elif [ -n "$CABLE" ]; then
    VMNET="direct:$CABLE"; REACH="on your LAN through the cable ($CABLE) — every machine but this one ($0 --bridge changes that)"
  else
    VMNET="nat"; REACH="on this host's private network — this host reaches it; from other machines: ssh -J $(hostname) <its address>"
  fi
}

# the question, asked once, when this host uses the cable the VMs would share
ask_about_network() {
  [ -z "$BRIDGE" ] && [ -n "$CABLE" ] && [ "$OUT" = "$CABLE" ] || return 0
  [ -s "$CHOICE_FILE" ] && return 0
  [ -t 0 ] && have_nm || return 0
  local wifi_con; wifi_con="$(saved_wifi)"
  cat <<EOF

  This host reaches the network through its cable ($CABLE). A VM on that same cable is on your
  LAN for every other machine — but not for this host itself: the traffic would have to go out
  and straight back in through the same port, and it never does.

    1) Put this host on a bridge (br0), so everything — this host included — reaches its VMs.
       Recommended. Your connection drops for a few seconds; it undoes itself if it fails.
EOF
  if [ -n "$WIFI" ] && [ -n "$wifi_con" ]; then
    echo "    2) Give the cable to the VMs, and move this host onto Wi-Fi ('$wifi_con' on $WIFI)."
    echo "       This host then reaches its VMs through your router. Undoes itself if Wi-Fi fails."
  elif [ -n "$WIFI" ]; then
    echo "    2) (Give the cable to the VMs and use Wi-Fi: first join a Wi-Fi network on this host.)"
  fi
  echo "    3) Leave it: reach the VMs from other machines only. (Ask again: $0 --bridge)"
  echo
  local a; read -r -p "  Choice [1]: " a </dev/tty || a=3
  case "${a:-1}" in
    1) start_switch bridge ;;
    2) [ -n "$wifi_con" ] || die "join a Wi-Fi network on this host first"; start_switch dedicate ;;
    *) mkdir -p "$(dirname "$CHOICE_FILE")"; echo keep > "$CHOICE_FILE"; echo "    left as it is" ;;
  esac
}

# move an existing VM to where VMs go now (bridge ⇄ cable)
match_vm_network() {
  $V dominfo "$NAME" >/dev/null 2>&1 || return 0
  local x; x="$($V dumpxml --inactive "$NAME")"
  case "$VMNET" in
    bridge:*)
      grep -q "<interface type='direct'>" <<<"$x" || return 0
      echo "    moving $NAME onto the bridge ${VMNET#bridge:} (it restarts)"
      x="$(sed -e "s#<interface type='direct'>#<interface type='bridge'>#" -e "s#<source dev='[^']*' mode='bridge'/>#<source bridge='${VMNET#bridge:}'/>#" <<<"$x")" ;;
    direct:*)
      grep -q "<interface type='bridge'>" <<<"$x" || return 0
      echo "    moving $NAME off the bridge, onto ${VMNET#direct:} (it restarts)"
      x="$(sed -e "s#<interface type='bridge'>#<interface type='direct'>#" -e "s#<source bridge='[^']*'/>#<source dev='${VMNET#direct:}' mode='bridge'/>#" <<<"$x")" ;;
    *) return 0 ;;
  esac
  local f; f="$(mktemp)"; printf '%s\n' "$x" > "$f"
  $V define "$f" >/dev/null; rm -f "$f"
  if [ "$($V domstate "$NAME")" = running ]; then $V destroy "$NAME" >/dev/null; $V start "$NAME" >/dev/null; fi
}

vm_ip() {
  local ip
  ip="$($V domifaddr "$NAME" --source agent 2>/dev/null | awk '$3 == "ipv4" && $4 !~ /^127\./ {split($4, a, "/"); print a[1]; exit}')"
  [ -z "$ip" ] && ip="$($V domifaddr "$NAME" --source lease 2>/dev/null | awk '$3 == "ipv4" {split($4, a, "/"); print a[1]; exit}')"
  if [ -z "$ip" ] && sudo test -s "$CONSOLE_LOG"; then
    ip="$(sudo grep -aoE '(eth0|enp[0-9a-z]+) *\| *True *\| *[0-9.]+' "$CONSOLE_LOG" | tail -n 1 | grep -oE '[0-9.]+$')"
  fi
  printf '%s' "$ip"
}

# the port its screen is on (from libvirt: VMs made before fixed ports got the first free one)
screen_port() { local d; d="$($V vncdisplay "$NAME" 2>/dev/null | grep -oE '[0-9]+$')"; echo $((5900 + ${d:-${IDX#0}})); }

tx_pkts() { $V domstats "$NAME" --interface 2>/dev/null | awk -F= '/net.0.tx.pkts/ {print $2}'; }

# ─── changing this host's network: a bridge, or the cable for the VMs — and back ───
# NetworkManager only (openSUSE, Fedora, RHEL, Ubuntu/Mint desktops). The switch runs detached
# (systemd-run), so it finishes even though an ssh session drops while the address moves, and it
# undoes itself if the network hasn't reached the router within 60 seconds.
start_switch() {   # bridge | dedicate | undo
  have_nm || die "this needs NetworkManager; this host's network is run by something else (see: n host .)"
  local kind="$1" GW sw
  GW="$(ip -o route show default | awk '{print $3; exit}')"
  sw="$(mktemp /tmp/test-vm-net.XXXX.sh)"
  {
    echo '#!/bin/bash'
    echo 'set -u'
    echo 'log() { echo "$(date +%T) $*"; }'
    echo "GW='$GW'"
    # reaches DEV: DEV itself has an IPv4 address and the router answers THROUGH it — not just
    # "the router answers" (Wi-Fi alone passed that, and a bridge with no address looked done)
    echo 'reaches() { for i in $(seq 1 60); do ip -4 -o addr show dev "$1" 2>/dev/null | grep -q inet && ping -c1 -W1 -I "$1" "$GW" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }'
    echo "RESULT=$RESULT_FILE"
    echo 'result() { echo "$*" > "$RESULT"; chmod 644 "$RESULT"; }'
  } > "$sw"
  case "$kind" in
    bridge)
      [ -z "$BRIDGE" ] || { echo "    already on the bridge $BRIDGE"; rm -f "$sw"; return 0; }
      local old hw
      old="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$CABLE" '$2 == d {print $1; exit}')"
      if [ -z "$old" ]; then
        # a half-made bridge from an earlier try left the cable's own profile switched off: use it
        old="$(nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /ethernet/ && $1 !~ /^br0-port-/ {print $1; exit}')"
        [ -n "$old" ] && echo "    (an earlier try left a half-made bridge: starting again from '$old')"
      fi
      [ -n "$old" ] || die "no NetworkManager connection for $CABLE"
      hw="$(cat "/sys/class/net/$CABLE/address")"
      cat >> "$sw" <<EOF
OLD='$old'; NIC='$CABLE'
# a half-made bridge from an earlier try: away first, so this one starts clean
nmcli con delete br0 >/dev/null 2>&1; nmcli con delete "br0-port-\$NIC" >/dev/null 2>&1
# VMs plugged straight into the cable (macvtap) stop the kernel putting it into a bridge
for vm in \$(virsh -c qemu:///system list --name 2>/dev/null); do
  if virsh -c qemu:///system domiflist "\$vm" 2>/dev/null | grep -q " direct .*\$NIC"; then
    log "stopping \$vm (plugged into \$NIC directly): a card in use that way can't join a bridge"
    virsh -c qemu:///system shutdown "\$vm" >/dev/null 2>&1
    for i in \$(seq 1 30); do virsh -c qemu:///system domstate "\$vm" 2>/dev/null | grep -q 'shut off' && break; sleep 1; done
    virsh -c qemu:///system destroy "\$vm" >/dev/null 2>&1
  fi
done
M="\$(nmcli -g ipv4.method con show "\$OLD")"
log "br0 from \$OLD (\$NIC, ipv4 \$M), same MAC $hw — so the router gives the same address"
nmcli con add type bridge ifname br0 con-name br0 bridge.stp no bridge.mac-address '$hw' ipv4.method "\$M" ipv6.method auto connection.autoconnect yes
if [ "\$M" = manual ]; then
  nmcli con mod br0 ipv4.addresses "\$(nmcli -g ipv4.addresses con show "\$OLD")" ipv4.gateway "\$(nmcli -g ipv4.gateway con show "\$OLD")" ipv4.dns "\$(nmcli -g ipv4.dns con show "\$OLD")"
fi
nmcli con add type bridge-slave ifname "\$NIC" master br0 con-name "br0-port-\$NIC" connection.autoconnect yes
nmcli con mod "\$OLD" connection.autoconnect no
nmcli con up "br0-port-\$NIC"; nmcli con up br0
if reaches br0; then
  ip4="\$(ip -4 -o addr show dev br0 | awk '{print \$4; exit}')"
  log "br0 is up (\$ip4) and reaches \$GW — done"; result "ok br0 \$ip4"; exit 0
fi
log "br0 didn't get an address reaching \$GW in 60 s — putting \$OLD back"
nmcli con delete br0 "br0-port-\$NIC"; nmcli con mod "\$OLD" connection.autoconnect yes; nmcli con up "\$OLD"
result "undone br0 got no address that reaches the router — \$NIC is back as it was"; exit 1
EOF
      say "Putting $(hostname) on a bridge (br0, from $CABLE / connection '$old')" ;;
    dedicate)
      local old wifi_con
      old="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$CABLE" '$2 == d {print $1; exit}')"
      wifi_con="$(saved_wifi)"
      [ -n "$old" ] && [ -n "$wifi_con" ] || die "need the cable's connection and a saved Wi-Fi network"
      cat >> "$sw" <<EOF
OLD='$old'; WIFI_CON='$wifi_con'
log "moving this host onto Wi-Fi ('\$WIFI_CON'); the cable ('\$OLD') stays up with no address, for the VMs"
nmcli con mod "\$WIFI_CON" connection.autoconnect yes; nmcli con up "\$WIFI_CON"
nmcli con mod "\$OLD" ipv4.method disabled ipv6.method disabled; nmcli con up "\$OLD"
WIFI_DEV="\$(nmcli -g GENERAL.DEVICES con show "\$WIFI_CON" 2>/dev/null)"
if reaches "\${WIFI_DEV:-\$(ip -o route show default | awk '{print \$5; exit}')}"; then
  log "out through Wi-Fi, reaching \$GW — done"; result "ok wifi \$WIFI_DEV"; exit 0
fi
log "Wi-Fi didn't reach \$GW in 60 s — giving the cable its address back"
nmcli con mod "\$OLD" ipv4.method auto ipv6.method auto; nmcli con up "\$OLD"
result "undone Wi-Fi didn't reach the router — the cable has its address back"; exit 1
EOF
      say "Giving the cable ($CABLE) to the VMs; $(hostname) moves onto Wi-Fi ('$wifi_con')" ;;
    undo)
      local port phys old
      port="$(nmcli -t -f NAME con show | grep -m1 '^br0-port-' || true)"
      if [ -n "$port" ]; then
        phys="${port#br0-port-}"
        old="$(nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /ethernet/ && $1 !~ /^br0-port-/ {print $1; exit}')"
        cat >> "$sw" <<EOF
nmcli con mod '$old' connection.autoconnect yes; nmcli con delete br0 '$port'; nmcli con up '$old'
if reaches '$phys'; then log "back on $phys ('$old')"; result "ok back on $phys, as before"
else log "$phys has no address that reaches the router yet"; result "undone off the bridge, but $phys hasn't reached the router yet — try: nmcli con up '$old'"; fi
EOF
        say "Taking $(hostname) off the bridge, back to $phys ('$old')"
      else
        old="$(nmcli -t -f NAME,TYPE con show | while IFS=: read -r c t; do [[ "$t" == *ethernet* ]] && [ "$(nmcli -g ipv4.method con show "$c")" = disabled ] && { echo "$c"; break; }; done || true)"
        [ -n "$old" ] || { echo "    nothing to undo: not on a bridge, and the cable has its address"; rm -f "$sw"; return 0; }
        cat >> "$sw" <<EOF
nmcli con mod '$old' ipv4.method auto ipv6.method auto; nmcli con up '$old'
log "the cable ('$old') has its address back"; result "ok cable back"
EOF
        say "Giving the cable ('$old') back to $(hostname)"
      fi
      rm -f "$CHOICE_FILE" ;;
  esac
  chmod 755 "$sw"
  if [ -n "${DRY:-}" ]; then echo "    (DRY=1: not run — it would run this)"; cat "$sw"; rm -f "$sw"; exit 0; fi
  echo "    if you're connected over ssh, it drops for a few seconds — reconnect after ~30 s"
  [ "$kind" = undo ] || echo "    if the network doesn't reach the router ($GW) within 60 s, it puts things back by itself"
  rm -f "$RESULT_FILE"
  sudo systemd-run --unit "test-vm-net-$$" --collect bash "$sw" >/dev/null || die "couldn't start the change (sudo refused?)"
  echo "    working on it (up to ~90 s)…"
  local r="" i
  for i in $(seq 1 120); do [ -s "$RESULT_FILE" ] && { r="$(cat "$RESULT_FILE")"; break; }; sleep 1; done
  echo
  case "$r" in
    "ok br0 "*)  echo "  ✓ Done: $(hostname) is on the bridge br0 now, at ${r#ok br0 } — its VMs can join it, and this host reaches them." ;;
    "ok wifi"*)  echo "  ✓ Done: $(hostname) is on Wi-Fi now; the cable is for the VMs." ;;
    ok*)         echo "  ✓ Done: ${r#ok }." ;;
    undone*)     echo "  ✗ It didn't work, so it put things back: ${r#undone }."
                 echo "    What it did, step by step: sudo journalctl -u test-vm-net-$$" ;;
    *)           echo "  ? No answer after 2 minutes (an ssh session that dropped would explain it)."
                 echo "    Look: ip -br addr   ·   what it did: sudo journalctl -u test-vm-net-$$" ;;
  esac
  case "$r" in ok*) echo "    Next: $0 --distro $NAME   (creates the VM, or moves it onto the new network)" ;; esac
  exit 0
}

case "$ACTION" in
  bridge)   start_switch bridge; exit 0 ;;
  unbridge) start_switch undo; exit 0 ;;
esac

# ─── the small actions ───
case "$ACTION" in
  list)
    $V list --all 2>/dev/null | awk 'NR<=2 || /rocky9|fedora|debian1[23]|ubuntu24|opensuse/'
    exit 0 ;;
  status)
    $V dominfo "$NAME" 2>/dev/null | grep -E '^(Name|State|CPU\(s\)|Max memory)' || { echo "$NAME doesn't exist"; exit 0; }
    ip="$(vm_ip || true)"; echo "Address:        ${ip:-unknown (still booting?)}"
    decide_network; echo "Network:        $REACH"
    echo "Its screen:     ssh -L 5900:127.0.0.1:$(screen_port) $(hostname), then vnc://localhost:5900"
    exit 0 ;;
  console)
    if sudo test -s "$CONSOLE_LOG"; then
      sudo tail -n "$LINES" "$CONSOLE_LOG" | tr -d '\r'
    else
      echo "no boot log yet; a screenshot of its screen instead:"
      $V screenshot "$NAME" "/tmp/$NAME-screen.png" >/dev/null && echo "    /tmp/$NAME-screen.png"
    fi
    exit 0 ;;
  type-add)
    # n add's one line, "typed at the machine": run as root through the QEMU guest agent — no
    # ssh needed, which is the point (a fresh VM has none). curl, or wget where there's no curl.
    $V dominfo "$NAME" >/dev/null 2>&1 || die "$NAME doesn't exist — make it first: $0 --distro ${NAME%-fresh}${FRESH:+ --fresh}"
    line='if command -v curl >/dev/null 2>&1; then curl -fsSL netscrew.dev/add | sh; else wget -qO- netscrew.dev/add | sh; fi'
    say "In $NAME, as root: $line"
    pid="$($V qemu-agent-command "$NAME" "{\"execute\":\"guest-exec\",\"arg\":{\"path\":\"/bin/sh\",\"arg\":[\"-c\",\"$line\"],\"capture-output\":true}}" 2>&1 | grep -oE '"pid":[0-9]+' | grep -oE '[0-9]+')" \
      || die "the guest agent didn't answer — is $NAME fully booted? ($0 --distro ${NAME%-fresh} --fresh --status)"
    for i in $(seq 1 240); do
      st="$($V qemu-agent-command "$NAME" "{\"execute\":\"guest-exec-status\",\"arg\":{\"pid\":$pid}}" 2>/dev/null)"
      grep -q '"exited":true' <<<"$st" && break
      sleep 3
    done
    grep -q '"exited":true' <<<"$st" || die "still running after 12 minutes — see: $0 --distro ${NAME%-fresh} --fresh --console"
    for k in out-data err-data; do
      grep -oE "\"$k\":\"[^\"]*\"" <<<"$st" | cut -d'"' -f4 | base64 -d 2>/dev/null || true
    done
    echo "    exit code: $(grep -oE '"exitcode":[0-9]+' <<<"$st" | grep -oE '[0-9]+')"
    ip="$(vm_ip || true)"
    echo
    echo "    Now, from this host:  n add $USER_NAME@${ip:-<its address>}   (its password: $PASSWORD)"
    exit 0 ;;
  destroy)
    say "Deleting $NAME and its disk"
    $V destroy "$NAME" 2>/dev/null || true
    $V undefine "$NAME" --nvram 2>/dev/null || $V undefine "$NAME" 2>/dev/null || true
    sudo rm -f "$IMG_DIR/$NAME.qcow2" "$IMG_DIR/$NAME-seed.iso" "$CONSOLE_LOG"
    echo "    kept the base image: $IMG_DIR/$BASE_IMG"
    exit 0 ;;
esac

# ─── create / bring up ───

# 1. hardware virtualisation
[ -e /dev/kvm ] || die "/dev/kvm is missing: Intel VT-x / AMD-V is off in the BIOS.
    HP desktops: F10 at the HP logo → Advanced → System Options → Virtualization Technology (VTx) → on, save.
    Then run this again."

# 2. the host's tools, by its package manager
say "KVM / libvirt tools"
if command -v zypper >/dev/null; then
  PM="zypper"; PKGS="libvirt qemu-x86 virt-install xorriso"; HAS="rpm -q"
  INSTALL="sudo zypper --non-interactive install --no-recommends"
elif command -v apt-get >/dev/null; then
  PM="apt"; PKGS="qemu-system-x86 qemu-utils libvirt-daemon-system virtinst xorriso"; HAS="dpkg -s"
  INSTALL="sudo apt-get install -y --no-install-recommends"
elif command -v dnf >/dev/null; then
  PM="dnf"; PKGS="qemu-kvm libvirt virt-install xorriso"; HAS="rpm -q"
  INSTALL="sudo dnf install -y"
else
  die "this host has no zypper, apt or dnf — install libvirt, QEMU, virt-install and xorriso by hand"
fi
need=()
for p in $PKGS; do $HAS "$p" >/dev/null 2>&1 || need+=("$p"); done
if [ ${#need[@]} -gt 0 ]; then
  [ "$PM" = apt ] && sudo apt-get update -qq
  $INSTALL "${need[@]}"
else skip "$PKGS"; fi

if ! systemctl is-active --quiet libvirtd && ! systemctl is-active --quiet virtqemud; then
  sudo systemctl enable --now libvirtd
else skip "libvirt running"; fi

if ! id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx libvirt; then
  sudo usermod -aG libvirt "$USER_NAME"
  echo "    added $USER_NAME to the libvirt group — virsh without sudo from your next login"
else skip "$USER_NAME in the libvirt group"; fi

say "Where the VM goes on the network"
ask_about_network          # may change this host's network, and then stops here
decide_network
echo "    $REACH"
[ "$VMNET" = nat ] && [ -n "$PORT_NO_CABLE" ] && echo "    (plug a cable into $PORT_NO_CABLE to put VMs on your LAN instead)"
[ "$VMNET" = nat ] && [ -n "$WIFI" ] && echo "    (Wi-Fi can't carry a VM's own address: access points drop traffic from extra MAC addresses)"
if [ "$VMNET" = nat ]; then
  $V net-info default >/dev/null 2>&1 || die "libvirt's 'default' network is missing (package libvirt-daemon-config-network)"
  $V net-autostart default >/dev/null 2>&1 || true
  $V net-start default >/dev/null 2>&1 || true
fi

# 3. the base image (downloaded once, checked against the distro's own checksum)
say "$NAME cloud image"
sudo mkdir -p "$IMG_DIR"
if [ ! -s "$IMG_DIR/$BASE_IMG" ]; then
  sudo curl -fL --progress-bar -o "$IMG_DIR/$BASE_IMG.part" "$BASE_URL/$BASE_IMG"
  want="$(curl -fsSL "$BASE_URL/$SUMS" | grep -F "$BASE_IMG" | grep -oE '[0-9a-f]{64,128}' | head -1)"
  case "${#want}" in
    64)  have="$(sudo sha256sum "$IMG_DIR/$BASE_IMG.part" | cut -d' ' -f1)" ;;
    128) have="$(sudo sha512sum "$IMG_DIR/$BASE_IMG.part" | cut -d' ' -f1)" ;;
    *)   have="" ;;
  esac
  [ -n "$want" ] && [ "$want" = "$have" ] || { sudo rm -f "$IMG_DIR/$BASE_IMG.part"; die "checksum mismatch (or no checksum found) — run again"; }
  sudo mv "$IMG_DIR/$BASE_IMG.part" "$IMG_DIR/$BASE_IMG"
else skip "$IMG_DIR/$BASE_IMG"; fi

# 4. the VM's own disk: a thin copy on top of the base image
say "Disk"
if [ ! -s "$IMG_DIR/$NAME.qcow2" ]; then
  sudo qemu-img create -q -f qcow2 -F qcow2 -b "$IMG_DIR/$BASE_IMG" "$IMG_DIR/$NAME.qcow2" "${DISK_GB}G"
else skip "$IMG_DIR/$NAME.qcow2"; fi

# 5. first-boot settings (cloud-init): user, keys, the guest agent, the network — and a desktop
say "First-boot settings"
if [ ! -s "$IMG_DIR/$NAME-seed.iso" ]; then
  [ -n "$FRESH" ] || [ -s "$HOME/.ssh/authorized_keys" ] || die "no ~/.ssh/authorized_keys here to give the VM (n ssh copy-id from your own machine first)"
  desktop_cmd=""
  case "$DESKTOP:$NAME" in
    :*) ;;
    gnome:rocky9)    desktop_cmd='dnf -y groupinstall "Server with GUI"' ;;
    xfce:rocky9)     desktop_cmd='dnf -y install epel-release && dnf -y groupinstall Xfce' ;;
    gnome:fedora)    desktop_cmd='dnf -y group install workstation-product-environment' ;;
    xfce:fedora)     desktop_cmd='dnf -y group install xfce-desktop-environment' ;;
    gnome:debian1*)  desktop_cmd='DEBIAN_FRONTEND=noninteractive apt-get install -y task-gnome-desktop' ;;
    xfce:debian1*)   desktop_cmd='DEBIAN_FRONTEND=noninteractive apt-get install -y task-xfce-desktop' ;;
    gnome:ubuntu24)  desktop_cmd='DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop-minimal' ;;
    xfce:ubuntu24)   desktop_cmd='DEBIAN_FRONTEND=noninteractive apt-get install -y xubuntu-core' ;;
    gnome:opensuse)  desktop_cmd='zypper --non-interactive install -t pattern gnome' ;;
    xfce:opensuse)   desktop_cmd='zypper --non-interactive install -t pattern xfce' ;;
    *) die "--desktop is gnome or xfce" ;;
  esac
  tmp="$(mktemp -d)"
  {
    echo "#cloud-config"
    echo "hostname: $NAME"
    echo "users:"
    echo "  - name: $USER_NAME"
    echo "    sudo: ALL=(ALL) ALL"
    echo "    lock_passwd: false"
    echo "    shell: /bin/bash"
    if [ -z "$FRESH" ]; then
      echo "    ssh_authorized_keys:"
      grep -E '^(ssh-|ecdsa-|sk-)' "$HOME/.ssh/authorized_keys" | sed 's/^/      - /'
    else
      echo "ssh_pwauth: true"   # a fresh install takes passwords; n add installs the key
    fi
    echo "chpasswd:"
    echo "  expire: false"
    echo "  users:"
    echo "    - {name: $USER_NAME, password: '$PASSWORD', type: text}"
    echo "write_files:"
    echo "  - path: /etc/security/pwquality.conf.d/90-test-vm.conf"
    echo "    content: |"
    echo "      # a test VM: short passwords are fine — warn, don't refuse"
    echo "      enforcing = 0"
    echo "packages: [qemu-guest-agent]"
    echo "runcmd:"
    echo "  - [systemctl, enable, --now, qemu-guest-agent]"
    [ -n "$FRESH" ] && echo "  - [sh, -c, '$NOSSH']"
    if [ -n "$desktop_cmd" ]; then
      echo "  - [sh, -c, '$desktop_cmd && systemctl set-default graphical.target && reboot']"
    fi
  } > "$tmp/user-data"
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$NAME" "$NAME" > "$tmp/meta-data"
  # the network, said explicitly: DHCP on the card with this MAC (cloud-init's guess can miss)
  printf 'version: 2\nethernets:\n  lan:\n    match:\n      macaddress: "%s"\n    dhcp4: true\n    dhcp6: true\n' "$MAC" > "$tmp/network-config"
  sudo xorriso -as mkisofs -quiet -o "$IMG_DIR/$NAME-seed.iso" -V cidata -J -r "$tmp/user-data" "$tmp/meta-data" "$tmp/network-config"
  rm -rf "$tmp"
else skip "$IMG_DIR/$NAME-seed.iso"; fi

# 6. the VM
say "Virtual machine $NAME"
if ! $V dominfo "$NAME" >/dev/null 2>&1; then
  osv="$OSV"
  virt-install --osinfo list 2>/dev/null | grep -qx "$osv" || osv="linux2022"   # older osinfo-db
  case "$VMNET" in
    bridge:*) net="bridge=${VMNET#bridge:},model=virtio,mac=$MAC" ;;
    direct:*) net="type=direct,source=${VMNET#direct:},source_mode=bridge,model=virtio,mac=$MAC" ;;
    *)        net="network=default,model=virtio,mac=$MAC" ;;
  esac
  sudo virt-install --connect qemu:///system --name "$NAME" --memory "$RAM_MB" --vcpus "$CPUS" \
    --os-variant "$osv" --import \
    --disk "path=$IMG_DIR/$NAME.qcow2,format=qcow2,bus=virtio" \
    --disk "path=$IMG_DIR/$NAME-seed.iso,device=cdrom" \
    --network "$net" \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --serial "pty,log.file=$CONSOLE_LOG" \
    --graphics "vnc,listen=127.0.0.1,port=59$IDX" --noautoconsole
  $V autostart "$NAME" >/dev/null
else
  match_vm_network
  if [ "$($V domstate "$NAME")" != "running" ]; then $V start "$NAME"; else skip "$NAME running"; fi
fi

# 7. its address (first boot installs the guest agent; a desktop adds a long install and a reboot)
say "Waiting for its address"
ip=""; restarted=false
for i in $(seq 1 72); do
  ip="$(vm_ip || true)"; [ -n "$ip" ] && break
  # first boots of some images never bring the network up (they send next to nothing);
  # a restart fixes it — once
  if [ "$i" = 36 ] && [ "$restarted" = false ] && [ "$(tx_pkts)" -lt 100 ] 2>/dev/null; then
    echo "    its network never came up — restarting it once"
    $V destroy "$NAME" >/dev/null; $V start "$NAME" >/dev/null; restarted=true
  fi
  sleep 5
done
if [ -z "$ip" ]; then
  echo "    no address yet — check again: $0 --distro $NAME --status"
  echo "    or see what it's doing: $0 --distro $NAME --console"
  exit 0
fi

cat <<EOF

  [✓] $NAME is up at $ip — $REACH
      Log in: ssh $ip   (your key; sudo password: $PASSWORD — any length is fine: passwd)
      Its screen, if the network breaks: ssh -L 5900:127.0.0.1:$(screen_port) $(hostname), then vnc://localhost:5900
${DESKTOP:+      The $DESKTOP desktop is installing in the background; it reboots into it when done (several minutes).
}
  From your own machine:
      n access $ip             # what it lets in, seen from outside
      n ssh copy-n $ip         # put n on it
      ssh $ip, then: n access . · n host . · n iface · n sys · sudo n sys
EOF
