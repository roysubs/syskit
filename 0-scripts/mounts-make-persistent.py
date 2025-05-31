#!/usr/bin/env python3
# Author: Roy Wiseman 2025-01

import subprocess
import os
import shutil
import sys
import argparse
import re

# Regex to match the SOURCE[/SUBPATH] format
SUBPATH_SOURCE_RE = re.compile(r'^([^\[]+)\[([^\]]+)\]$')

def run_command(command):
    """Runs a shell command and returns its output or None on error."""
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            # check=True, # Don't raise error immediately, we'll check stderr for 'unknown column'
            shell=True
        )
        # Check for known errors like 'unknown column'
        if result.returncode != 0 and "unknown column" in result.stderr.lower():
             return None
        elif result.returncode != 0:
             print(f"Error executing command: {command}", file=sys.stderr)
             print(f"Stderr: {result.stderr.strip()}", file=sys.stderr)
             return None

        return result.stdout.strip()
    except FileNotFoundError:
        print(f"Command not found. Make sure '{command.split()[0]}' is in your PATH.", file=sys.stderr)
        return None
    except Exception as e:
        print(f"An unexpected error occurred running command: {e}", file=sys.stderr)
        return None


def parse_mount_output(output, include_sourcepath=False):
    """Parses the output of findmnt, optionally including SOURCEPATH."""
    mounts = []
    if not output:
        return mounts

    lines = output.splitlines()
    if not lines or len(lines) < 2:
        return mounts

    header = lines[0].split()
    data_lines = lines[1:]

    # Find column indices
    try:
        source_idx = header.index('SOURCE')
        target_idx = header.index('TARGET')
        fstype_idx = header.index('FSTYPE')
        options_idx = header.index('OPTIONS')
        sourcepath_idx = header.index('SOURCEPATH') if include_sourcepath and 'SOURCEPATH' in header else -1
    except ValueError as e:
        print(f"Error parsing findmnt header: {e}", file=sys.stderr)
        print("Please ensure findmnt output contains SOURCE, TARGET, FSTYPE, and OPTIONS columns.", file=sys.stderr)
        return []


    for line in data_lines:
        # Attempt to split line by spaces, being aware of paths/sources with spaces
        # This is a potential source of parsing issues for paths with spaces not quoted by findmnt -l
        parts = line.split()

        # --- Basic parsing assuming order ---
        if len(parts) < 4: continue # Need at least SOURCE, TARGET, FSTYPE, OPTIONS

        # --- Attempt to locate TARGET, FSTYPE, OPTIONS, SOURCE ---
        # We can try to locate known fields from the right, assuming TARGET is first,
        # then some fields, then OPTIONS, FSTYPE, SOURCE (potentially with spaces)
        # This is still fragile. Let's stick to simple split and acknowledge limitations with spaced paths.
        # The logic below uses simple split assuming SOURCE, TARGET, FSTYPE, OPTIONS are first fields.
        # This will fail if SOURCE or TARGET have spaces UNLESS findmnt quotes them (which -l doesn't reliably do).
        # The best parsing for -l is complex and involves column widths, which is beyond this scope.
        # We proceed with simple split, accepting that sources/targets with spaces might be misparsed.

        if include_sourcepath and sourcepath_idx != -1:
             # If SOURCEPATH is present, try parsing including it
             # This split needs to be smarter to handle potential spaces in SOURCE or TARGET before SOURCEPATH
             # Let's skip robust parsing here for now and rely on the simpler case working or filtering.
             # For now, if SOURCEPATH is available, assume basic parsing works OR that SOURCEPATH itself is correct.
             if len(parts) > sourcepath_idx:
                  source = " ".join(parts[:source_idx+1]) # Simple guess - source might be multiple words
                  target = " ".join(parts[source_idx+1:target_idx+1]) # Simple guess
                  fstype = parts[fstype_idx] # Likely correct
                  options = parts[options_idx].strip('[]') # Likely correct
                  source_path_val = " ".join(parts[sourcepath_idx:]) # SourcePath might be multiple words
             else:
                  continue # Skip malformed line
        else:
             # Standard case without SOURCEPATH
             if len(parts) >= 4:
                  source = parts[0]
                  target = parts[1]
                  fstype = parts[2]
                  options = parts[3].strip('[]')
                  source_path_val = None
             else:
                  continue # Skip malformed line


        mount_info = {
           'source': source,
           'target': target,
           'fstype': fstype,
           'options': options,
           'source_path': source_path_val
       }

        # Check if the source is in the DEVICE[/SUBPATH] format
        match = SUBPATH_SOURCE_RE.match(mount_info['source'])
        if match:
            mount_info['underlying_device'] = match.group(1)
            mount_info['subpath_on_device'] = match.group(2)
            mount_info['is_subpath_mount'] = True
        else:
            mount_info['is_subpath_mount'] = False

        mounts.append(mount_info)

    return mounts


