#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02
import os
import curses
import subprocess
import time
import signal
import sys
from datetime import datetime

LOG_FILE = "/tmp/python_app_installer_menus.log"

# Associative array of essential apps and their descriptions
ESSENTIAL_APPS = {
    "ack-grep": "A tool like grep, optimized for programmers (often 'ack' or 'ack-grep' package).",
    "ansible": "Configuration management, deployment, and task execution system.",
    "apache2": "Apache HTTP Server.",
    "awscli": "AWS Command Line Interface.",
    "bat": "cat(1) clone with syntax highlighting and Git integration (package often 'bat' or 'batcat').",
    "bc": "An arbitrary precision calculator language.",
    "btop": "Modern TUI resource monitor, shows usage and stats for processor, memory, disks, network and processes.",
    "build-essential": "Development tools meta-package (gcc, g++, make, etc.).",
    "busybox": "Collected common console tools in a single small executable.",
    "cargo": "Rust package manager and build system (often installed with rustc).",
    "certbot": "Automatically enable HTTPS on your website with Let's Encrypt.",
    "chkrootkit": "Rootkit detection tool.",
    "clamav": "Open-source antivirus engine.",
    "clang": "Alternative C/C++/Objective-C compiler (LLVM based).",
    "cmake": "Cross-platform build system generator.",
    "cpio": "Tool to copy files into or out of a cpio or tar archive.",
    "curl": "Command line tool for transferring data with URL syntax.",
    "default-jdk": "Java Development Kit (standard OpenJDK version).",
    "dnsutils": "DNS utilities (dig, nslookup, nsupdate).",
    "docker-compose": "Define and run multi-container Docker applications.",
    "docker.io": "Linux container runtime (Docker Engine).",
    "dstat": "Versatile resource statistics tool (replacement for vmstat, iostat, netstat).",
    "emacs": "Extensible, customizable, self-documenting real-time display editor.",
    "fail2ban": "Daemon to ban hosts that cause multiple authentication errors.",
    "fdupes": "Identifies and deletes duplicate files.",
    "ffmpeg": "Tools for recording, converting and streaming audio and video.",
    "flatpak": "Application sandboxing and distribution framework ('app stores').",
    "gcc": "GNU C Compiler.",
    "gdb": "GNU Debugger.",
    "git": "Fast, scalable, distributed revision control system.",
    "goaccess": "Real-time web log analyzer and interactive viewer for terminal or browser.",
    "golang": "Go programming language compiler, tools, and libraries (metapackage, consider 'golang-go').",
    "google-cloud-sdk": "Command-line tools for Google Cloud Platform.",
    "gparted": "GUI partition editor for managing disk partitions.",
    "gradle": "Powerful build automation tool for Java, Groovy, Scala, etc.",
    "htop": "Interactive process viewer and manager.",
    "iftop": "Network bandwidth monitor (displays bandwidth usage on an interface).",
    "inxi": "Comprehensive command-line system information tool.",
    "iotop": "Monitor disk I/O usage by processes.",
    "john": "Password cracking tool (John the Ripper).",
    "jq": "Command-line JSON processor.",
    "jupyter-notebook": "Web-based interactive computational environment (Jupyter Notebook).",
    "kubeadm": "Tool for bootstrapping a Kubernetes cluster.",
    "kubectl": "Command-line tool for controlling Kubernetes clusters.",
    "kubelet": "Primary node agent that runs on each Kubernetes node.",
    "libxml2-utils": "Utilities for XML manipulation (xmllint).",
    "lsof": "List open files by processes.",
    "lynis": "System security auditing tool.",
    "maven": "Java project management and comprehension tool (Apache Maven).",
    "mc": "Midnight Commander - a console-based file manager.",
    "mlr": "Miller - like awk, sed, cut, join, and sort for CSV, TSV, JSON, and more.",
    "mtr": "Network diagnostic tool (combines ping and traceroute).",
    "mysql-server": "MySQL database server.",
    "nano": "Simple, modeless text editor for the console.",
    "ncdu": "NCurses Disk Usage analyzer.",
    "neovim": "Vim-fork focused on extensibility and usability.",
    "net-tools": "Networking utilities (arp, ifconfig, netstat, route).",
    "nginx": "High-performance web server, reverse proxy, and load balancer.",
    "nmap": "Network exploration tool and security/port scanner.",
    "nodejs": "Node.js event-based server-side JavaScript runtime.",
    "ntp": "Network Time Protocol daemon and utility programs for time synchronization.",
    "openssh-client": "Secure shell (SSH) client for remote login.",
    "openssh-server": "Secure Shell (SSH) server for remote access.",
    "p7zip-full": "Full 7z and p7zip archive support (compression/decompression).",
    "pandoc": "Universal document converter (Markdown, HTML, PDF, LaTeX, etc.).",
    "parted": "Command-line partition manipulation program.",
    "php": "PHP server-side scripting language (metapackage).",
    "php-cli": "Command-line interpreter for PHP.",
    "php-curl": "cURL module for PHP.",
    "php-fpm": "FastCGI Process Manager for PHP.",
    "php-gd": "GD module for PHP (image manipulation).",
    "php-mbstring": "MBSTRING module for PHP (multibyte string functions).",
    "php-mysql": "MySQL module for PHP.",
    "php-pgsql": "PostgreSQL module for PHP.",
    "php-xml": "XML module for PHP.",
    "php-zip": "Zip module for PHP.",
    "postgresql": "Object-relational SQL database server (PostgreSQL).",
    "postgresql-contrib": "Contributed extensions and utilities for PostgreSQL.",
    "pulseaudio": "PulseAudio sound server.",
    "python3-certbot-apache": "Apache plugin for Certbot.",
    "python3-certbot-nginx": "Nginx plugin for Certbot.",
    "python3-csvkit": "csvkit: a suite of command-line tools for converting and working with CSV.",
    "python3-pip": "Python package installer for Python 3.",
    "python3-virtualenv": "Tool to create isolated Python environments (for Python 3).",
    "rclone": "Command-line program to manage files on cloud storage.",
    "rsync": "Fast, versatile remote (and local) file-copying tool.",
    "ruby-full": "Ruby programming language (full installation including headers).",
    "rustc": "Rust compiler.",
    "samba": "SMB/CIFS file, print, and login server for Unix.",
    "screen": "Terminal multiplexer with VT100/ANSI terminal emulation.",
    "silversearcher-ag": "A code-searching tool similar to ack, but faster (the_silver_searcher).",
    "snapd": "Daemon and tooling that enables snap packages.",
    "sysstat": "Performance monitoring tools for Linux (sar, iostat, mpstat).",
    "tcpdump": "Command-line network packet analyzer.",
    "terraform": "Infrastructure as Code software by HashiCorp.",
    "texlive-full": "TeX Live: A comprehensive TeX document production system (very large).",
    "timeshift": "System restore utility for Linux (similar to Time Machine or System Restore).",
    "tmux": "Terminal multiplexer, enables multiple terminals in one screen.",
    "traceroute": "Prints the route packets trace to network host.",
    "tree": "Displays directory contents in a tree-like format.",
    "ufw": "Uncomplicated Firewall - a simple interface for iptables.",
    "unrar": "Utility for extracting, testing and viewing RAR archives.",
    "unzip": "Utility for extracting and viewing files in ZIP archives.",
    "util-linux": "Miscellaneous system utilities (includes lsblk, fdisk, dmesg, etc.).",
    "vagrant": "Tool for building and managing virtual machine environments.",
    "valgrind": "Instrumentation framework for building dynamic analysis tools (memory debugging, profiling).",
    "vim": "Vi IMproved - a highly configurable text editor.",
    "vim-nox": "Vim compiled with support for scripting (Perl, Python, Ruby, Tcl) but no GUI.",
    "virtualbox": "x86 virtualization solution (Oracle VM VirtualBox).",
    "virtualbox-ext-pack": "VirtualBox extension pack (USB 2.0/3.0, RDP, PXE boot - check license).",
    "wget": "Non-interactive network downloader.",
    "whois": "Client for the WHOIS directory service (domain/IP lookup).",
    "xmlstarlet": "Command line XML toolkit for querying, validating, and transforming XML.",
    "zip": "Utility for packaging and compressing (archiving) files.",
    "zsh": "Z Shell - a powerful command-line interpreter."
}

