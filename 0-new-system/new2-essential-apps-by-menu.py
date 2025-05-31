#!/usr/bin/env python3
# Author: Roy Wiseman 2025-01
import os
import curses
import subprocess
import time
import signal
import sys
from datetime import datetime

LOG_FILE = "/tmp/python_game_installer_menus.log"

PACKAGE_STATUS_INSTALLED = "INSTALLED"
PACKAGE_STATUS_AVAILABLE = "AVAILABLE"
PACKAGE_STATUS_NOT_AVAILABLE = "NOT_AVAILABLE"
PACKAGE_STATUS_CHECK_ERROR = "ERROR_CHECKING"

HEADER_PREFIX = "### " # Define the prefix for headers

# User should structure this dictionary with headers in the desired places.
# The order will be preserved in the menu.
ESSENTIAL_APPS = {
    "### SYSINFO & MONITORING": "Tools for viewing system status, hardware, and performance.",
    "atop": "Advanced interactive monitor for Linux system and process activity. (~<1MB)",
    "bottom": "A customizable cross-platform graphical process/system monitor for the terminal (command 'btm'). (~5MB)",
    "btop": "Modern TUI resource monitor (processor, memory, disks, network, processes). (~2MB)",
    "dstat": "Versatile resource statistics tool (replacement for vmstat, iostat, netstat). (~<1MB)",
    "glances": "A cross-platform system monitoring tool with a curses or web interface. (~2MB)",
    "hddtemp": "Utility to monitor hard drive temperature (often needs daemon setup). (~<1MB)",
    "htop": "Interactive process viewer and manager. (~<1MB)",
    "hwinfo": "Probes for hardware present in the system. (~2MB)",
    "iftop": "Network bandwidth monitor (displays bandwidth usage on an interface). (~<1MB)",
    "inxi": "Comprehensive command-line system information tool. (~1MB)",
    "iotop": "Monitor disk I/O usage by processes (needs sudo). (~<1MB)",
    "lm-sensors": "Utilities to read temperature/voltage/fan sensors (run 'sensors-detect' first). (~<1MB)",
    "lshw": "List an inventory of hardware on the system (needs sudo for full detail). (~1MB)",
    "lsof": "List open files by processes. (~<1MB)",
    "neofetch": "A fast, highly customizable system information script with an ASCII logo. (~<1MB)",
    "nethogs": "A small 'net top' tool that shows bandwidth usage per process (needs sudo). (~<1MB)",
    "nmon": "Systems administrator, tuner, benchmark tool (displays stats or saves to file). (~<1MB)",
    "pciutils": "Linux PCI utilities (provides lspci). (~<1MB)",
    "powertop": "Diagnose issues with power consumption and power management (needs sudo). (~<1MB)",
    "screenfetch": "Fetches system/theme information in terminal for screenshot purposes. (~<1MB)",
    "smartmontools": "Utilities for controlling and monitoring S.M.A.R.T. data on hard drives. (~1MB)",
    "sysstat": "Performance monitoring tools for Linux (sar, iostat, mpstat). (~1MB)",
    "usbutils": "Linux USB utilities (provides lsusb). (~<1MB)",
    "util-linux": "Miscellaneous system utilities (lsblk, fdisk, dmesg, etc. - usually core). (~2MB)",
    "vnstat": "Console-based network traffic monitor that keeps long-term statistics. (~<1MB)",
    "wavemon": "Curses-based monitoring application for wireless network devices. (~<1MB)",

    "### FILE & DISK": "Tools for creating, managing, searching, and analyzing files and disks.",
    "bat": "cat(1) clone with syntax highlighting and Git integration (package often 'bat' or 'batcat'). (~5MB)",
    "bmon": "Portable bandwidth monitor and rate estimator with a curses interface. (~<1MB)", # Also network, but listed here by user
    "broot": "A new way to see and navigate directory trees with context and fuzzy search (command 'br'). (~10MB)",
    "cpio": "Tool to copy files into or out of a cpio or tar archive. (~<1MB)",
    "csvkit": "A suite of command-line tools for converting and working with CSV. (~5MB)",
    "datamash": "GNU Datamash: command-line program for basic numeric, textual, and statistical operations. (~<1MB)",
    "dos2unix": "Converts text file line endings between DOS/Windows and Unix formats. (~<1MB)",
    "du-dust": "A more intuitive version of du in rust (like du + tree; command 'dust'). (~5MB)",
    "fdupes": "Identifies and deletes duplicate files. (~<1MB)",
    "fd-find": "A simple, fast and user-friendly alternative to 'find' (command 'fd'). (~2MB)",
    "gdu": "Fast disk usage analyzer with console interface (Go Du). (~5MB)",
    "gparted": "GUI partition editor for managing disk partitions. (~5MB)",
    "highlight": "Converts source code to formatted text with syntax highlighting (ANSI, HTML, RTF, etc.). (~1MB)",
    "lf": "Lightweight Go console file explorer. (~2MB)",
    "libxml2-utils": "Utilities for XML manipulation (xmllint). (~<1MB)",
    "mc": "Midnight Commander - a console-based file manager. (~2MB)",
    "most": "A powerful paging program, similar to 'less' but with more features. (~<1MB)",
    "ncdu": "NCurses Disk Usage analyzer. (~<1MB)",
    "nnn": "Extremely fast and resource-light console file explorer. (~<1MB)",
    "p7zip-full": "Full 7z and p7zip archive support (compression/decompression). (~5MB)",
    "pandoc": "Universal document converter (Markdown, HTML, PDF, LaTeX, etc.). (~100MB)",
    "parted": "Command-line partition manipulation program. (~<1MB)",
    "pigz": "A parallel implementation of gzip for faster compression/decompression. (~<1MB)",
    "progress": "Coreutils Progress Viewer - shows progress for cp, mv, dd, tar, etc. (command 'cv'). (~<1MB)",
    "pv": "Pipe Viewer - monitors the progress of data through a pipeline. (~<1MB)",
    "ranger": "A console file manager with VI key bindings. (~1MB)",
    "renameutils": "A set of programs to make renaming files easier (incl. qmv, qcp). (~<1MB)",
    "ripgrep": "Recursively searches directories for a regex pattern, very fast (command 'rg'). (~3MB)",
    "rsync": "Fast, versatile remote (and local) file-copying tool. (~<1MB)",
    "sd": "Intuitive find & replace CLI (sed alternative, often simpler for basic cases). (~2MB)",
    "silversearcher-ag": "A code-searching tool similar to ack, but faster (the_silver_searcher). (~<1MB)",
    "trash-cli": "Command-line interface to the freedesktop.org trash system. (~<1MB)",
    "tree": "Displays directory contents in a tree-like format. (~<1MB)",
    "unrar": "Utility for extracting, testing and viewing RAR archives. (~<1MB)",
    "unzip": "Utility for extracting and viewing files in ZIP archives. (~<1MB)",
    "xmlstarlet": "Command line XML toolkit for querying, validating, and transforming XML. (~1MB)",
    "yq": "A lightweight and portable command-line YAML, JSON and XML processor (like jq for YAML). (~5MB)",
    "zip": "Utility for packaging and compressing (archiving) files. (~<1MB)",

    "### NETWORKING": "Utilities for network analysis, communication, and configuration.",
    "aria2": "High speed download utility (HTTP, FTP, BitTorrent, Metalink). (~5MB)",
    "arp-scan": "ARP scanning and fingerprinting tool (sudo arp-scan -l). (~<1MB)",
    "autossh": "Automatically restarts SSH sessions and tunnels if they drop. (~<1MB)",
    "bridge-utils": "Utilities for configuring the Linux Ethernet bridge (for network bridging). (~<1MB)",
    "curl": "Command line tool for transferring data with URL syntax. (~1MB)",
    "dnsutils": "DNS utilities (dig, nslookup, nsupdate). (~1MB)",
    "ethtool": "Utility for querying and controlling network driver and hardware settings. (~<1MB)",
    "httpie": "Modern, user-friendly command-line HTTP client (alternative to curl/wget). (~2MB)",
    "iperf3": "Network performance testing tool for TCP, UDP, and SCTP. (~<1MB)",
    "mtr": "Network diagnostic tool (combines ping and traceroute). (~<1MB)",
    "ncat": "Netcat replacement from Nmap, with SSL, IPv6, and proxy support. (~<1MB, part of nmap often)",
    "net-tools": "Networking utilities (arp, ifconfig, netstat, route - often deprecated). (~<1MB)",
    "ngrep": "Network grep - applies regex patterns to network traffic in real time. (~<1MB)",
    "nmap": "Network exploration tool and security/port scanner. (~25MB)",
    "ntp": "Network Time Protocol daemon and utility programs for time synchronization. (~1MB)",
    "openssh-client": "Secure shell (SSH) client for remote login. (~1MB)",
    "proxychains4": "Route connections through SOCKS4/5 or HTTP proxies (command 'proxychains4'). (~<1MB)",
    "rclone": "Command-line program to manage files on cloud storage. (~20MB)",
    "rsstail": "Like tail -f, but for RSS/Atom feeds. (~<1MB)",
    "socat": "Multipurpose relay (SOcket CAT) - versatile network tool. (~<1MB)",
    "speedtest-cli": "Command line interface for testing internet bandwidth using speedtest.net. (~<1MB)",
    "tcpdump": "Command-line network packet analyzer. (~1MB)",
    "traceroute": "Prints the route packets trace to network host. (~<1MB)",
    "w3m": "Text-based web browser and pager (can render HTML to text, browse local files). (~2MB)",
    "wget": "Non-interactive network downloader. (~1MB)",
    "whois": "Client for the WHOIS directory service (domain/IP lookup). (~<1MB)",

    "### TEXT & EDITORS": "Tools for creating, viewing, and manipulating text files.",
    "ack": "Grep-like text finder, optimized for programmers (often package 'ack-grep'). (~<1MB)",
    "colordiff": "A tool to colorize diff output. (~<1MB)",
    "emacs": "Extensible, customizable, self-documenting real-time display editor. (~100MB)",
    "iconv": "Utility to convert text from one character encoding to another. (~<1MB, often core)",
    "jo": "A small utility to create JSON objects from shell commands or strings. (~<1MB)",
    "jq": "Command-line JSON processor. (~<1MB)",
    "kakoune": "Modal editor with a focus on interactivity, inspired by Vim, with multiple cursors. (~5MB)",
    "micro": "A modern and intuitive terminal-based text editor (Go based). (~10MB)",
    "mlr": "Miller - like awk, sed, cut, join, and sort for CSV, TSV, JSON, and more. (~5MB)",
    "nano": "Simple, modeless text editor for the console. (~<1MB)",
    "neovim": "Vim-fork focused on extensibility and usability. (~30MB)",
    "poppler-utils": "PDF utilities (pdftotext, pdfimages, pdffonts, pdfinfo, etc.). (~2MB)",
    "recode": "Character set conversion utility. (~<1MB)",
    "texlive-full": "TeX Live: A comprehensive TeX document production system (VERY large). (~2GB+)",
    "vim": "Vi IMproved - a highly configurable text editor. (~30MB)",
    "vim-nox": "Vim compiled with support for scripting (Perl, Python, Ruby, Tcl) but no GUI. (~30MB)",

    "### DEV TOOLS": "Tools for software development, debugging, and version management.",
    "ansible": "Configuration management, deployment, and task execution system. (~50MB)",
    "ccache": "A fast C/C++ compiler cache to speed up recompilations. (~1MB)",
    "entr": "Run arbitrary commands when files change. (~<1MB)",
    "fzf": "A command-line fuzzy finder for history, files, processes, git commits, etc. (~1MB)",
    "gh": "Official GitHub CLI tool - interact with GitHub from the command line. (~10MB)",
    "lazygit": "A simple terminal UI for git commands, written in Go. (~10MB)",
    "ltrace": "Traces dynamic library calls, also for debugging. (~<1MB)",
    "meld": "Visual diff and merge tool (GUI, but often launched from/useful with CLI workflows). (~2MB)",
    "pass": "The standard unix password manager (uses GPG and git). (~<1MB)",
    "rlwrap": "A readline wrapper that provides command editing and history for other commands. (~<1MB)",
    "shellcheck": "A static analysis tool for shell scripts. (~5MB)",
    "shfmt": "Shell script parser, formatter, and interpreter (supports bash, sh, zsh, mksh). (~3MB)",
    "strace": "Traces system calls and signals, useful for debugging. (~<1MB)",
    "terraform": "Infrastructure as Code software by HashiCorp (download, or check package availability). (~50MB)",
    "tig": "Text-mode interface for Git, acts as a repository browser and commit viewer. (~1MB)",
    "tldr": "Collaborative cheatsheets for console commands (Too Long; Didn't Read). (~<1MB)",

    "### SHELL UTILS": "Tools to improve command-line experience and shell scripting.",
    "byobu": "Text-based window manager and terminal multiplexer (enhances screen or tmux). (~<1MB)",
    "busybox": "Collected common console tools in a single small executable. (~1MB)",
    "dialog": "Displays user-friendly dialog boxes from shell scripts. (~<1MB)",
    "direnv": "An extension for your shell to load/unload environment variables per directory. (~1MB)",
    "expect": "A tool for automating interactive applications. (~<1MB)",
    "figlet": "Generates large characters out of ordinary screen characters (ASCII art). (~<1MB)",
    "moreutils": "A collection of useful UNIX tools (parallel, sponge, vipe, vidir, etc.). (~<1MB)",
    "navi": "An interactive cheatsheet tool for the command-line, using fzf. (~5MB)",
    "screen": "Terminal multiplexer with VT100/ANSI terminal emulation. (~<1MB)",
    "tmux": "Terminal multiplexer, enables multiple terminals in one screen. (~<1MB)",
    "toilet": "Displays large colourful characters in a variety of fonts (similar to figlet). (~<1MB)",
    "whiptail": "Displays user-friendly dialog boxes from shell scripts (similar to dialog). (~<1MB)",
    "zoxide": "A smarter 'cd' command that learns your frequently used directories. (~2MB)",
    "zsh": "Z Shell - a powerful command-line interpreter. (~5MB)",

    "### SECURITY": "Tools for system security, encryption, and privacy.",
    "certbot": "Automatically enable HTTPS on your website with Let's Encrypt. (~5MB)",
    "chkrootkit": "Rootkit detection tool. (~<1MB)",
    "clamav": "Open-source antivirus engine. (~100MB for definitions + engine)",
    "fail2ban": "Daemon to ban hosts that cause multiple authentication errors. (~<1MB)",
    "firejail": "Linux namespaces and seccomp-bpf sandbox to restrict application permissions. (~1MB)",
    "gocryptfs": "Encrypted overlay filesystem that is easy to set up and use. (~2MB)",
    "inotify-tools": "Command-line programs for inotify (filesystem event monitoring). (~<1MB)",
    "john": "Password cracking tool (John the Ripper). (~10MB)",
    "lynis": "System security auditing tool. (~1MB)",
    "openssh-server": "Secure Shell (SSH) server for remote access. (~1MB)",
    "rkhunter": "Rootkit Hunter - scans for rootkits, backdoors and local exploits. (~1MB)",
    "tor": "The Onion Router: an anonymizing overlay network for TCP (provides SOCKS proxy). (~10MB)",
    "ufw": "Uncomplicated Firewall - a simple interface for iptables. (~<1MB)",

    "### VIRTUALIZATION": "Tools for managing virtual machines and containers.",
    # "docker-compose": "Define and run multi-container Docker applications (check for conflicts). (~15MB)",
    # "docker.io": "Linux container runtime (Docker Engine - check for conflicts or use docker-ce). (~100MB+)",
    "kubeadm": "Tool for bootstrapping a Kubernetes cluster. (~20MB)",
    "kubectl": "Command-line tool for controlling Kubernetes clusters. (~15MB)",
    "kubelet": "Primary node agent that runs on each Kubernetes node. (~20MB)",
    "vagrant": "Tool for building and managing virtual machine environments. (~50MB)",
    "virtualbox": "x86 virtualization solution (Oracle VM VirtualBox). (~100MB)",
    "virtualbox-ext-pack": "VirtualBox extension pack (USB 2.0/3.0, RDP, PXE boot - check license). (~20MB)",

    "### SERVERS & SERVICES": "Software for providing network services.",
    "apache2": "Apache HTTP Server. (~5MB)",
    "mysql-server": "MySQL database server. (~150MB)",
    "nginx": "High-performance web server, reverse proxy, and load balancer. (~2MB)",
    "postgresql": "Object-relational SQL database server (PostgreSQL). (~50MB)",
    "postgresql-contrib": "Contributed extensions and utilities for PostgreSQL. (~5MB)",
    "samba": "SMB/CIFS file, print, and login server for Unix. (~20MB)",

    "### GUI/CLI": "GUI tools often used alongside CLI or for system tasks.",
    # gparted already listed under File & Disk
    # meld already listed under Development
    "glow": "Render markdown on the CLI, with a beautiful server-side-rendering style. (~10MB)",
    "pulseaudio": "PulseAudio sound server (often a desktop environment dependency). (~2MB)",
    "scrot": "Command line screen capture utility using imlib2 (for X11). (~<1MB)",
    "screenkey": "A screencast tool to display your keystrokes (X11). (~<1MB)",
    "timeshift": "System restore utility for Linux (similar to Time Machine or System Restore). (~1MB)",
    "xclip": "Command line interface to X selections (clipboard - for X11 desktop). (~<1MB)",
    "xsel": "Command-line program for getting and setting the contents of the X selection (X11). (~<1MB)",

    "### MISC": "Other useful or entertaining command-line tools.",
    "apg": "Automated Password Generator - generates random passwords. (~<1MB)",
    "asciinema": "Record and share your terminal sessions, the right way. (~1MB)",
    "at": "Delayed command execution and batch processing (jobs run once). (~<1MB)",
    "bc": "An arbitrary precision calculator language. (~<1MB)",
    "calcurse": "A text-based calendar and scheduling application with ncurses UI. (~<1MB)",
    "cmus": "A small, fast and powerful console music player for Unix-like systems. (~1MB)",
    "cowsay": "A configurable talking cow (or other characters) using ASCII art. (~<1MB)",
    "ffmpeg": "Tools for recording, converting and streaming audio and video. (~50MB+)",
    "flatpak": "Application sandboxing and distribution framework ('app stores'). (~10MB)",
    "fortune-mod": "Provides fortune cookies (aphorisms, jokes, etc.) to your terminal (command 'fortune'). (~2MB)",
    "khal": "Standards based CLI and terminal calendar program (CalDAV compatible). (~1MB)",
    "pwgen": "Generates pronounceable (yet secure) passwords. (~<1MB)",
    "qalc": "Powerful and easy to use command line calculator (Qalculate!). (~5MB)",
    "snapd": "Daemon and tooling that enables snap packages. (~50MB)",
    "units": "GNU Units: converts between different systems of units. (~<1MB)",
    "uuid-runtime": "Runtime components for the Universally Unique ID library (provides uuidgen). (~<1MB)",
    "yt-dlp": "A youtube-dl fork with additional features and fixes for downloading videos. (~5MB)"
}
INSTALL_COMMAND_TEMPLATE = "sudo apt-get install -y {packages}"

