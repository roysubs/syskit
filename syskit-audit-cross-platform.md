# Cross-Platform Compatibility Guide for syskit scripts

Audit performed: 2026-09-30. This file is both (a) a reference for writing every *future*
syskit script correctly the first time, and (b) a backlog of the specific existing scripts
found to have real cross-platform problems, so they don't need re-discovering.

**Status as of 2026-10-04 (latest)**: The openSUSE apt-only list, the Tier 2 release-asset
list, and the Tier 3 list are all handled — ports where macOS has a native equivalent,
clear skip-with-message elsewhere. Recursive `pkg_install` self-calls (sys-info-basic,
optimal-cpu/disks-policy, enable-wake-on-lan), backticks in a heredoc (enable-wake-on-lan),
and a few pre-existing bugs were fixed too. Changes are uncommitted. Still open: a live
test pass on both machines (see the test list in the conversation), the Debian-only
package-name items that have no verified zypper name, and the `0-scripts/n` history purge.

**Earlier status (2026-10-04)**: Tier 1 (mechanical fixes: openSUSE stray-`apt`-bypass,
macOS Docker-installer gap, GNU-only `sed`/`stat`/`date`, most missing-`brew`-branch gaps)
is done and independently verified. The macOS unconditional-root-re-exec category (12
files) is also fully resolved, including a real cross-platform fix for
`navidrome-radio-podcast.sh` and a new, live-tested `optimal-disks-policy-mac.sh` sibling
script. `remote-access-opensuse.sh` was rewritten to explain what each option does and its
real downside before asking (rather than just doing it) and had a real latent bug fixed
(Samba section never opened the firewall for the share); a genuinely new
`remote-access-mac.sh` sibling was built and live-tested, with two real bugs found and
fixed in the process (see its entry under "Reference implementations" below). **Still
open**: Tier 2 (10 files with hardcoded Linux-only release-asset filenames — needs real
per-project research into each tool's actual Darwin asset naming, not a mechanical fix),
Tier 3 (~20 files assuming `/proc`, `useradd`/`usermod`, `ip`, `hostnamectl` etc. with no
macOS path — needs a judgment pass on which are genuinely meant to run on macOS at all vs.
inherently Linux-server tools like `webmin-10000.sh`), and the openSUSE apt-only backlog
(~35 files, same mechanical pattern as the 17 already fixed, just never applied to this list).

## Scope

syskit scripts should aim to work correctly on:
- **macOS** (Homebrew as the package manager, BSD userland)
- **openSUSE** (Tumbleweed/Leap; zypper, systemd, GNU userland)
- **Debian family** (Debian, Ubuntu, Linux Mint; apt, systemd, GNU userland)
- **RHEL family** (RHEL, CentOS, Rocky, AlmaLinux, Fedora; dnf, systemd, GNU userland)

Not every script needs to support all four — a script whose filename/purpose says it's
Debian-only (`*-debian.sh`) is fine being Debian-only. But a script that doesn't name a
specific OS/distro, or that claims general "Linux" or cross-platform support, should
actually work on all of the above.

## Philosophy: standalone scripts, no shared libraries

The repo owner deliberately does **not** want scripts to `source` a shared helper file.
Every script must be self-contained and runnable on its own. This means the boilerplate
below gets **copy-pasted into each script that needs it**, not factored out into a
`lib.sh` that gets sourced. Yes, this means the same ~10 lines appear in many files —
that's the accepted tradeoff for scripts that work correctly when copied/run individually
with no other dependency.

## Process lessons for running a batched fix pass

Learned while fixing 76 files across two rounds (2026-09-30). These apply regardless of
which specific bug is being fixed:

- **Grep the whole file for every occurrence of the trigger command before calling it
  fixed, not just the one instance you were told about.** This repo has real duplication:
  near-identical launcher scripts copy-pasted across directories (e.g. three
  `start-stack.sh` variants under `0-docker/`), and individual files that have the *same*
  buggy block pasted twice within themselves. A fix applied to only the first occurrence
  found is a plausible-looking but incomplete fix — this happened once in this pass and
  was only caught by an independent re-scan.
- **The same broken command can appear in more than one logical place for different
  reasons.** `usermod -aG docker` showed up both in the expected install block AND in an
  unrelated "fix Docker permissions" remediation block elsewhere in the same file — a fix
  scoped only to "the install logic" missed the second one entirely until a plain
  `grep -n usermod` across the whole file caught it.
- **Verify independently after any batched/delegated fix pass — don't just trust a
  self-reported summary.** Re-running `bash -n` on every touched file is necessary but
  not sufficient (it catches syntax errors, not logic gaps). A cheap, effective second
  pass: grep for the bug's trigger command across every touched file and confirm each hit
  sits inside a guard, rather than assuming "the report said it's fixed."
- **Know whether the code you're fixing runs on the host or somewhere else (e.g. inside a
  Docker container) before applying a host-`uname` branch.** Code destined for
  `docker exec ... /bin/bash -c '...'`, or written to a file that a container's entrypoint
  runs, is always whatever OS the *container* is (almost always Linux) — branching it on
  the host's OS would introduce a bug, not fix one.
- **When a fix requires inventing something you can't verify** (a package name for a
  manager you don't have access to, a repo-registration command modeled on docs but never
  run) — say so explicitly rather than presenting it as equally solid as a verified fix.
  Every such case in this pass got flagged with a caveat rather than silently merged in
  as "done."

## The two systemic bugs found in this audit (read this before writing new install logic)

