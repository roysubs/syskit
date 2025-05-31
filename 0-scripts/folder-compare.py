#!/usr/bin/env python3
# Author: Roy Wiseman 2025-03
# -*- coding: utf-8 -*-

import os
import argparse
import hashlib
import sys

# ANSI escape codes for colors
class Colors:
    RESET = '\033[0m'
    CYAN = '\033[96m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    GREEN = '\033[92m'
    BOLD = '\033[1m'

def format_duration(seconds_abs):
    """Formats a non-negative duration in seconds into a human-readable string."""
    if seconds_abs < 60:
        return f"{seconds_abs:.1f} sec"
    elif seconds_abs < 3600:
        return f"{seconds_abs / 60:.1f} min"
    else:
        return f"{seconds_abs / 3600:.1f} hours"

def calculate_hash(filepath, hash_algo="md5", buffer_size=65536):
    """Calculates the hash of a file."""
    hasher = hashlib.new(hash_algo)
    try:
        with open(filepath, 'rb') as f:
            while True:
                data = f.read(buffer_size)
                if not data:
                    break
                hasher.update(data)
        return hasher.hexdigest()
    except FileNotFoundError:
        print(f"{Colors.RED}Error: File not found during hashing: {filepath}{Colors.RESET}", file=sys.stderr)
        return None
    except IOError as e:
        print(f"{Colors.RED}Error: Could not read file for hashing: {filepath} ({e}){Colors.RESET}", file=sys.stderr)
        return None

def analyze_directories(folder1_path, folder2_path, fuzzy_time_threshold_sec, 
                        check_hash, size_only, excluded_folder_names):
    print(f"{Colors.BOLD}Comparing directories:{Colors.RESET}")
    print(f"{Colors.CYAN}fld1 (e.g., WSL): {os.path.abspath(folder1_path)}{Colors.RESET}")
    print(f"{Colors.YELLOW}fld2 (e.g., Debian): {os.path.abspath(folder2_path)}{Colors.RESET}")

    mode_desc = []
    if check_hash:
        mode_desc.append("content hash (MD5) comparison")
    if size_only:
        mode_desc.append("size-only comparison")
    if fuzzy_time_threshold_sec is not None:
        mode_desc.append(f"fuzzy time comparison (±{fuzzy_time_threshold_sec}s)")
    if excluded_folder_names:
        mode_desc.append(f"excluding folders named: {Colors.BOLD}{', '.join(excluded_folder_names)}{Colors.RESET}")
    
    if not mode_desc and not check_hash and not size_only and fuzzy_time_threshold_sec is None and not excluded_folder_names: # Default mode
        print("Mode: Exact size and time comparison.\n")
    elif mode_desc:
        print(f"Mode: {', '.join(mode_desc)}.\n")
    else: # Should not happen if logic is correct, but as a fallback
        print("Mode: Default comparison.\n")


    files_fld1 = {}
    for root, dirs, files in os.walk(folder1_path, topdown=True):
        # Modify dirs in-place to exclude specified folder names
        dirs[:] = [d for d in dirs if d not in excluded_folder_names]
        for file in files:
            full_path = os.path.join(root, file)
            relative_path = os.path.relpath(full_path, folder1_path)
            files_fld1[relative_path] = full_path

    files_fld2 = {}
    for root, dirs, files in os.walk(folder2_path, topdown=True):
        # Modify dirs in-place to exclude specified folder names
        dirs[:] = [d for d in dirs if d not in excluded_folder_names]
        for file in files:
            full_path = os.path.join(root, file)
            relative_path = os.path.relpath(full_path, folder2_path)
            files_fld2[relative_path] = full_path

    all_relative_paths = set(files_fld1.keys()) | set(files_fld2.keys())
    found_differences = False

    for rel_path in sorted(list(all_relative_paths)):
        path1 = files_fld1.get(rel_path)
        path2 = files_fld2.get(rel_path)
        file_name = os.path.basename(rel_path)

        if path1 and path2: # File exists in both directories
            try:
                stat1 = os.stat(path1)
                stat2 = os.stat(path2)
            except FileNotFoundError:
                print(f"{Colors.RED}Error: File disappeared during analysis: {rel_path}{Colors.RESET}", file=sys.stderr)
                if not os.path.exists(path1): print(f"  {Colors.CYAN}fld1: .../{rel_path} (missing now){Colors.RESET}", file=sys.stderr)
                if not os.path.exists(path2): print(f"  {Colors.YELLOW}fld2: .../{rel_path} (missing now){Colors.RESET}", file=sys.stderr)
                print("-" * 30)
                found_differences = True
                continue

            size1, mtime1 = stat1.st_size, stat1.st_mtime
            size2, mtime2 = stat2.st_size, stat2.st_mtime

            size_diff = size1 - size2
            size_desc = ""
            if size_diff != 0:
                if size_diff > 0: size_desc = f"{Colors.CYAN}fld1 is bigger (by {size_diff} bytes){Colors.RESET}"
                else: size_desc = f"{Colors.YELLOW}fld2 is bigger (by {abs(size_diff)} bytes){Colors.RESET}"

            time_diff_seconds = mtime1 - mtime2
            time_desc = ""
            times_are_effectively_same = False

            if fuzzy_time_threshold_sec is not None:
                if abs(time_diff_seconds) <= fuzzy_time_threshold_sec:
                    times_are_effectively_same = True
                    if time_diff_seconds == 0: time_desc = "times are identical"
                    else: time_desc = f"times considered identical (differs by {format_duration(abs(time_diff_seconds))}, within ±{fuzzy_time_threshold_sec}s threshold)"
                else:
                    if time_diff_seconds > 0: time_desc = f"{Colors.CYAN}fld1 is newer (by {format_duration(time_diff_seconds)}){Colors.RESET}"
                    else: time_desc = f"{Colors.YELLOW}fld2 is newer (by {format_duration(abs(time_diff_seconds))}){Colors.RESET}"
            else: # Exact time comparison
                if time_diff_seconds == 0:
                    times_are_effectively_same = True
                    time_desc = "times are identical"
                else:
                    if time_diff_seconds > 0: time_desc = f"{Colors.CYAN}fld1 is newer (by {format_duration(time_diff_seconds)}){Colors.RESET}"
                    else: time_desc = f"{Colors.YELLOW}fld2 is newer (by {format_duration(abs(time_diff_seconds))}){Colors.RESET}"

            diff_reason_primary = ""
            hash1_val, hash2_val = None, None 

            if check_hash:
                hash1_val = calculate_hash(path1)
                hash2_val = calculate_hash(path2)
                if hash1_val is None or hash2_val is None: 
                    diff_reason_primary = "hash_error"
                elif hash1_val == hash2_val:
                    continue 
                else: 
                    diff_reason_primary = "hash_diff"
            elif size_only:
                if size_diff == 0:
                    continue 
                else: 
                    diff_reason_primary = "size_only_diff"
            else: 
                if size_diff == 0 and times_are_effectively_same:
                    continue 
                else:
                    diff_reason_primary = "default_diff"

            found_differences = True
            print(f"{Colors.CYAN}fld1: {os.path.join(folder1_path, rel_path)}{Colors.RESET}")
            print(f"{Colors.YELLOW}fld2: {os.path.join(folder2_path, rel_path)}{Colors.RESET}")
            
            final_details = []
            if diff_reason_primary == "hash_error":
                final_details.append(f"{Colors.RED}Error calculating MD5 hash{Colors.RESET}")
            elif diff_reason_primary == "hash_diff":
                final_details.append(f"{Colors.RED}contents differ (MD5 hashes different){Colors.RESET}")
                if size_diff != 0: final_details.append(size_desc)
                else: final_details.append("sizes are identical")
            elif diff_reason_primary == "size_only_diff":
                final_details.append(size_desc) 
            elif diff_reason_primary == "default_diff":
                if size_diff != 0:
                    final_details.append(size_desc)
                elif not times_are_effectively_same: 
                    final_details.append("sizes are identical")
                
                if not times_are_effectively_same:
                    final_details.append(time_desc)
                elif size_diff != 0: 
                    final_details.append(time_desc)
            
            details_string = f"  {file_name} {', '.join(filter(None, final_details))}"
            print(details_string)
            print("-" * 30)

        elif path1: 
            found_differences = True
            print(f"{Colors.CYAN}fld1: {os.path.join(folder1_path, rel_path)}{Colors.RESET}")
            print(f"{Colors.YELLOW}fld2: (file missing){Colors.RESET}")
            print(f"  {file_name} {Colors.CYAN}Only in fld1{Colors.RESET}")
            print("-" * 30)
        elif path2: 
            found_differences = True
            print(f"{Colors.CYAN}fld1: (file missing){Colors.RESET}")
            print(f"{Colors.YELLOW}fld2: {os.path.join(folder2_path, rel_path)}{Colors.RESET}")
            print(f"  {file_name} {Colors.YELLOW}Only in fld2{Colors.RESET}")
            print("-" * 30)

    if not found_differences:
        print(f"{Colors.GREEN}No reportable differences found between the two directories based on the chosen criteria.{Colors.RESET}")

def main():
    parser = argparse.ArgumentParser(
        description=(
            f"{Colors.BOLD}Compares two directories (fld1, fld2) and reports differences.{Colors.RESET}\n"
            "By default, compares file size and modification time.\n"
            "Identical files (based on the active criteria) are ignored.\n\n"
            "Color Legend:\n"
            f"  {Colors.CYAN}Information related to fld1 (first path argument){Colors.RESET}\n"
            f"  {Colors.YELLOW}Information related to fld2 (second path argument){Colors.RESET}\n"
            f"  {Colors.RED}Highlights significant differences (e.g., content mismatch){Colors.RESET}\n"
            f"  {Colors.GREEN}Used for summaries like 'no differences found'{Colors.RESET}"
        ),
        epilog="Example usages:\n"
               "  %(prog)s ./folderA ./folderB\n"
               "    (Default: compare size and exact modification time)\n"
               "  %(prog)s --exclude-folder .git --exclude-folder __pycache__ ./folderA ./folderB\n"
               "    (Exclude '.git' and '__pycache__' folders from comparison)\n"
               "  %(prog)s -f ./folderA ./folderB\n"
               "    (Fuzzy time comparison, default ±10s threshold)\n"
               "  %(prog)s --fuzzy-time 5 ./folderA ./folderB\n"
               "    (Fuzzy time comparison, ±5s threshold)\n"
               "  %(prog)s --size-only ./folderA ./folderB\n"
               "    (Only report files that differ in size; ignores time)\n"
               "  %(prog)s --hash ./folderA ./folderB\n"
               "    (Report if MD5 content hashes differ; ignores time for identity)\n",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("folder1", nargs='?', help="Path to the first folder (labeled 'fld1').")
    parser.add_argument("folder2", nargs='?', help="Path to the second folder (labeled 'fld2').")
    parser.add_argument(
        "-f", "--fuzzy-time",
        type=int, metavar="SECONDS", nargs='?', const=10, default=None,
        help="Enable fuzzy time comparison. Times differing by up to SECONDS (default 10)\n"
             "are considered identical. (e.g., -f or -f 5)"
    )
    parser.add_argument(
        "--size-only", action="store_true",
        help="Ignore modification times. Report only if sizes differ. Files with identical\n"
             "sizes will be skipped. Overridden by --hash if both are used."
    )
    parser.add_argument(
        "--hash", action="store_true", dest="check_hash",
        help="Perform content hash (MD5) comparison. Files with identical hashes are skipped.\n"
             "This is slower but definitive for content. If hashes differ, size difference\n"
             "may also be shown, but time is ignored for identity. Takes precedence over --size-only."
    )
    parser.add_argument(
        "--exclude-folder",
        action="append", 
        metavar="FOLDER_NAME",
        default=[],      
        help="Specify a folder name to exclude (e.g., '.git', 'node_modules').\n"
             "Can be used multiple times to exclude multiple folder names."
    )

    if len(sys.argv) == 1: 
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()

    if not args.folder1 or not args.folder2:
        print(f"{Colors.RED}Error: Both folder1 and folder2 paths are required.{Colors.RESET}\n", file=sys.stderr)
        parser.print_help(sys.stderr)
        sys.exit(1)

    if not os.path.isdir(args.folder1):
        print(f"{Colors.RED}Error: Folder1 '{args.folder1}' does not exist or is not a directory.{Colors.RESET}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(args.folder2):
        print(f"{Colors.RED}Error: Folder2 '{args.folder2}' does not exist or is not a directory.{Colors.RESET}", file=sys.stderr)
        sys.exit(1)

    if args.check_hash and args.size_only:
        print(f"{Colors.YELLOW}Warning: --hash is active, so --size-only is less relevant for determining identity.{Colors.RESET}\n"
              "Content hash comparison takes precedence for skipping identical files.", file=sys.stderr)

    analyze_directories(args.folder1, args.folder2, args.fuzzy_time, 
                        args.check_hash, args.size_only, args.exclude_folder)

if __name__ == "__main__":
    main()