def log_message(message):
    try:
        with open(LOG_FILE, "a") as log_file:
            log_file.write(f"{datetime.now()}: {message}\n")
    except Exception as e:
        print(f"Error writing to log file {LOG_FILE}: {e}", file=sys.stderr)

def get_package_status(package_name, suppress_logging=False):
    env = os.environ.copy()
    env['LC_ALL'] = 'C'
    try:
        dpkg_result = subprocess.run(['dpkg', '-l', package_name],
                                     capture_output=True, text=True, check=False, env=env)
        if dpkg_result.returncode == 0:
            for line in dpkg_result.stdout.splitlines():
                parts = line.split()
                if len(parts) > 1 and parts[0] == 'ii' and parts[1] == package_name:
                    return PACKAGE_STATUS_INSTALLED
    except FileNotFoundError:
        if not suppress_logging: log_message(f"dpkg command not found during check for {package_name}.")
    except Exception as e:
        if not suppress_logging: log_message(f"Exception during dpkg -l check for {package_name}: {e}")

    try:
        apt_show_result = subprocess.run(['apt-cache', 'show', package_name],
                                         capture_output=True, text=True, check=False, env=env)
        if apt_show_result.returncode == 0 and apt_show_result.stdout.strip():
            return PACKAGE_STATUS_AVAILABLE
        else:
            if not suppress_logging and apt_show_result.returncode != 0 :
                 log_message(f"apt-cache show for '{package_name}' indicated not available. RC: {apt_show_result.returncode}. Stderr: {apt_show_result.stderr.strip()}")
            return PACKAGE_STATUS_NOT_AVAILABLE
    except FileNotFoundError:
        if not suppress_logging: log_message(f"apt-cache command not found during check for {package_name}.")
        return PACKAGE_STATUS_CHECK_ERROR
    except Exception as e:
        if not suppress_logging: log_message(f"Exception during apt-cache show for {package_name}: {e}")
        return PACKAGE_STATUS_CHECK_ERROR