def parse_fstab():
    """Parses the /etc/fstab file."""
    fstab_entries = {}
    fstab_path = '/etc/fstab'
    try:
        with open(fstab_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split()
                if len(parts) >= 2:
                    target = parts[1]
                    fstab_entries[target] = line
    except FileNotFoundError:
        print(f"{fstab_path} not found. This script is intended for Linux-like systems.", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error reading {fstab_path}: {e}", file=sys.stderr)
        return None
    return fstab_entries

def is_system_mount_target(mount_target):
    """Checks if a mount target path is likely a system/internal mount location."""
    system_prefixes = [
        '/', # Root filesystem (especially important for WSL)
        '/proc', '/sys', '/dev', '/run', '/snap',
        '/var/lib/docker',
        '/lost+found',
        '/init', # WSL specific init mount
        '/mnt/wsl', # WSL internal mounts (docker-desktop, etc.)
        '/mnt/wslg', # WSLg (GUI) mounts
        '/tmp/.X11-unix' # Standard X11 socket location (often tmpfs or bind)
        # Keep /mnt itself as it's common for user mounts like /mnt/sdX
        # Windows drive mounts like /mnt/c are filtered by fstype '9p'
    ]
    for prefix in system_prefixes:
        # Use startswith for most, exact match for '/' and '/init' if preferred, but startswith is safer
        if mount_target.startswith(prefix):
            return True
    return False

def is_dynamic_or_pseudo_filesystem_type(fstype):
    """Checks if a filesystem type is typically dynamic or pseudo."""
    dynamic_fstypes = [
        'proc', 'sysfs', 'devtmpfs', 'tmpfs', 'cgroup2', 'securityfs', 'pstore',
        'bpf', 'debugfs', 'tracefs', 'configfs', 'fusectl', 'mqueue',
        'hugetlbfs', 'rpc_pipefs', 'nsfs', 'fuse.gvfsd-fuse', 'autofs', 'nfsd',
        'overlay', 'squashfs',
        '9p', # WSL Windows drive mounts and some internal mounts
        'iso9660', # Often temporary CD/ISO mounts like for docker cli tools
        '/Docker/host' # Specific Docker Desktop mount fstype? (May vary)
    ]
    if fstype == 'none': # Keep none as potentially user-created bind mount
        return False
    return fstype in dynamic_fstypes


def generate_fstab_line(mount_info):
    """Generates a potential fstab line based on mount info."""
    source = mount_info['source']
    target = mount_info['target']
    fstype = mount_info['fstype']
    options = mount_info['options']
    is_subpath_mount = mount_info.get('is_subpath_mount', False)
    underlying_device = mount_info.get('underlying_device')
    subpath_on_device = mount_info.get('subpath_on_device')
    source_path = mount_info.get('source_path') # SOURCEPATH from findmnt (if available)


    # Determine if nofail should be added based on user's general logic
    should_add_nofail = (target != '/')

    fstab_source = source
    fstab_fstype = fstype
    fstab_options = options

    notes = [] # List to store notes about this generated line

    # --- Handle Subpath Mounts (often bind mounts) ---
    if is_subpath_mount:
        notes.append("Detected as a sub-directory mount.")
        # Use source_path if available (from SOURCEPATH column)
        if source_path:
             fstab_source = source_path
             notes.append(f"  Source path derived from findmnt SOURCEPATH: {fstab_source}")
        else:
             # Construct the assumed source path from DEVICE[/SUBPATH]
             if underlying_device and subpath_on_device:
                 # Assume the underlying device is mounted at /mnt/<device_name>
                 # Handle devices like /dev/sdb1, /dev/sda, /dev/loop0 etc.
                 # Strip /dev/ prefix
                 device_base_name = underlying_device.replace('/dev/', '')
                 # Attempt to remove partition numbers but keep loopX, etc.
                 device_short_name = device_base_name
                 if device_short_name.startswith('sd') or device_short_name.startswith('hd'):
                     device_short_name = re.sub(r'\d+$', '', device_short_name) # Remove trailing digits (sda1 -> sda)
                     device_short_name = re.sub(r'p\d+$', '', device_short_name) # Remove pX like sda1p1 -> sda1

                 # Special case for /mnt/none seen in WSLg binds - use the source part directly
                 if underlying_device == '/mnt/none':
                      assumed_source = subpath_on_device # e.g., /etc/versions.txt or .X11-unix
                      notes.append("  Source path derived from /mnt/none[/SUBPATH] format.")
                 else:
                     # Combine /mnt/, device short name, and subpath
                     assumed_source = f"/mnt/{device_short_name}/{subpath_on_device.lstrip('/')}"
                     notes.append(f"  Source path assumed from DEVICE[/SUBPATH] format: {assumed_source}")
                     notes.append("  NOTE: This assumed path might be incorrect if the underlying device is not mounted at /mnt/<device_name>.")


                 fstab_source = assumed_source
             else:
                 notes.append("  WARNING: Could not fully parse subpath source. Using original source string.")
                 fstab_source = source


        fstab_fstype = 'none' # Bind/subpath mounts in fstab typically use 'none' fstype
        # Ensure 'bind' option is present
        if 'bind' not in fstab_options.split(','):
            fstab_options = f"{fstab_options},bind" if fstab_options else "bind"

        # Add defaults if options are minimal (excluding 'bind')
        current_options_list = fstab_options.split(',')
        options_without_bind = [opt for opt in current_options_list if opt != 'bind']
        if not options_without_bind or set(options_without_bind).issubset({'rw', 'relatime'}):
             if 'defaults' not in current_options_list:
                 fstab_options = f"{fstab_options},defaults" if fstab_options else "defaults"
        # Clean up duplicates potentially created by adding defaults
        fstab_options = ",".join(sorted(list(set(fstab_options.split(',')))))


    # --- Special handling for CIFS (SMB) ---
    elif fstype == 'cifs':
        notes.append("Detected as an SMB/CIFS mount.")
        print("This is an SMB/CIFS mount. Credentials are required for the fstab entry.")
        cred_choice = input("Use a credentials file (recommended) or enter directly? [file/direct/cancel]: ").lower()

        creds_options = ""
        if cred_choice == 'file':
            cred_path = input("Enter the full path to the credentials file (e.g., /home/user/.smbcredentials): ").strip()
            if not cred_path:
                print("Credentials file path cannot be empty. Skipping this mount.", file=sys.stderr)
                return None, []
            print(f"Remember to set strict permissions on your credentials file: chmod 600 {cred_path}")
            creds_options = f",credentials={cred_path}"
            notes.append(f"  Requires credentials file: {cred_path}")
        elif cred_choice == 'direct':
            username = input("Enter username: ").strip()
            password = input("Enter password: ").strip()
            if not username or not password:
                 print("Username and password cannot be empty. Skipping this mount.", file=sys.stderr)
                 return None, []
            print("Warning: Storing passwords directly in fstab is insecure. Consider using a credentials file.", file=sys.stderr)
            creds_options = f",username={username},password={password}"
            notes.append("  Includes username/password directly (less secure).")
        elif cred_choice == 'cancel':
            print("Cancelled credential input for this mount. Skipping fstab line.", file=sys.stderr)
            return None, []
        else:
            print("Invalid choice for credentials. Skipping fstab line.", file=sys.stderr)
            return None, []

        fstab_options = f"{fstab_options}{creds_options}"

        current_options_list = fstab_options.split(',')
        if not fstab_options or set(current_options_list).issubset({'rw', 'relatime', 'errors=remount-ro'}):
             if 'defaults' not in current_options_list:
                 fstab_options = f"{fstab_options},defaults" if fstab_options else "defaults"
        fstab_options = ",".join(sorted(list(set(fstab_options.split(',')))))
        if should_add_nofail and 'nofail' not in fstab_options.split(','):
            fstab_options = f"{fstab_options},nofail"


    # --- Handling other standard filesystems (ext4, vfat, etc.) ---
    elif fstype in ['ext4', 'xfs', 'vfat', 'ntfs', 'fuseblk']:
        notes.append(f"Detected as a standard {fstype} mount.")
        current_options_list = fstab_options.split(',')
        if not fstab_options or set(current_options_list).issubset({'rw', 'relatime', 'errors=remount-ro'}):
             if 'defaults' not in current_options_list:
                 fstab_options = f"{fstab_options},defaults" if fstab_options else "defaults"
        fstab_options = ",".join(sorted(list(set(fstab_options.split(',')))))


    elif is_dynamic_or_pseudo_filesystem_type(fstype):
         return None, [] # Should be filtered earlier, but double-check


    else: # Fallback for unhandled fstypes
        notes.append(f"Detected as an unhandled filesystem type: {fstype}.")
        print(f"Filesystem type '{fstype}' is not explicitly handled. Using captured options/defaults.", file=sys.stderr)
        if not fstab_options or fstab_options == 'rw':
             if 'defaults' not in fstab_options.split(','):
                 fstab_options = f"{fstab_options},defaults" if fstab_options else "defaults"
        fstab_options = ",".join(sorted(list(set(fstab_options.split(',')))))


    # --- Add nofail if required and not already present (for non-root mounts) ---
    if should_add_nofail and 'nofail' not in fstab_options.split(','):
        fstab_options = f"{fstab_options},nofail" if fstab_options else "nofail"
        fstab_options = fstab_options.strip(',')
        if 'nofail' in fstab_options.split(','):
            notes.append("  Added 'nofail' option.")


    # --- Construct the final line ---
    fstab_line = f"{fstab_source}\t{target}\t{fstab_fstype}\t{fstab_options}\t0\t0"

    return fstab_line, notes


# (Rest of the script remains the same, including add_line_to_fstab and main)
# ...
def add_line_to_fstab(line):
    """Adds a line to /etc/fstab with a backup using sudo tee."""
    fstab_path = '/etc/fstab'
    backup_path = '/etc/fstab.bak'

    print(f"\nAttempting to add line to {fstab_path}...")
    print(f"Line to add: {line}")

    if not os.path.exists(fstab_path):
        print(f"Error: {fstab_path} not found.", file=sys.stderr)
        return False

    # Check if already running as root
    if os.geteuid() != 0:
        print("Error: This action requires root privileges (sudo).")
        print("Please run the script itself with sudo (e.g., `sudo ./your_script_name.py`).", file=sys.stderr)
        return False


    # Create a backup before modifying
    try:
        shutil.copyfile(fstab_path, backup_path)
        print(f"Backup created at {backup_path}")
    except Exception as e:
        print(f"Error creating backup of {fstab_path}: {e}", file=sys.stderr)
        confirm_no_backup = input("Continue adding line WITHOUT creating a backup? (Highly NOT recommended) [yes/no]: ").lower()
        if confirm_no_backup != 'yes':
             print("Aborting line addition.")
             return False
        print("Proceeding without backup. Be extremely cautious.")


    # Add the line using tee -a
    try:
        subprocess.run(f"echo '{line}' | tee -a {fstab_path}", shell=True, check=True)
        print("Line added successfully.")
        return True

    except subprocess.CalledProcessError as e:
        print(f"Error adding line to {fstab_path}.", file=sys.stderr)
        print(f"Stderr: {e.stderr.strip()}", file=sys.stderr)
        if os.path.exists(backup_path):
             print(f"Your backup is at {backup_path}.", file=sys.stderr)
        return False
    except Exception as e:
        print(f"An unexpected error occurred while adding the line: {e}", file=sys.stderr)
        if os.path.exists(backup_path):
             print(f"Your backup is at {backup_path}.", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Finds active user-relevant mounts not in fstab and offers to make them persistent.")
    parser.add_argument(
        '--show-all',
        action='store_true',
        help="Show all active mounts, including common system paths and dynamic/pseudo filesystems like 9p."
    )
    args = parser.parse_args()

    fstab_path = '/etc/fstab'

    # --- Check for SOURCEPATH support ---
    sourcepath_supported = False
    test_output = run_command("findmnt -l --output SOURCE,TARGET,FSTYPE,OPTIONS,SOURCEPATH")
    if test_output is not None and 'SOURCEPATH' in test_output.splitlines()[0].split():
         sourcepath_supported = True
         mount_output = test_output
    else:
         mount_output = run_command("findmnt -l --output SOURCE,TARGET,FSTYPE,OPTIONS")
         if mount_output is None:
              print("Could not get basic mount info from findmnt. Exiting.", file=sys.stderr)
              return


    active_mounts = parse_mount_output(mount_output, include_sourcepath=sourcepath_supported)
    if not active_mounts:
        print("No active mount points found.", file=sys.stderr)
        return


    print("Reading /etc/fstab...")
    fstab_entries = parse_fstab()
    if fstab_entries is None:
        print("Could not read /etc/fstab. Exiting.", file=sys.stderr)
        return

    generated_lines_info = []

    print("\nChecking active mounts against /etc/fstab and generating potential entries...")

    for mount in active_mounts:
        target = mount.get('target')
        source = mount.get('source')
        fstype = mount.get('fstype')
        options = mount.get('options', '')
        is_subpath_mount = mount.get('is_subpath_mount', False)
        source_path = mount.get('source_path')


        # Skip entries that might be incomplete from parsing
        if not target or source is None or fstype is None:
             continue


        # Skip system mount targets unless --show-all is used
        if not args.show_all and is_system_mount_target(target):
            continue

        # Skip dynamic or pseudo filesystems unless it's a subpath mount AND --show-all is used
        if is_dynamic_or_pseudo_filesystem_type(fstype) and not args.show_all and not is_subpath_mount:
             continue


        # Check if this target already exists in fstab
        if target not in fstab_entries:
            line, notes = generate_fstab_line(mount)

            if line:
                 generated_lines_info.append((line, notes))


    if not generated_lines_info:
        print("\nNo new active user-relevant mounts found that are not already in /etc/fstab (or were skipped by default).")
        if args.show_all:
            print("Note: You used --show-all, so system and dynamic mounts were included in the check, but none needed fstab entries or were skipped for other reasons.")
        else:
             print("Note: System and dynamic mounts were skipped by default. Use --show-all to include them.")
        return

    print("\n--- Potential fstab entries to add ---")
    print("Review the lines below and add them to your /etc/fstab file.")
    print("Be sure to read any notes provided for specific entries.")
    print("-" * 35)

    for line, notes in generated_lines_info:
        print(line)
        for note in notes:
             print(note)
        print("-" * 35)


    print("\n--- How to add these lines to /etc/fstab ---")
    print("You can manually copy and paste the lines above into /etc/fstab")
    print("using a text editor with root privileges (e.g., `sudo nano /etc/fstab`).")
    print("Alternatively, you can use the `tee` command for each line:")
    for line, _ in generated_lines_info:
        escaped_line = line.replace("'", "'\\''")
        print(f"echo '{escaped_line}' | sudo tee -a {fstab_path}")

    print("\nAfter adding the lines, you can test them without rebooting using: `sudo mount -a`")
    print("This command attempts to mount all file systems listed in fstab that are not already mounted.")

    # Offer to add automatically - requires running the script with sudo
    if os.geteuid() != 0:
        print("\nTo have the script automatically add these lines, please run the script itself with sudo:")
        print(f"sudo python3 {sys.argv[0]} {'--show-all' if args.show_all else ''}".strip())
    else:
        add_automatically = input("\nRun the script to automatically add these lines now? (Requires sudo) [yes/no]: ").lower()
        if add_automatically == 'yes':
            print("\nAttempting to add lines automatically...")
            for line, _ in generated_lines_info:
                 if not add_line_to_fstab(line):
                     print(f"\nFailed to add line: {line}", file=sys.stderr)
                     print("Please check the error message and manually add the remaining lines.", file=sys.stderr)
                     break

            print("\nAutomatic addition process finished. Please test with `sudo mount -a`.")


if __name__ == "__main__":
    main()