1. **A `pkg_install()`-style helper exists in the script, but a stray unguarded
   `apt update` / `apt install` line runs before or alongside it anyway** — usually a
   leftover pre-flight check from before multi-distro support was added. Under `set -e`
   (common in this repo) that one bare `apt` call kills the whole script on every
   non-Debian platform, even though the "real" install logic two lines later would have
   worked fine via the helper.
   **Rule: once a script has a `pkg_install()` (or equivalent) helper, EVERY package
   install anywhere in the script must go through it. Grep the finished script for
   `apt|apt-get|zypper|dnf|brew install` outside the helper function before considering
   it done — there should be zero hits.**

   Fixed 2026-09-30 in 17 files across `0-scripts/`, `0-new-system/`, `0-install/`, and
   `0-games/` (`set -e` was **not** touched anywhere — the fix is always to correct the
   script's flow, never to relax safety flags). The pattern broke down into four concrete
   recipes, all still valid guidance for any future script:
   - **Redundant stray call → delete it.** If the stray `apt update`/`apt upgrade` only
     duplicated what the apt branch of `pkg_install()` already does internally, just
     remove it (e.g. `x-forwarding.sh`, `fangband-get.sh`, `0-classic-games1.sh`).
   - **Apt-specific logic that's still needed → guard it.** A cache-freshness check or
     similar apt-only pre-flight step that has no equivalent need on other managers gets
     wrapped in `if command -v apt &>/dev/null; then ... fi` rather than deleted (e.g.
     `new2-dev-package-managers.sh`, `cavez-of-phear-get.sh`, `zork1-with-frotz.sh`,
     `new2-tailscale.sh`, `cloud-dropbox-get.sh`).
   - **A specific package install hand-rolled with `apt install -y pkgname` → route it
     through the helper instead**: `sudo apt install -y caca-utils` becomes
     `pkg_install caca-utils` (e.g. `sys-info-mac.sh`, `convert-image-to-ascii-art.sh`).
   - **A *second*, parallel detection function exists that never got a zypper branch**
     (common when a script has both a generic `pkg_install()` AND its own
     `install_dependencies()`/`check_and_install_dependency()` for a specific tool) — add
     the missing `elif command -v zypper &>/dev/null; then pkg_install ...` case to it,
     matching the style of its existing apt/dnf/pacman branches, rather than leaving it to
     silently skip on openSUSE (e.g. `infra-arcana-get.sh`, `2048-compile.sh`).

   **Caveat worth knowing**: when the fix requires inventing package names for a manager
   that previously had none (as in `infra-arcana-get.sh`, which needed real openSUSE SDL2
   package names), verify on an actual openSUSE box rather than assuming — see the zypper
   capability-search note below.

2. **~20 Docker launcher scripts all copy-pasted the same `curl get.docker.com | sh` +
   `usermod -aG docker "$USER"` install block with no macOS branch.** `usermod` doesn't
   exist on macOS at all, and Linux's Docker Engine installer doesn't apply there — macOS
   needs Docker Desktop. See the `ensure_docker` template below.

   Fixed 2026-09-30 in 26 files under `0-docker/` (`set -e` untouched everywhere, same
   rule as bug #1). Two things worth carrying forward into every future fix of this shape:

   - **A file can have the buggy block more than once.** This repo has several
     near-duplicate launcher scripts (e.g. `0-graf/start-stack.sh`,
     `0-graf/1/start-stack.sh`, and `0-grafana-prometheus/start-stack.sh` are
     near-identical to each other), and individually some files have the SAME install
     block copy-pasted twice within themselves. Grep the whole file for every occurrence
     of the trigger string (`usermod -aG docker`, or whatever the bug's signature command
     is) before calling a file done — fixing only the first hit and missing a second,
     later one in the same file is a real mistake that happened during this fix and was
     only caught by an independent re-scan afterward.
   - **`usermod`/`newgrp` can also show up in a *separate* "fix Docker permissions"
     remediation block, not just the install block.** `docker-nginx-test-8888.sh` had a
     second, unrelated `sudo usermod -aG docker $USER` inside a "Docker permission
     denied, attempting to fix" section triggered whenever `docker info` fails — this is
     a Linux-only remedy (Docker Desktop for macOS doesn't use the Unix
     group/socket-permission model at all; if `docker info` fails there it's virtually
     always because Docker Desktop isn't running, and the right message is "start Docker
     Desktop," not a group-membership fix). When auditing for this bug class, search for
     the trigger command by itself across the *whole* file, not just within the install
     function you already know about.

## Standard boilerplate to paste into new scripts

### Bash version guard (already near-universal in this repo — keep it)

```bash
#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
```

Note: this is a deliberate repo-wide policy choice — require bash 4+ and tell the user to
`brew install bash` rather than writing defensive bash-3.2-compatible code. (This differs
from the older "Summary A: avoid Bash 4+ features" advice in `macos-compatibility.md`,
which predates this convention becoming standard. If you're touching a script that still
follows Summary A style, it's fine to leave as-is, but new scripts should use the
bash-4-required guard — it's simpler than writing around 3.2's limitations, and
`brew install bash` is a one-time, one-line fix for the user.)

### Package installer — for packages with the SAME name across managers

Use this when the package name is identical everywhere (curl, git, wget, tmux, htop, jq,
etc.):

```bash
pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need brew/apt/zypper/dnf)." >&2; exit 1
    fi
}
```

### Package installer — when the package name DIFFERS per manager

Do **not** call the generic `pkg_install()` with a Debian-specific name like
`build-essential` or `fonts-powerline` — it will silently fail to find that name on
zypper/dnf/brew. This was a real bug found in the audit (`cloud-onedrive-get.sh`,
`prompt-zsh-and-powerlevel10k.sh`, `switch-desktop-environment.sh`). Instead, branch
explicitly:

```bash
install_build_tools() {
    if command -v brew &>/dev/null; then
        brew install gcc make  # Xcode CLT normally covers this; adjust as needed
    elif command -v apt &>/dev/null; then
        sudo apt update -qq && sudo apt install -y build-essential
    elif command -v zypper &>/dev/null; then
        sudo zypper --non-interactive install -y -t pattern devel_basis
    elif command -v dnf &>/dev/null; then
        sudo dnf groupinstall -y "Development Tools"
    else
        echo "No supported package manager found." >&2; exit 1
    fi
}
```

### Docker installer (fixes the #1 macOS systemic bug)

```bash
ensure_docker() {
    if command -v docker &>/dev/null; then return 0; fi
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/" >&2
        echo "(or: brew install --cask docker)" >&2
        exit 1
    else
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker "$USER"
        echo "Docker installed. Log out and back in for group membership to take effect."
    fi
}
```

### Portable `sed -i`

```bash
portable_sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then sed -i '' "$@"
    else sed -i "$@"
    fi
}
# usage: portable_sed_i 's/old/new/' file.txt
```

**Caveat confirmed 2026-09-30**: only branch on host `uname` when the `sed -i` call
actually runs *on the host*. Several media-stack scripts build a heredoc that gets written
to a file and later executed *inside a Docker container* via `docker exec ... /bin/bash -c
'...'` — that code is always Linux regardless of the host OS, so branching it on host
`uname` would be wrong (it would apply BSD sed syntax inside a container that only has GNU
sed). Check whether code you're "fixing" runs on the host or inside a container before
applying any of these patterns.

### Portable `stat` (file size / owner / mtime)

```bash
file_size() {
    if [[ "$(uname)" == "Darwin" ]]; then stat -f%z "$1"
    else stat -c%s "$1"
    fi
}
file_owner_uid() {
    if [[ "$(uname)" == "Darwin" ]]; then stat -f%u "$1"
    else stat -c%u "$1"
    fi
}
file_mtime_epoch() {
    # GNU `stat -c%Y` and BSD `stat -f%m` are the verified equivalent pair for mtime-as-epoch
    if [[ "$(uname)" == "Darwin" ]]; then stat -f%m "$1"
    else stat -c%Y "$1"
    fi
}
```

### Portable `date -d` / epoch conversion

```bash
# Parsing an EPOCH (simplest case - prefer this form when you already have a Unix timestamp):
# GNU: date -d "@$epoch" +FORMAT   |   BSD/macOS: date -r "$epoch" +FORMAT
epoch_to_date() {
    local epoch="$1" fmt="$2"
    if [[ "$(uname)" == "Darwin" ]]; then date -r "$epoch" +"$fmt"
    else date -d "@$epoch" +"$fmt"
    fi
}

# Parsing an arbitrary DATE STRING in a known format (more fiddly - BSD date needs the
# exact input format given via -f, and -u must come BEFORE -f to apply, not after):
# GNU: date -d "2024-01-01" +%s   |   BSD/macOS: date -j -f "%Y-%m-%d" "2024-01-01" +%s
epoch_from_date() {
    if [[ "$(uname)" == "Darwin" ]]; then date -j -f "%Y-%m-%d" "$1" +%s
    else date -d "$1" +%s
    fi
}
```

**Caveat confirmed 2026-09-30**: `git show --date=iso-strict` produces timestamps like
`2026-09-30T13:36:18+01:00` — BSD `date -j -f "%Y-%m-%dT%H:%M:%S%z"` rejects the colon in
the `+01:00` UTC offset (it wants `+0100`) and will silently fail to parse otherwise.
Strip it first: `sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/'`. This is the kind of thing
that's easy to get subtly wrong without testing against a real timestamp on a real Mac —
when in doubt, test the actual `date`/`stat` invocation live rather than trust a
generic-looking fix.

### OS/arch tag for release-asset downloads

Audit found many `*-get.sh` scripts hardcoding a Linux-only asset filename
(`linux_amd64`, `x86_64-unknown-linux-gnu.tar.gz`) with no Darwin case at all. Always
branch on `uname -s`, not just `uname -m`:

```bash
os_tag() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        *) echo "unknown"; return 1 ;;
    esac
}
arch_tag() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) echo "unknown"; return 1 ;;
    esac
}
# then build the release URL from $(os_tag)/$(arch_tag) instead of a hardcoded string
```

## Platform gotcha reference table

| Thing | Linux (GNU) | macOS (BSD) | Notes |
|---|---|---|---|
| `sed -i 'expr' file` | works as-is | **fails** — needs `sed -i '' 'expr' file` | see `portable_sed_i` above |
| `stat -c%s file` | works | **fails** — needs `stat -f%z file` | see `file_size` above |
| `date -d STR +%s` | works | **fails** — needs `date -j -f FORMAT STR +%s` | see `epoch_from_date` above |
| `readlink -f path` | works | missing on stock macOS | avoid, or check `command -v` first |
| `realpath -e path` | works | `-e` flag not supported by BSD realpath | drop `-e`, check existence separately |
| Package manager | apt / zypper / dnf | **only** `brew` — no apt/dnf/zypper exist | see `pkg_install` above |
| Service manager | `systemctl` (systemd) | **no systemd at all** — uses `launchd`/`launchctl` | a script that only ever calls `systemctl` will hard-fail on macOS with no error explaining why |
| User/group management | `useradd`, `groupadd`, `usermod` | **none exist** — use `dscl` | don't assume these commands exist cross-platform |
| `/proc`, `/sys` | present | **do not exist** | scripts reading `/proc/cpuinfo`, checking `/proc/$pid`, etc. need a macOS branch (e.g. `sysctl`, `ps`) |
| Network config | `ip addr`, `ip route` | **no `ip` command** — use `ifconfig`, `netstat -rn`, `networksetup` | see the `ping-subnet-new.ps1` fix earlier in this repo's history for a worked example |
| Hostname | `hostnamectl` | **doesn't exist** — use `scutil --set HostName` | |
| Disk/mount listing | `lsblk`, `findmnt`, `blkid` | **do not exist** (util-linux only) | no direct BSD equivalent; needs a genuinely different approach (`diskutil`, `mount`) |
| Firewall | `ufw`, `firewalld` | neither exists | macOS firewall is `pfctl`/System Settings, not scriptable the same way |
| Docker install | `get.docker.com` script installs Docker Engine | **no Docker Engine for Mac** — needs Docker Desktop | see `ensure_docker` above |
| Docker `network_mode: host` | works natively | **effectively non-functional** under Docker Desktop for Mac | flag any compose file using this for macOS users |
| netcat listen flags | `nc -l -p PORT -q 1` (GNU netcat syntax) | BSD `nc` doesn't support `-p`/`-q` the same way | check `nc -h` output, or just avoid netcat for anything nontrivial |

## Package-manager coverage notes (openSUSE specifically)

- openSUSE uses `zypper`, not `apt`/`dnf` — a script that only checks
  `apt-get`/`dnf`/`pacman` (several `detect_package_manager()` functions in this repo do
  exactly this) will hit its "unsupported package manager" branch and exit, even though
  zypper support would have been trivial to add.
- Debian-style package names are **not** universal. Known mismatches found in this audit:
  `build-essential` (use `zypper install -t pattern devel_basis`), `fonts-powerline` /
  `fonts-font-awesome` (different package names on openSUSE), `task-gnome-desktop` /
  `task-xfce-desktop` (tasksel is Debian-only; openSUSE uses patterns:
  `zypper install -t pattern gnome`), `libcurl4-openssl-dev` /
  `libphobos2-ldc-dev` (openSUSE `-devel` suffix convention differs).
- Microsoft's own package repos (used for e.g. PowerShell — see
  `0-new-system/new3-powershell-pwsh.sh` for a full worked reference implementation) do
  **not** officially support openSUSE/SLES or Fedora at all. For anything from Microsoft's
  package feed, openSUSE/Fedora need the binary-archive fallback method, not a repo/apt-style
  install. See that script's `install_binary_fallback()` for the pattern (queries GitHub's
  API for the latest release asset rather than hardcoding a version).
- **zypper does capability-based fallback matching** — confirmed live on a real openSUSE
  Tumbleweed box: `zypper install libicu` printed `'libicu' not found in package names.
  Trying capabilities. 'libicu78' providing 'libicu' is already installed.` So an
  approximate/upstream-project-style name sometimes resolves correctly even when it isn't
  the literal package name. This is a real safety net, but **don't rely on it as your
  only verification** — treat a zypper-branch package list you can't personally test as
  "probably works" rather than "confirmed works," and prefer real package names when
  you know them (e.g. `libSDL2-2_0-0` over a guessed `SDL2`).

## Known backlog: scripts with real problems as of this audit

Not yet fixed as of 2026-09-30. Re-verify before assuming still broken if a while has passed.

### ~~openSUSE — helper exists but a stray `apt` line bypasses it~~ — RESOLVED 2026-09-30

All 17 affected files fixed (`0-scripts/network-discovery-setup.sh`, `x-forwarding.sh`,
`x-forwarding-wslg.sh`, `x-forwarding-verbose.sh`, `sys-info-mac.sh`,
`convert-image-to-ascii-art.sh`; `0-new-system/new2-dev-package-managers.sh`,
`new2-tailscale.sh`; `0-games/0-X-gui/infra-arcana-get.sh`, `2048-compile.sh`,
`cavez-of-phear-get.sh`, `0-z-machine/zork1-with-frotz.sh`, `fangband-get.sh`,
`0-classic-games1.sh`, `0-X-gui/steam-gui-setup.sh`; `0-install/cloud-dropbox-get.sh`,
`cloud-googledrive-get.sh`). The four reusable fix recipes are now documented under
systemic bug #1 above — apply those directly if this pattern turns up again elsewhere
instead of re-deriving it. One file (`infra-arcana-get.sh`) has an unverified package-name
caveat, noted above.

### ~~openSUSE — no zypper/dnf path at all (apt-only or apt/dnf-only)~~ — RESOLVED 2026-10-04 (unverified on a live box)

All ~50 listed files were handled in this round (6 parallel agents), and every changed file
passes `bash -n`. Three kinds of fix were used, per the four recipes above:
- **zypper branch added** to an existing helper, or a small new helper added (gh, sysbench,
  fio, iperf3, lshw, cowsay, figlet, toilet, timeshift, chkrootkit, cockpit, openttd, 0ad,
  wesnoth, supertuxkart, freecol, scorched3d, sauerbraten, and others).
- **Clean "not automated for openSUSE" skip** where the install is an apt repository or
  `.deb` with no verified zypper equivalent (Brave, Charm glow, Microsoft Edge, dotnet
  .deb, Webmin, navidrome .deb, ZeroTier repo script, cataclysm-dda, tome-gcu, zangband,
  adom, redeclipse, AssaultCube, Xonotic, ASCIIpOrtal). Each prints the official URL.
- **Already fine, skipped**: mosh-get.sh, knights-who-say-ni.sh, unimatrix-cmatrix-bb-hollywood.sh,
  xterms.sh (their helpers already had zypper branches from earlier passes).

**Caveats to verify on the susew box before trusting**:
- Package names were not tested live. Less certain ones: `sensors` (lm_sensors),
  `timeshift`, `cyrus-sasl-plain`, `clamav` service names (openSUSE uses `freshclam`/`clamd`).
- `freecol`, `scorched3d`, `sauerbraten` live only in the OBS `games` project, not the
  default Tumbleweed repos — a stock system will say "not found" until that repo is added.
- `kvm-get.sh` uses zypper patterns `kvm_server`/`kvm_tools` — documented by SUSE, untested here.
- `new2-x11-forwarding.sh` and `new2-xrdp.sh` got apt steps skipped on zypper with a message,
  not a full rewrite — they still have no real package helper.

**Pre-existing bugs noticed in this round (not fixed, out of scope)**:
- `0-games/tome-gcu-mux.sh` checks for `tome-gcu` but launches `zangband` in tmux (copy-paste).
- `0-web-apps/cockpit-9090.sh` prints `systemctl start cockpit`; the unit on openSUSE is `cockpit.socket`.
- `0-scripts/0-toys/fig-cow-etc.sh` calls `display_warning`, which is never defined.
- `0-install/gitleaks-get.sh` Linux line has a `||` fallback grep that reads no input.
- `0-games/0-X-gui/infra-arcana-get.sh` still uses Fedora-style SDL2 names on zypper.

### Still open — noticed during the Tier 2 pass
- `lazygit-get.sh` / `lazydocker-get.sh` call `pkg_install`, which has no brew branch, so on
  macOS they exit before downloading. Also use GNU-only `df / --output=...`.
- `fd-get.sh` compares versions with `sort -V`, which BSD sort lacks on macOS (it always
  reports "upgrade needed").

`0-scripts/sys-bench.sh`, `0-scripts/gh-list-project-on-github.sh`,
`0-scripts/git-list-myprojects.sh`, `0-help/x-glow-template.sh`,
`0-scripts/0-toys/fig-cow-etc.sh`, `0-scripts/0-toys/fig-cow-etc1.sh`,
`0-install/edge.sh`, `0-install/clean-browser-brave.sh`,
`0-install/clean-browser-brave-old.sh`, `0-install/browser-brave-rebuild-refresh.sh`,
`0-install/c-sharp-dotnet-sdk-8.0.sh`, `0-install/unimatrix-cmatrix-bb-hollywood.sh`,
`0-install/mosh-get.sh`, `0-install/knights-who-say-ni.sh`, `0-install/kvm-get.sh`,
`0-install/glow-get.sh`, `0-install/ollama-get.sh`, `0-install/xterms.sh`,
`0-install/zerotier-get.sh`, `0-new-system/new0-openssh-server-setup.sh`,
`0-new-system/new0-sync-clock-to-Amsterdam.sh`, `0-new-system/new0-sync-clock-to-London.sh`,
`0-new-system/new0-timeshift.sh`, `0-new-system/new2-clamav.sh`,
`0-new-system/new2-x11-forwarding.sh`, `0-new-system/new2-xrdp.sh`,
`0-new-system/new3-email-with-gmail-relay.sh`, `0-web-apps/cockpit-9090.sh`,
`0-web-apps/my-system-info-8081.sh`, `0-web-apps/navidrome-music-4533.sh` (ships a `.deb`),
`0-web-apps/vscode-8088.sh`, `0-web-apps/webmin-10000.sh`,
`0-games/fitd-tower-defence.sh`, `0-games/cataclysm-dark-days-ahead.sh`,
`0-games/tome-gcu-mux.sh`, `0-games/zangband-mux.sh`, `0-games/adom-console-get.sh`,
`0-games/asciiquarium.sh`, and every `0-games/0-X-gui/*-get-gui.sh` script (0ad, freecol,
scorched3d, sauerbraten, supertux2, supertuxkart, wesnoth, flightgear, xonotic,
redeclipse, openttd, AssaultCube, ASCIIpOrtal, shattered-pixel-dungeon, infra-arcana)

### openSUSE — helper runs but is passed Debian-only package names

`0-install/prompt-zsh-and-powerlevel10k.sh`, `0-install/switch-desktop-environment.sh`,
`0-install/cloud-onedrive-get.sh`, `0-new-system/new3-email-with-gmail-relay.sh`

### ~~macOS — Docker install boilerplate has no Darwin branch~~ — RESOLVED 2026-09-30

All 26 files fixed: `0-docker/setup-docker.sh`, `docker-heimdall.sh`, `docker-wetty-ssh.sh`,
`docker-distros-linux.sh`, `docker-vscode-3005.sh`, `docker-watchtower.sh`,
`docker-webtop-alpine-xfce-3013.sh`, `docker-bastillion-ssh.sh`,
`docker-emulatorjs-3332-3333.sh`, `docker-portainer-9443.sh`, `docker-nginx-test-8888.sh`
(both its install-block `systemctl` calls AND a separate permissions-fix `usermod` found
during independent re-verification — see systemic bug #2 above), `docker-qbittorrent-8080.sh`,
`docker-plex-32400.sh`, `docker-webtop-debian-mate-3012.sh`, `docker-syncthing-8384.sh`,
`docker-rustdesk-server.sh`, `0-graf/start-stack.sh`, `0-graf/1/start-stack.sh`,
`0-grafana-prometheus/start-stack.sh`, `0-media-stack/fix-binhex-paths-and-restart.sh`,
`0-media-stack/stop-and-remove-media-stack.sh`,
`0-media-stack/0-wip-old/gluetun/start-media-stack.sh`,
`0-media-stack/0-wip-old/wireguard/start-media-stack-wireguard.sh`,
`0-media-stack/0-dyonr-qbittorrentvpn/start-media-stack-old-full.sh` (had the block
TWICE in the same file — see systemic bug #2's "can appear more than once" lesson),
`0-monitoring-stack/start-monitoring-stack.sh`, `0-media-players/start-media-players-stack.sh`.

Not fixed, tracked separately: `docker-rustdesk-server.sh` and
`start-media-players-stack.sh`'s underlying compose files still set
`network_mode: host`, which is a Docker-Desktop-for-Mac networking limitation, not a
shell-script bug — out of scope for this pass.

### ~~macOS — GNU-only `sed -i` / `stat -c` / `date -d` / `readlink -f` / `realpath -e`~~ — RESOLVED 2026-09-30

All 23 files fixed (`0-docker/docker-heimdall.sh`, `docker-immich-stack.sh`,
`docker-bastillion-ssh.sh`, `0-media-players/start-media-players-stack.sh`,
`0-media-stack/fix-media-stack.sh`, `fix-media-stack-paths.sh`, `reset-password.sh`,
`stop-binhex-fix-paths-restart.sh`, `0-games/angband-backup-restore-saves.sh`,
`sil-q-get.sh`, `brogue-console.sh`, `fitd-tower-defence.sh`, `bashmaze.sh`,
`0-scripts/git-old-versions.sh`, `git-extract-commit-versions.sh`,
`syntax-fix-issues.sh`, `diff-folders.sh`, `0-new-system/new1-add-paths.sh`,
`new1-dns-rename.sh`, `new1-dns-troubleshoot.sh`, `0-web-apps/navidrome-music-4533.sh`) —
**except** `0-media-stack/start-media-stack.sh` and
`0-binhex-arch-qbittorrent/start-media-stack-binhex-fix-old.sh`, whose `sed -i` calls
were correctly left untouched: they run *inside a Docker container*
(`docker exec ... /bin/bash -c '...'`), not on the host, so a host-`uname` branch would
have been wrong there — see the container-vs-host caveat under "Portable `sed -i`" above.
The verified exact BSD `stat`/`date` mappings discovered while fixing this are now in the
boilerplate section above (`file_mtime_epoch`, `epoch_to_date`, the git ISO-strict
timestamp caveat).

### ~~macOS — unconditional root re-exec with no OS check~~ — RESOLVED 2026-10-04

12 scripts re-exec themselves via `sudo "$0"` (or `sudo bash "$0"`) the moment
`$EUID -ne 0`, with no OS check at all — so on macOS they prompt for a sudo password
before the script has even determined whether it applies there. Found while verifying the
user's "does brew get run as root anywhere?" concern (answer: no — confirmed zero
`sudo brew` in the repo, and the one real past instance of root-exec-then-brew-install was
`mosh-get.sh`, already fixed in Tier 1). `0-scripts/sys-info-lin-mac.sh` is the one sibling
that does this correctly — gates on `[[ "$IS_MAC" == "false" && $EUID -ne 0 ]]`.

**6 fixed 2026-10-03** with an early exit rather than the `sys-info-lin-mac.sh` "just move
the gate" pattern. Each one is deeply Linux-specific beyond the root check itself
(`sys-info.sh` uses `getent`, `sys-info-basic.sh` is built on `dmidecode`, `stop-GUI.sh`
targets X11/Wayland by design, `storage-decom.sh` does Linux fstab/exports/Samba/partition
work, the two NTFS scripts use Linux mount tooling) — moving the sudo gate alone would
just mean they crash moments later instead of failing immediately. Building real macOS
equivalents (diskutil-based decommissioning, macFUSE NTFS mounting, a WindowServer-aware
process killer) is substantial new feature work, not a quick fix, and `storage-decom.sh`
specifically does destructive partition deletion — not something to improvise casually.
So the fix applied to all 6 was an early `[[ "$(uname)" == "Darwin" ]]` exit with a clear
message, BEFORE the sudo prompt: `0-scripts/sys-info.sh`, `sys-info-basic.sh`, `stop-GUI.sh`,
`storage-decom.sh`, `ntfs-mount-auto.sh`, `ntfs-unmount-all.sh`. One side-fix:
`ntfs-mount-auto.sh`'s header comment falsely claimed `"Optimized for: ... macOS"` despite
having zero real macOS logic anywhere in the file — corrected.

**5 more fixed 2026-10-04**, same "skip gracefully" shape, each verified live (ran on the
real machine, confirmed clean exit with zero sudo prompt): `optimal-cpu-policy.sh`
(Linux cpufreq governors — no macOS equivalent exists, not even on Apple Silicon, the OS
fully owns P/E-core scheduling with no user knob), `optimal-disks-policy.sh` (Linux-only
`hdparm` power tuning — no macOS equivalent; its SMART-health half got a *real* macOS
sibling instead, see below), `winbind-fix-stale.sh` (not just "Linux-only" but a one-off
diagnostic hardcoded to a specific host/IP — not a reusable tool on any platform),
`winbind-wins.sh` (rewires glibc NSS to resolve NetBIOS/WINS — the problem it solves
doesn't exist on macOS, whose SMB stack resolves this natively without touching
`/etc/nsswitch.conf` at all), `remote-access-opensuse.sh` (a deliberately openSUSE-specific
13-section toolkit — Cockpit, x11vnc, Fail2Ban, zypper, etc.). A proper `remote-access-mac.sh`
sibling was subsequently built 2026-10-04 rather than left skipped — see "Reference
implementations" below.

**`navidrome-radio-podcast.sh` got a real fix, not a skip** — Navidrome itself runs fine on
macOS (`brew install navidrome`); the bug was that this particular script assumed a
specific Linux *server deployment* (dedicated system user, `/srv/music`, systemd), not
that Navidrome itself can't run there. Fixed: `MUSIC_DIR` now defaults appropriately per OS
(`$HOME/Music/Navidrome` on macOS, `/srv/music` on Linux, override via env var either way),
root is only required on Linux, the Linux-only `chown navidrome:navidrome` is skipped on
macOS, and the service restart branches `brew services restart navidrome` vs
`systemctl restart navidrome`. Side-fix found while in there: the podcast-fetch line used
`grep -oP` (a GNU-only Perl-regex extension — macOS's BSD grep has no `-P` at all, so this
would have silently failed even after everything else was fixed) — replaced with a
portable `grep -o` + `sed` extraction that works identically on both.

**New script**: `0-scripts/optimal-disks-policy-mac.sh` — the genuinely-portable half of
`optimal-disks-policy.sh` (SMART health reporting), built and live-tested on real hardware.
Initial design used `smartctl`/smartmontools per the original plan, but testing surfaced two
real problems with that approach: smartmontools has known gaps reading Apple Silicon's
proprietary internal NVMe controller, and it needs `sudo` access this session didn't have
permission to grant. Switched to parsing `diskutil info`'s own `SMART Status` field instead
— built in, no extra dependency, no sudo needed, and it works because Apple's own
DiskArbitration framework talks to the controller directly. Also had to filter
`diskutil list` down to `diskutil list physical` — the naive `/dev/disk[0-9]*` glob counted
synthesized APFS container/volume devices as if they were separate physical disks, which
would have reported the same drive's SMART status 3-4 times over.

### ~~macOS — hardcoded Linux-only release-asset filenames (no Darwin case)~~ — RESOLVED 2026-10-04

Fixed from the upstream release assets fetched on 2026-10-04: gitleaks (`darwin_arm64`/`darwin_x64`),
go (`darwin-arm64`/`darwin-amd64`), lazygit (`Darwin_arm64`/`Darwin_x86_64`), lazydocker
(same pattern), trufflehog (`darwin_arm64`/`darwin_amd64`), fd (`aarch64-apple-darwin` /
`x86_64-apple-darwin`), yt-dlp (`yt-dlp_macos`, one universal asset), onefetch
(`onefetch-mac.tar.gz`, one asset), yq (`yq_darwin_arm64`/`yq_darwin_amd64`). `mdcat` has no
macOS release asset upstream, so it now points at `brew install mdcat`.

Caveats: names were read from WebFetch summaries, not raw API JSON — spot-check once with a
real download on your Mac. `go-language.sh` still pins 1.22.5; the darwin pattern was only
confirmed on 1.27.1. The arch-less yt-dlp/onefetch assets are assumed to run on Intel and Apple Silicon.

`0-install/gitleaks-get.sh`, `go-language.sh`, `lazygit-get.sh`, `lazydocker-get.sh`,
`mdcat-get.sh`, `onefetch-get.sh`, `trufflehog-get.sh`, `fd-get.sh`, `yt-dlp-get.sh`,
`0-docker/setup-yq-for-yaml.sh`

### macOS — systemd/launchd, `/proc`, `useradd`/`usermod`, `ip`/`hostnamectl` with no macOS path

`0-scripts/process-hunter.sh` (`/proc`), `enable-wake-on-lan.sh` (`ip route`),
`change-hostname.sh` (`hostnamectl`), `mounts.sh` (`findmnt`),
`share-folder-samba.sh` (`groupadd`), `0-scripts/0-toys/figbanner.sh` /
`figbanner-compact.sh` (`/proc/cpuinfo`), `0-install/surfshark-on-wireshark-headless-get.sh`,
`cloud-onedrive-get.sh`, `cloud-dropbox-get.sh` (`.desktop` file),
`bastillion-web-ssh.sh` (`useradd`), `ollama-get.sh`, `zerotier-get.sh`,
`zerotier-set-cron-get.sh`,
`0-new-system/new0-sudo-add-current-user.sh` (`groupadd`/`usermod`),
`new0-sync-clock-to-Amsterdam.sh`/`London.sh`, `0-web-apps/glances-61208.sh`,
`my-system-info-8081.sh` (also BSD-incompatible `nc -l -p`), `vscode-8088.sh` (`usermod`),
`webmin-10000.sh`

### ~~macOS — otherwise multi-distro `pkg_install()` is missing a `brew` branch~~ — MOSTLY RESOLVED 2026-09-30

13 of 15 files fixed: `0-new-system/new1-vimrc.sh`, `new1-vimrc1.sh`, `new2-clamav.sh`,
`new2-tailscale.sh`, `new3-email-with-gmail-relay.sh`,
`0-install/switch-desktop-environment.sh`, `xterms.sh`, `prompt-zsh-and-powerlevel10k.sh`,
`0-web-apps/qbittorrent-nox.sh`, `visual-studio-code-get.sh` (had no helper at all — built
one from scratch including zypper/dnf branches modeled on Microsoft's official docs, but
**unverified live**, same caveat class as `infra-arcana-get.sh`'s openSUSE SDL2 names),
`unimatrix-cmatrix-bb-hollywood.sh`, `mosh-get.sh` (also had a latent bug found while
fixing: an unconditional root re-exec via `sudo "$0"` that would have run Homebrew as
root and silently failed — guarded to Linux-only), `knights-who-say-ni.sh`.

**Not fixed — genuinely didn't match the bug pattern**: `new2-x11-forwarding.sh` and
`new2-xrdp.sh` have no `pkg_install()`-style helper at all (direct `apt`/`dpkg` calls
throughout) — "add a brew branch" doesn't apply without a much larger restructure
(introducing a helper and replacing every direct call), which wasn't attempted as a
minimal surgical diff. Both are still listed in the "no zypper/dnf path at all" category
above too — whoever picks these up should build the helper once and it'll resolve both
bugs together.

**Known-bad package names left unguessed rather than invented** (these will likely still
fail on their respective managers even with the brew branch added, since the failure is
the *package name*, not missing branch logic): `new2-clamav.sh` passes `clamav-daemon`
(Debian-specific split package; brew's `clamav` formula doesn't separate the daemon),
`new3-email-with-gmail-relay.sh` passes `libsasl2-2`/`libsasl2-modules` (Debian names;
brew equivalent is structured differently as `cyrus-sasl`), `switch-desktop-environment.sh`
passes tasksel meta-package names like `task-gnome-desktop` (Debian-only concept; desktop
environments aren't applicable to macOS at all, so this script may not be a meaningful
macOS target regardless), and the pre-existing `prompt-zsh-and-powerlevel10k.sh` caveat
(`fonts-font-awesome`/`fonts-powerline`) from the openSUSE section above applies here too.

## Reference implementations already fixed in this repo (copy patterns from these)

- `0-new-system/new3-powershell-pwsh.sh` — full worked example of OS detection
  (`uname` + `/etc/os-release`), the "package name differs per manager" pattern, and the
  "not officially supported, use binary-archive fallback with a live GitHub API lookup"
  pattern.
- `0-scripts/storage-build.sh` — full worked example of a macOS-vs-Linux branch for an
  entire feature area (disk partitioning), including a `diskutil`-based retry loop with
  real error output instead of a silent hard-fail.
- `0-scripts/ping-subnet-new.ps1` (PowerShell, not bash, but same principle) — worked
  example of branching `ip` (Linux) vs `ifconfig`/`netstat`/`arp` (macOS) vs
  `Get-NetIPConfiguration`/`Get-NetAdapter`/`Get-NetNeighbor` (Windows) for the same
  logical feature (subnet/gateway/ARP detection).
- `0-scripts/g` — the `pkg_install()` helper pattern this whole guide is built around.
- `0-scripts/optimal-disks-policy-mac.sh` — worked example of a deliberately *separate*
  OS-specific sibling script rather than a branched single file, for a case where the
  underlying feature set genuinely diverges (Linux `hdparm` power tuning has no macOS
  concept to branch to) rather than just needing different commands for the same idea.
  Also a reminder to verify tooling choices live rather than trust a plan: the original
  intent was `smartctl`, but live testing surfaced real gaps (Apple Silicon NVMe support,
  sudo permission friction) that a built-in `diskutil info` field solved more simply.
- `0-scripts/remote-access-mac.sh` — a genuinely separate sibling to
  `remote-access-opensuse.sh` rather than a branched port (Cockpit/x11vnc/Fail2Ban have no
  macOS equivalent; Screen Sharing/`kickstart`, `scutil`, `pmset`, `systemsetup` replace
  them where a real native equivalent exists). Two real bugs were only caught by running it
  live on real hardware, not by reading the code: (1) `scutil --get HostName` prints an
  `AuthorizationCreate() failed` error to *stdout*, not stderr, when HostName isn't
  explicitly set (common - most Macs only ever have ComputerName/LocalHostName set via the
  GUI) - a plain `2>/dev/null` fallback doesn't catch that, the fix checks the exit code via
  `if VAR=$(cmd); then` instead of trusting captured output. (2) The obvious
  `netstat -rn | grep '^default' | head -1` pattern for finding the primary network
  interface (used correctly elsewhere in this repo, e.g. `storage-build.sh`) picked a
  `utunN` VPN/tunnel interface instead of the real one on this exact machine, because
  multiple default-route lines existed and the tunnel one sorted first - needed an
  additional filter for a line with a real IPv4 gateway address. Also: three sections
  originally called `sudo` unconditionally just to *display* current status before the user
  had decided to change anything (mirroring the exact "don't force needless sudo" bug this
  whole audit has been fixing elsewhere) - switched to non-privileged proxy signals
  (`pgrep`, `launchctl list`) instead, so sudo is only invoked once something is actually
  being changed.
- `0-scripts/remote-access-opensuse.sh` (V20) — example of backporting real value found
  while building a sibling script, not just mechanical fixes: picked up a GUI
  remote-access-tools survey (TeamViewer/AnyDesk/Chrome Remote Desktop/RealVNC all support
  Linux too) and a laptop-battery caveat on sleep-hardening from `remote-access-mac.sh`.
  Also gained real safety improvements of its own: every option now explains what it does
  and its actual downside before asking (not just doing it), FileBrowser's forced
  `admin/admin` login got a random-strong-password alternative, and a real latent bug was
  fixed - the Samba section configured a share but never opened the firewall for it, so it
  likely never actually worked as shipped.