def get_formatted_header_text(item_name_key):
    header_content = item_name_key[len(HEADER_PREFIX):].strip().upper()
    return f"--- {header_content} ---"


def run_menu_session_with_cache_build(stdscr, item_definitions, status_cache, build_done_flag_container):
    if not curses.has_colors():
        raise RuntimeError("Terminal does not support colors.")
    try:
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Highlighted
        curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Normal / Available / Header
        curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # Error text
        curses.init_pair(4, curses.COLOR_GREEN, curses.COLOR_BLACK)  # Installed Item Name / Legend
        curses.init_pair(5, curses.COLOR_YELLOW, curses.COLOR_BLACK) # Yellow Key Hint
        # Pair 6 for Green Legend text (can reuse pair 4 if needed)
        # For Dimmed text, we use Pair 2 + A_DIM
    except curses.error as e:
        raise RuntimeError(f"Error initializing colors: {e}.")

    if not build_done_flag_container[0]: # Check flag
        stdscr.clear()
        h_loader, w_loader = stdscr.getmaxyx()
        loading_line_y = h_loader // 2
        title_message = "Building package status cache. This may take a moment..."
        title_x = max(0, (w_loader - len(title_message)) // 2)

        def safe_addstr_loader(y, x, text, attr=0):
            if 0 <= y < h_loader and 0 <= x < w_loader and x + len(text) <= w_loader:
                stdscr.addstr(y, x, text, attr)
            elif 0 <= y < h_loader and 0 <= x < w_loader :
                 stdscr.addstr(y, x, text[:w_loader-x-1], attr)
        
        if loading_line_y > 0 : safe_addstr_loader(loading_line_y -1 , title_x, title_message)
        elif loading_line_y >=0 : safe_addstr_loader(loading_line_y , title_x, title_message)

        # Filter out headers for cache building and progress count
        items_to_check_status_for = [name for name in item_definitions.keys() if not name.startswith(HEADER_PREFIX)]
        total_items_to_check = len(items_to_check_status_for)
        checked_count = 0
        
        log_message("Building item status cache (first run)...")
        initial_cache_build_start_time = time.time()

        if total_items_to_check > 0: # Only show progress if there are items to check
            for item_name_key in items_to_check_status_for:
                checked_count += 1
                progress_percent = (checked_count * 100) // total_items_to_check
                bar_width = 20; filled_len = int(bar_width * progress_percent // 100)
                bar = '#' * filled_len + '-' * (bar_width - filled_len)
                progress_prefix = f"[{bar}] {progress_percent}% "
                checking_text = "Checking: "
                available_for_name = w_loader - len(progress_prefix) - len(checking_text) - 4
                display_item_name_progress = item_name_key
                if len(item_name_key) > available_for_name and available_for_name > 0:
                    display_item_name_progress = item_name_key[:available_for_name] + "..."
                elif available_for_name <=0: display_item_name_progress = ""; checking_text = ""
                
                if loading_line_y < h_loader :
                    stdscr.move(loading_line_y, 0); stdscr.clrtoeol()
                    full_progress_message = f"{progress_prefix}{checking_text}{display_item_name_progress}"
                    safe_addstr_loader(loading_line_y, 0, full_progress_message[:w_loader-1])
                stdscr.refresh()
                status_cache[item_name_key] = get_package_status(item_name_key, suppress_logging=True)
        
        cache_build_duration = time.time() - initial_cache_build_start_time
        log_message(f"Item status cache built in {cache_build_duration:.2f}s for {checked_count} items.")
        if loading_line_y < h_loader:
            stdscr.move(loading_line_y, 0); stdscr.clrtoeol()
            final_cache_message = f"Cache built: {checked_count} items in {cache_build_duration:.2f}s."
            msg_x_final = max(0, (w_loader - len(final_cache_message)) // 2)
            safe_addstr_loader(loading_line_y, msg_x_final, final_cache_message[:w_loader-1])
            stdscr.refresh()
            time.sleep(1.0)
        build_done_flag_container[0] = True
        
    return display_menu(stdscr, item_definitions, status_cache)


def display_menu(stdscr, item_definitions, status_cache):
    curses.curs_set(0) # Already set by wrapper, but safe

    item_names = list(item_definitions.keys()) # Preserve definition order
    if not item_names:
        stdscr.addstr(0,0, "No items loaded."); stdscr.refresh(); time.sleep(1); stdscr.getch()
        return None

    checked_items = {name: False for name in item_names if not name.startswith(HEADER_PREFIX)}
    select_all_items = False
    highlighted_linear_idx = 0
    display_column_offset = 0

    while True:
        try:
            stdscr.clear()
            height, width = stdscr.getmaxyx()

            footer_content_height = 8 
            footer_height_needed = footer_content_height + 1
            
            if height < footer_height_needed + 1 or width < 50:
                stdscr.attron(curses.color_pair(3))
                stdscr.addstr(0, 0, "Terminal too small.")
                stdscr.addstr(1,0, "Press Q to quit or resize.")
                stdscr.attroff(curses.color_pair(3))
                stdscr.refresh()
                key = stdscr.getch()
                if key == ord('q') or key == ord('Q'): return None
                continue

            # Calculate max_text_len_for_item considering games and formatted headers
            max_len_game_name_only = 0
            game_item_names = [n for n in item_names if not n.startswith(HEADER_PREFIX)]
            if game_item_names:
                max_len_game_name_only = max(len(name) for name in game_item_names)
            max_game_line_len = 4 + max_len_game_name_only + 2 # "[X] " + name + " ✓"

            max_len_formatted_header = 0
            header_item_names = [n for n in item_names if n.startswith(HEADER_PREFIX)]
            if header_item_names:
                 max_len_formatted_header = max(len(get_formatted_header_text(h_name)) for h_name in header_item_names)
            
            max_text_len_for_item = max(max_game_line_len, max_len_formatted_header, 10) # Min width 10
            
            option_padding = 2 
            option_width_on_screen = max_text_len_for_item + option_padding
            num_display_columns_on_screen = max(1, width // option_width_on_screen)
            num_display_rows = height - footer_height_needed 
            if num_display_rows < 1: num_display_rows = 1

            total_logical_columns = (len(item_names) + num_display_rows - 1) // num_display_rows if num_display_rows > 0 else 1
            max_possible_offset = max(0, total_logical_columns - num_display_columns_on_screen)
            display_column_offset = max(0, min(display_column_offset, max_possible_offset))

            highlighted_linear_idx = max(0, min(highlighted_linear_idx, len(item_names) -1 if item_names else 0))
            current_highlighted_logical_col = highlighted_linear_idx // num_display_rows if num_display_rows > 0 else 0
            current_highlighted_row_in_col = highlighted_linear_idx % num_display_rows if num_display_rows > 0 else 0

            for idx, item_name in enumerate(item_names):
                is_header = item_name.startswith(HEADER_PREFIX)
                logical_col_of_item = idx // num_display_rows if num_display_rows > 0 else 0
                display_row_of_item = idx % num_display_rows if num_display_rows > 0 else 0
                screen_col_to_draw_in = logical_col_of_item - display_column_offset

                if not (0 <= screen_col_to_draw_in < num_display_columns_on_screen): continue
                if display_row_of_item >= num_display_rows: continue

                screen_x = screen_col_to_draw_in * option_width_on_screen
                screen_y = display_row_of_item
                if screen_x + max_text_len_for_item > width : continue

                display_string = ""
                current_attributes = curses.color_pair(2) # Default

                if is_header:
                    display_string = get_formatted_header_text(item_name)
                    current_attributes |= curses.A_BOLD # Make headers bold
                else: # It's a game/package
                    checkbox = "[X]" if checked_items.get(item_name, False) else "[ ]" # Use .get for safety
                    status = status_cache.get(item_name, PACKAGE_STATUS_CHECK_ERROR)
                    item_marker = ""
                    if status == PACKAGE_STATUS_INSTALLED:
                        current_attributes = curses.color_pair(4) # Green
                        item_marker = " ✓"
                    elif status == PACKAGE_STATUS_AVAILABLE:
                        current_attributes = curses.color_pair(2) # Normal
                    elif status == PACKAGE_STATUS_NOT_AVAILABLE or status == PACKAGE_STATUS_CHECK_ERROR:
                        current_attributes = curses.color_pair(2) | curses.A_DIM # Dimmed
                    display_string = f"{checkbox} {item_name}{item_marker}"
                
                display_string_padded = display_string.ljust(max_text_len_for_item)
                
                final_attributes_to_apply = current_attributes
                if idx == highlighted_linear_idx:
                    final_attributes_to_apply = curses.color_pair(1) # Highlighted
                    if is_header: # Optionally make highlighted headers also bold
                        final_attributes_to_apply |= curses.A_BOLD
                
                if 0 <= screen_y < height and 0 <= screen_x < width:
                     stdscr.addstr(screen_y, screen_x, display_string_padded[:width-screen_x], final_attributes_to_apply)

            # ... (Footer drawing logic - same as previous full script, ensure it uses safe_addstr_footer) ...
            # Make sure footer section correctly calculates its y positions based on num_display_rows
            air_gap_line = num_display_rows 
            instruction_y_base = air_gap_line + 1
            instr_line_y = instruction_y_base
            
            def draw_line_safely(y, content_parts): # Helper for footer
                if y < height:
                    stdscr.move(y, 0)
                    current_x = 0
                    for part_text, part_attr in content_parts:
                        if current_x < width -1:
                           drawable_len = min(len(part_text), width - 1 - current_x)
                           stdscr.addstr(part_text[:drawable_len], part_attr)
                           current_x += drawable_len
                        else: break
                    stdscr.clrtoeol()

            draw_line_safely(instr_line_y, [("Arrows/PgUp/PgDn/Home/End. Space=toggle. Ctrl+A=all.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("", curses.A_BOLD), ("'I'", curses.color_pair(5) | curses.A_BOLD),(" to install ", curses.A_BOLD), ("selected", curses.color_pair(2) | curses.A_BOLD),(". ", curses.A_BOLD), ("'Q'", curses.color_pair(5) | curses.A_BOLD),(" to quit.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("Green text ✓", curses.color_pair(4) | curses.A_BOLD),(" = Installed.", curses.A_BOLD)])
            instr_line_y+=1
            draw_line_safely(instr_line_y, [("Dimmed text", curses.color_pair(2) | curses.A_DIM | curses.A_BOLD),(" = Not in repos / Error.", curses.A_BOLD)])
            instr_line_y+=1
            page_info_text = f"Cols: 1-{total_logical_columns} of {total_logical_columns}"
            if total_logical_columns > num_display_columns_on_screen:
                start_col_num = display_column_offset + 1
                end_col_num = min(display_column_offset + num_display_columns_on_screen, total_logical_columns)
                page_info_text = f"Cols: {start_col_num}-{end_col_num} of {total_logical_columns} (Left/Right to page)"
            draw_line_safely(instr_line_y, [(page_info_text, curses.A_BOLD)])
            instr_line_y+=1

            description_area_y_start = instr_line_y
            if item_names and 0 <= highlighted_linear_idx < len(item_names):
                current_item_name = item_names[highlighted_linear_idx]
                is_current_header = current_item_name.startswith(HEADER_PREFIX)
                
                status_desc_marker = ""
                if not is_current_header:
                    current_status = status_cache.get(current_item_name, PACKAGE_STATUS_CHECK_ERROR)
                    if current_status == PACKAGE_STATUS_INSTALLED: status_desc_marker = " (INSTALLED)"
                    elif current_status == PACKAGE_STATUS_NOT_AVAILABLE: status_desc_marker = " (NOT IN REPOS)"
                    elif current_status == PACKAGE_STATUS_CHECK_ERROR: status_desc_marker = " (STATUS CHECK ERROR)"

                desc_display_name = current_item_name[len(HEADER_PREFIX):].strip() if is_current_header else current_item_name
                desc_header = f"Desc of {desc_display_name}{status_desc_marker}:"
                if description_area_y_start < height: stdscr.addstr(description_area_y_start, 0, desc_header[:width-1])
                
                actual_desc_text = item_definitions.get(current_item_name, "No description available.")
                if description_area_y_start + 1 < height: stdscr.addstr(description_area_y_start + 1, 0, actual_desc_text[:width-1])
            stdscr.refresh()

            key = stdscr.getch()
            num_items = len(item_names)
            if not num_items: continue
            
            # --- Key handling ---
            if key == curses.KEY_UP:
                if current_highlighted_row_in_col > 0: highlighted_linear_idx -= 1
                elif current_highlighted_logical_col > 0: 
                    highlighted_linear_idx = (current_highlighted_logical_col - 1) * num_display_rows + (num_display_rows -1)
                    highlighted_linear_idx = min(highlighted_linear_idx, num_items -1) 
            elif key == curses.KEY_DOWN:
                if current_highlighted_row_in_col < num_display_rows - 1 and highlighted_linear_idx + 1 < num_items: highlighted_linear_idx += 1
                elif current_highlighted_logical_col + 1 < total_logical_columns and \
                     (current_highlighted_logical_col + 1) * num_display_rows < num_items : highlighted_linear_idx = (current_highlighted_logical_col + 1) * num_display_rows
            elif key == curses.KEY_LEFT:
                if current_highlighted_logical_col > 0:
                    new_idx_target = (current_highlighted_logical_col - 1) * num_display_rows + current_highlighted_row_in_col
                    max_idx_in_prev_col = min( (current_highlighted_logical_col * num_display_rows) -1 , num_items -1)
                    highlighted_linear_idx = min(new_idx_target, max_idx_in_prev_col)
            elif key == curses.KEY_RIGHT:
                if current_highlighted_logical_col < total_logical_columns - 1:
                    new_idx_target = (current_highlighted_logical_col + 1) * num_display_rows + current_highlighted_row_in_col
                    highlighted_linear_idx = min(new_idx_target, num_items - 1)
            elif key == curses.KEY_PPAGE: highlighted_linear_idx = max(0, highlighted_linear_idx - num_display_rows)
            elif key == curses.KEY_NPAGE: highlighted_linear_idx = min(num_items - 1, highlighted_linear_idx + num_display_rows)
            elif key == curses.KEY_HOME: highlighted_linear_idx = 0
            elif key == curses.KEY_END: highlighted_linear_idx = num_items - 1
            elif key == ord(" "): 
                if 0 <= highlighted_linear_idx < num_items:
                    item_to_toggle = item_names[highlighted_linear_idx]
                    if not item_to_toggle.startswith(HEADER_PREFIX): # Can't toggle headers
                        status_toggle = status_cache.get(item_to_toggle, PACKAGE_STATUS_CHECK_ERROR)
                        if status_toggle == PACKAGE_STATUS_INSTALLED or status_toggle == PACKAGE_STATUS_AVAILABLE:
                            checked_items[item_to_toggle] = not checked_items[item_to_toggle]
                        else: curses.flash()
                    else: curses.flash() # Flash if trying to toggle header
            elif key == 1:  # Ctrl+A
                select_all_items = not select_all_items
                for item_name_iter in item_names:
                    if not item_name_iter.startswith(HEADER_PREFIX): # Only select/deselect actual items
                        status_toggle_all = status_cache.get(item_name_iter, PACKAGE_STATUS_CHECK_ERROR)
                        if status_toggle_all == PACKAGE_STATUS_INSTALLED or status_toggle_all == PACKAGE_STATUS_AVAILABLE:
                            checked_items[item_name_iter] = select_all_items
                        elif not select_all_items: # If deselecting all, ensure it's deselected
                           checked_items[item_name_iter] = False
            elif key == ord("i") or key == ord("I") : 
                selected_to_install = [item for item, is_checked in checked_items.items() if is_checked and not item.startswith(HEADER_PREFIX)]
                return selected_to_install 
            elif key == ord("q") or key == ord("Q"):
                return None 
            elif key == curses.KEY_RESIZE: pass

            if num_items > 0: # Auto-paging logic
                highlighted_linear_idx = max(0, min(highlighted_linear_idx, num_items - 1))
                new_curr_hl_logical_col = highlighted_linear_idx // num_display_rows if num_display_rows > 0 else 0
                
                if new_curr_hl_logical_col >= display_column_offset + num_display_columns_on_screen:
                    display_column_offset = min(max_possible_offset, display_column_offset + num_display_columns_on_screen)
                elif new_curr_hl_logical_col < display_column_offset:
                    display_column_offset = max(0, display_column_offset - num_display_columns_on_screen)
                
                if key == curses.KEY_HOME: display_column_offset = 0
                elif key == curses.KEY_END:
                    if num_display_rows > 0:
                        last_item_logical_col = (num_items - 1) // num_display_rows
                        display_column_offset = max(0, last_item_logical_col - num_display_columns_on_screen + 1)
                        display_column_offset = min(display_column_offset, max_possible_offset)
        except curses.error as e: 
            log_message(f"Curses error in display_menu: {e}")
            if "ERR" in str(e) or "addwstr" in str(e) or "addstr" in str(e) or "waddwstr" in str(e): time.sleep(0.05) 
            else: raise 
        except Exception as e: 
            log_message(f"Unexpected error in display_menu: {e}, {type(e)}")
            raise

# (install_selected_items function remains the same as the one that takes status_cache_to_update)
def install_selected_items(selected_items_list, item_definitions_dict, status_cache_to_update):
    if not selected_items_list:
        print("No items were selected for installation.")
        return

    items_to_actually_install = []
    successfully_installed_in_batch = [] 
    already_installed_skipped = []
    not_available_skipped = []
    error_checking_skipped = []

    log_message("Verifying selected item statuses before attempting installation...")
    for item_name in selected_items_list:
        current_status_in_cache = status_cache_to_update.get(item_name, PACKAGE_STATUS_CHECK_ERROR)
        if item_name.startswith(HEADER_PREFIX): continue # Should not happen if selection logic is correct

        if current_status_in_cache == PACKAGE_STATUS_INSTALLED:
            already_installed_skipped.append(item_name)
        elif current_status_in_cache == PACKAGE_STATUS_NOT_AVAILABLE:
            not_available_skipped.append(item_name)
        elif current_status_in_cache == PACKAGE_STATUS_CHECK_ERROR:
            error_checking_skipped.append(item_name)
        elif current_status_in_cache == PACKAGE_STATUS_AVAILABLE:
            items_to_actually_install.append(item_name)
        else:
             log_message(f"Unknown status '{current_status_in_cache}' for {item_name} during install prep. Skipping.")
             error_checking_skipped.append(f"{item_name} (unknown status: {current_status_in_cache})")
    
    if already_installed_skipped: print(f"Skipping (already installed): {', '.join(already_installed_skipped)}")
    if not_available_skipped: print(f"Skipping (not in repos): {', '.join(not_available_skipped)}")
    if error_checking_skipped: print(f"Skipping (error/unknown status): {', '.join(error_checking_skipped)}")

    if not items_to_actually_install:
        print("No new items left to install from selection.")
        return
    
    overall_start_time = time.time()
    print(f"\nPreparing to install {len(items_to_actually_install)} item(s): {', '.join(items_to_actually_install)}")
    items_string = " ".join(items_to_actually_install)
    install_command = INSTALL_COMMAND_TEMPLATE.format(packages=items_string)
    print(f"Command: {install_command}\n")
    
    try:
        process = subprocess.Popen(install_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        if process.stdout:
            for line in iter(process.stdout.readline, ''): print(line, end='')
            process.stdout.close()
        process.wait()

        if process.returncode == 0:
            log_message(f"Apt install command potentially successful for: {', '.join(items_to_actually_install)}")
            print("\n✓ Installation process completed for attempted items. Verifying statuses...")
            for item_name_verify in items_to_actually_install: 
                new_status = get_package_status(item_name_verify)
                status_cache_to_update[item_name_verify] = new_status 
                if new_status == PACKAGE_STATUS_INSTALLED:
                    print(f"  ✓ {item_name_verify} is now INSTALLED.")
                    successfully_installed_in_batch.append(item_name_verify)
                else:
                    print(f"  ✗ {item_name_verify} still not INSTALLED (status: {new_status}). Apt reported success but verification failed or it's in a different state.")
        else:
            print(f"\n✗ Installation command failed (RC:{process.returncode}) for: {', '.join(items_to_actually_install)}")
            log_message(f"Command failed (code {process.returncode}): {install_command}")
            print("Re-checking status of items that apt reported errors for...")
            for item_name_failed in items_to_actually_install: # Re-check all attempted if batch failed
                 status_cache_to_update[item_name_failed] = get_package_status(item_name_failed, suppress_logging=True)
    except Exception as e:
        print(f"An unexpected error occurred during installation: {e}")
        log_message(f"Exception during installation command '{install_command}': {e}")
    
    total_runtime = time.time() - overall_start_time
    print(f"\nInstallation attempt finished for batch. Runtime: {total_runtime:.2f} seconds.")

# (main function remains the same as the one with the 'Install More?' loop and session cache)
def main():
    def graceful_signal_handler(sig, frame):
        if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
            try: curses.nocbreak(); curses.echo(); curses.endwin()
            except: pass
        print("\nProgram terminated by user (Ctrl+C).")
        log_message("Program terminated by SIGINT.")
        sys.exit(0)

    signal.signal(signal.SIGINT, graceful_signal_handler)

    active_item_collection = ESSENTIAL_APPS 
    collection_name_for_messages = "ESSENTIAL_APPS" 

    if not active_item_collection:
        print(f"No items defined in {collection_name_for_messages}. Nothing to do.")
        log_message(f"{collection_name_for_messages} dictionary is empty.")
        return

    session_item_status_cache = {}
    cache_build_done_flag_container = [False] 

    while True: 
        selected_items_for_action = None
        try:
            # run_menu_session_with_cache_build calls display_menu
            # display_menu now returns a single list (selected) or None (quit)
            selected_items_for_action = curses.wrapper(
                run_menu_session_with_cache_build, 
                active_item_collection, 
                session_item_status_cache, 
                cache_build_done_flag_container
            )
        except RuntimeError as e: 
            print(f"Error: {e}")
            log_message(f"RuntimeError from menu session: {e}")
            break 
        except Exception as e: 
            if 'curses' in sys.modules and hasattr(curses, 'isendwin') and not curses.isendwin():
                try: curses.endwin()
                except: pass
            print(f"An unexpected error occurred running the menu: {e}")
            log_message(f"Unhandled exception in main around curses.wrapper: {e}, {type(e)}")
            break 

        if selected_items_for_action is None: 
            log_message("User quit the menu.")
            break 
        elif not selected_items_for_action: 
            log_message("User proceeded from menu but no items were checked.")
            if not ask_to_continue("No items checked. Return to menu?"):
                break
            else:
                continue 
        else:
            print("\nThe following items were marked for installation:")
            for item_name in selected_items_for_action: print(f"- {item_name}")

            if not ask_to_continue("Proceed with installation?"):
                log_message("User cancelled installation at confirmation prompt.")
                if not ask_to_continue("Return to menu?"): 
                    break
                else:
                    continue 
            
            log_message(f"User confirmed. Selected items for installation: {selected_items_for_action}")
            install_selected_items(selected_items_for_action, active_item_collection, session_item_status_cache)

        if not ask_to_continue("Would you like to install more items?"):
            break 

    print("Exiting program.")
    log_message(f"Script {os.path.basename(__file__)} finished.")

# (ask_to_continue function remains the same)
def ask_to_continue(prompt_message):
    while True:
        try:
            response = input(f"{prompt_message} (y/N): ").strip().lower()
            if response in ['y', 'yes']: return True
            elif response in ['', 'n', 'no']: return False
            else: print("Invalid input. Please enter 'y' or 'n'.")
        except EOFError: print("\nNo input received, assuming No."); return False
        except KeyboardInterrupt: print("\nSelection cancelled by user."); return False

if __name__ == "__main__":
    script_name = os.path.basename(__file__)
    try:
        log_dir = os.path.dirname(LOG_FILE)
        if log_dir and not os.path.exists(log_dir): 
            os.makedirs(log_dir, exist_ok=True)
        with open(LOG_FILE, "a") as f: 
            f.write(f"{datetime.now()}: === {script_name} session started ===\n")
    except Exception as e: 
        print(f"Warning: Could not initialize logging for {LOG_FILE}: {e}", file=sys.stderr)

    if not sys.stdout.isatty():
        print("Error: This script uses curses and must be run in a terminal.", file=sys.stderr)
        log_message("Script aborted: Not running in a TTY.")
        sys.exit(1)
        
    log_message(f"Starting {script_name} script.") 
    main()