INSTALL_COMMAND_TEMPLATE = "sudo apt-get install -y {packages}"

def log_message(message):
    with open(LOG_FILE, "a") as log_file:
        log_file.write(f"{datetime.now()}: {message}\n")

def display_menu(stdscr, app_definitions):
    curses.curs_set(0)
    curses.start_color()
    curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Highlighted
    curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)  # Normal
    curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # Error

    app_names = sorted(list(app_definitions.keys()))
    if not app_names:
        stdscr.addstr(0,0, "No applications loaded. Check ESSENTIAL_APPS.")
        stdscr.refresh()
        time.sleep(2)
        stdscr.getch()
        return None

    checked_apps = {app_name: False for app_name in app_names}
    select_all_apps = False
    
    # Grid navigation variables
    current_grid_row = 0    # Current row in the displayed grid column
    current_grid_col = 0    # Current column in the displayed grid
    highlighted_linear_idx = 0 # Linear index of the highlighted app

    while True:
        try:
            stdscr.clear()
            height, width = stdscr.getmaxyx()

            # Minimum size check
            footer_height_needed = 5 # For instructions and description lines
            if height < footer_height_needed + 1 or width < 20: # Need at least 1 row for items
                stdscr.attron(curses.color_pair(3))
                stdscr.addstr(0, 0, "Terminal too small.")
                stdscr.attroff(curses.color_pair(3))
                stdscr.refresh()
                time.sleep(1)
                key = stdscr.getch()
                if key == ord('q') or key == ord('Q'): return None
                continue

            # Calculate columns and rows for the grid
            # Max app name length plus "[X] " prefix and a little padding
            max_app_name_len = 0
            if app_names:
                 max_app_name_len = max(len(name) for name in app_names)
            
            option_width_on_screen = max_app_name_len + 4 + 2 # [X] name  <space><space>
            num_display_columns = max(1, width // option_width_on_screen)
            
            # num_display_rows is how many items fit vertically in each column of the grid
            num_display_rows = height - footer_height_needed 
            if num_display_rows < 1: num_display_rows = 1


            # Ensure highlighted_linear_idx is valid (e.g. after resize or if list is short)
            highlighted_linear_idx = max(0, min(highlighted_linear_idx, len(app_names) -1))
            if not app_names: highlighted_linear_idx = 0


            # Update current_grid_col and current_grid_row based on highlighted_linear_idx
            # Items are laid out column by column.
            # So, col_index = linear_idx // num_items_per_col_on_screen
            #    row_index_in_col = linear_idx % num_items_per_col_on_screen
            if num_display_rows > 0 : # Avoid division by zero if num_display_rows is 0
                current_grid_col = highlighted_linear_idx // num_display_rows
                current_grid_row = highlighted_linear_idx % num_display_rows
            else: # Should not happen if height check is correct
                current_grid_col = 0
                current_grid_row = 0


            # Display the menu in a grid layout
            for idx, app_name in enumerate(app_names):
                # Determine the display col and row for this app_name
                display_col_for_item = idx // num_display_rows
                display_row_for_item = idx % num_display_rows
                
                # Only draw if it's within the visible grid area
                if display_row_for_item >= num_display_rows: # Item is too far down to fit in any column
                    continue 

                screen_x = display_col_for_item * option_width_on_screen
                screen_y = display_row_for_item

                if screen_x + option_width_on_screen > width : # Item is in a column that's off screen
                    continue


                checkbox = "[X]" if checked_apps[app_name] else "[ ]"
                display_string = f"{checkbox} {app_name}"
                
                # Truncate display_string to fit within the allocated column width
                # -1 for safety with addstr
                max_len_in_col = option_width_on_screen - 2 
                display_string = display_string[:max_len_in_col]


                if idx == highlighted_linear_idx:
                    stdscr.attron(curses.color_pair(1))
                    stdscr.addstr(screen_y, screen_x, display_string)
                    stdscr.attroff(curses.color_pair(1))
                else:
                    stdscr.attron(curses.color_pair(2))
                    stdscr.addstr(screen_y, screen_x, display_string)
                    stdscr.attroff(curses.color_pair(2))
            
            # --- Footer and Descriptions ---
            footer_y_start = num_display_rows 
            
            instruction_line1 = "Arrows/PgUp/PgDn/Home/End. Space to toggle. Ctrl+A all."
            instruction_line2 = "'I' to install selected. 'Q' to quit."
            
            if footer_y_start < height:
                 stdscr.addstr(footer_y_start, 0, instruction_line1[:width-1], curses.A_BOLD)
            if footer_y_start + 1 < height:
                 stdscr.addstr(footer_y_start + 1, 0, instruction_line2[:width-1], curses.A_BOLD)

            description_area_y_start = footer_y_start + 2
            if app_names and highlighted_linear_idx < len(app_names):
                current_app_name = app_names[highlighted_linear_idx]
                
                if description_area_y_start < height:
                    desc_header = f"Description of {current_app_name}:"
                    stdscr.addstr(description_area_y_start, 0, desc_header[:width-1])

                actual_desc_text = app_definitions.get(current_app_name, "No description available.")
                if not isinstance(actual_desc_text, str): actual_desc_text = str(actual_desc_text)

                desc_content_lines = actual_desc_text.split('\n')
                for i, line_content in enumerate(desc_content_lines):
                    current_print_y = description_area_y_start + 1 + i
                    if current_print_y < height:
                        stdscr.addstr(current_print_y, 0, line_content[:width-1])
                    else:
                        break
            stdscr.refresh()

            # --- Handle user input ---
            key = stdscr.getch()
            num_apps = len(app_names)
            if not num_apps: continue # Should not happen if initial check is good

            # Recalculate current linear index before navigation
            # This is important if num_display_rows changed due to resize
            # highlighted_linear_idx = current_grid_col * num_display_rows + current_grid_row
            # highlighted_linear_idx = max(0, min(highlighted_linear_idx, num_apps - 1))


            if key == curses.KEY_UP:
                # highlighted_linear_idx = (current_grid_col * num_display_rows + current_grid_row - 1 + num_apps) % num_apps
                new_row = current_grid_row - 1
                if new_row >=0:
                    highlighted_linear_idx = current_grid_col * num_display_rows + new_row
                else: # wrap to bottom of previous column if not in first column
                    if current_grid_col > 0:
                        highlighted_linear_idx = (current_grid_col - 1) * num_display_rows + (num_display_rows -1)
                        # Clamp if previous col was shorter
                        highlighted_linear_idx = min(highlighted_linear_idx, num_apps -1)

            elif key == curses.KEY_DOWN:
                # highlighted_linear_idx = (current_grid_col * num_display_rows + current_grid_row + 1) % num_apps
                new_row = current_grid_row + 1
                potential_new_idx = current_grid_col * num_display_rows + new_row
                if new_row < num_display_rows and potential_new_idx < num_apps :
                    highlighted_linear_idx = potential_new_idx
                else: # wrap to top of next column
                    if (current_grid_col + 1) * num_display_rows < num_apps: # if next col exists
                         highlighted_linear_idx = (current_grid_col + 1) * num_display_rows
            
            elif key == curses.KEY_LEFT:
                if current_grid_col > 0:
                    new_col = current_grid_col -1
                    highlighted_linear_idx = new_col * num_display_rows + current_grid_row
                     # If that row doesn't exist in new_col (e.g. last item of new_col)
                    if highlighted_linear_idx >= (new_col +1) * num_display_rows and highlighted_linear_idx >=num_apps :
                        highlighted_linear_idx = min(num_apps -1, (new_col +1) * num_display_rows -1 ) # last item in that col
                    highlighted_linear_idx = min(highlighted_linear_idx, num_apps -1) # clamp

            elif key == curses.KEY_RIGHT:
                if (current_grid_col + 1) * num_display_rows < num_apps : # if there are items in the next column
                    new_col = current_grid_col + 1
                    highlighted_linear_idx = new_col * num_display_rows + current_grid_row
                    # If that row doesn't exist in new_col (e.g. last item of new_col)
                    # This can happen if the last column is not full.
                    if highlighted_linear_idx >= num_apps:
                         highlighted_linear_idx = num_apps -1 # Go to very last item
                    highlighted_linear_idx = min(highlighted_linear_idx, num_apps -1) # clamp


            elif key == curses.KEY_PPAGE:
                highlighted_linear_idx = max(0, highlighted_linear_idx - num_display_rows)
            elif key == curses.KEY_NPAGE:
                highlighted_linear_idx = min(num_apps - 1, highlighted_linear_idx + num_display_rows)
            elif key == curses.KEY_HOME:
                highlighted_linear_idx = 0
            elif key == curses.KEY_END:
                highlighted_linear_idx = num_apps - 1
            
            elif key == ord(" "):
                if num_apps > 0 and highlighted_linear_idx < num_apps:
                    app_to_toggle = app_names[highlighted_linear_idx]
                    checked_apps[app_to_toggle] = not checked_apps[app_to_toggle]
            elif key == 1:  # Ctrl+A
                select_all_apps = not select_all_apps
                for app_name_iter in app_names:
                    checked_apps[app_name_iter] = select_all_apps
            elif key == ord("i") or key == ord("I") or key == ord("x"):
                selected_to_install = [app for app, is_checked in checked_apps.items() if is_checked]
                return selected_to_install
            elif key == ord("q") or key == ord("Q"):
                return None
            elif key == curses.KEY_RESIZE:
                # Recalculate grid parameters in the next loop iteration
                # Ensure highlighted_linear_idx stays valid
                highlighted_linear_idx = max(0, min(highlighted_linear_idx, len(app_names) -1))
                pass

            # Ensure highlighted_linear_idx is always valid after navigation
            if num_apps > 0:
                 highlighted_linear_idx = max(0, min(highlighted_linear_idx, num_apps - 1))


        except curses.error as e:
            log_message(f"Curses error: {e}")
            if "addwstr" in str(e) or "addstr" in str(e): pass
            else:
                curses.endwin()
                print(f"A curses error occurred: {e}. Check log at {LOG_FILE}")
                sys.exit(1)
        except Exception as e:
            log_message(f"Unexpected error in display_menu: {e}")
            curses.endwin()
            print(f"An unexpected error occurred: {e}. Check log at {LOG_FILE}")
            sys.exit(1)

# ... (rest of the script: install_selected_apps, main, etc. remains the same) ...
def install_selected_apps(selected_apps):
    """Install the selected applications."""
    if not selected_apps:
        print("No applications were selected for installation.")
        return

    overall_start_time = time.time()
    app_start_times = {}

    print("-" * 40)
    print(f"Preparing to install {len(selected_apps)} application(s)...")
    print("-" * 40)

    apps_string = " ".join(selected_apps)
    install_command = INSTALL_COMMAND_TEMPLATE.format(packages=apps_string)
    
    start_time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    app_start_times["_batch_install_"] = start_time_str 

    print(f"Starting: {start_time_str} - Installation of: {', '.join(selected_apps)}")
    print(f"Command: {install_command}")
    print("-" * 40)
    
    try:
        process = subprocess.Popen(install_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        
        if process.stdout:
            for line in iter(process.stdout.readline, ''):
                print(line, end='')
            process.stdout.close() 
        
        process.wait() 
        
        if process.returncode == 0:
            print(f"\nSuccessfully processed: {', '.join(selected_apps)}")
            log_message(f"Successfully ran: {install_command}")
        else:
            print(f"\nInstallation command failed with error code {process.returncode} for: {', '.join(selected_apps)}")
            log_message(f"Command failed (code {process.returncode}): {install_command}")

    except FileNotFoundError:
        print(f"Error: The install command (e.g., sudo, apt-get) was not found. Is it in your PATH?")
        log_message(f"FileNotFoundError for command: {install_command}")
    except PermissionError:
        print(f"Error: Permission denied. Ensure you have rights to run: {install_command} (e.g. sudo access)")
        log_message(f"PermissionError for command: {install_command}")
    except Exception as e:
        print(f"An unexpected error occurred during installation: {e}")
        log_message(f"Exception during installation command '{install_command}': {e}")

    overall_end_time = time.time()

    print("-" * 40)
    print("Installation Summary:")
    for app_batch, start_t in app_start_times.items(): 
        print(f"{start_t} - Attempted installation of: {', '.join(selected_apps)}")
    
    final_end_time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{final_end_time_str} - Finished installation process.")
    total_runtime = overall_end_time - overall_start_time
    print(f"Total runtime for installation process: {total_runtime:.2f} seconds.")

def main():
    def signal_handler(sig, frame):
        try:
            curses.nocbreak()
            # stdscr is not defined here, so can't use it directly.
            # curses.echo() and curses.endwin() are general.
            curses.echo()
            curses.endwin()
        except:
            pass 
        print("\nProgram terminated by user (Ctrl+C).")
        log_message("Program terminated by SIGINT.")
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    if not ESSENTIAL_APPS:
        print("No applications defined in ESSENTIAL_APPS. Nothing to do.")
        log_message("ESSENTIAL_APPS dictionary is empty.")
        return

    selected_apps_to_install = []
    try:
        selected_apps_to_install = curses.wrapper(display_menu, ESSENTIAL_APPS)
    except curses.error as e: 
        print(f"A Curses error occurred: {e}. Check log for details at {LOG_FILE}.")
        log_message(f"Curses wrapper error: {e}")
        sys.exit(1)
    except Exception as e: 
        try: curses.endwin()
        except: pass
        print(f"An unexpected error occurred: {e}. Check log for details at {LOG_FILE}.")
        log_message(f"Unhandled exception in main during curses: {e}")
        sys.exit(1)
    
    if selected_apps_to_install is None: 
        print("No applications selected for installation. Exiting.")
        log_message("User quit the menu. No apps selected.")
    elif not selected_apps_to_install: 
        print("No applications were checked for installation.")
        log_message("User proceeded to install but no apps were checked.")
    else:
        print("\nThe following applications will be installed:")
        for app_name in selected_apps_to_install:
            print(f"- {app_name}")
        
        try:
            confirm = input("\nPress Enter to start installation, or type 'n' to cancel: ")
            if confirm.lower() == 'n':
                print("Installation cancelled by user.")
                log_message("Installation cancelled by user at confirmation prompt.")
                return
        except EOFError: 
            print("\nNo input received for confirmation, cancelling installation.")
            log_message("EOFError at confirmation prompt, cancelling.")
            return
        except KeyboardInterrupt: 
            print("\nInstallation cancelled by user (Ctrl+C at prompt).")
            log_message("Installation cancelled by SIGINT at confirmation prompt.")
            return

        print("\nProceeding with installation...\n")
        log_message(f"User confirmed. Selected apps for installation: {selected_apps_to_install}")
        install_selected_apps(selected_apps_to_install)

if __name__ == "__main__":
    script_name = os.path.basename(__file__)
    log_message(f"Starting {script_name} script.")
    main()
    log_message(f"Script {script_name} finished.")
