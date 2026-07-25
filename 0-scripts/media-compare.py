#!/usr/bin/env python3
import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime
from collections import defaultdict

# ---------------------
def format_size(total_bytes):
    for unit in ['bytes', 'KB', 'MB', 'GB', 'TB']:
        if total_bytes < 1024 or unit == 'TB':
            return f"{total_bytes:.2f} {unit}" if unit != 'bytes' else f"{total_bytes} bytes"
        total_bytes /= 1024

def format_duration(seconds):
    if seconds < 60:
        return f"{seconds:.1f}s"
    m, s = divmod(int(seconds), 60)
    if m < 60:
        return f"{m}m {s:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m {s:02d}s"

def load_json(path):
    """Load and validate a scan JSON. Exits immediately on any problem."""
    p = Path(path)
    if not p.exists():
        print(f"Error: File does not exist: [{path}]")
        sys.exit(1)
    if not p.suffix == '.json':
        print(f"Error: Not a .json file: [{path}]")
        sys.exit(1)
    try:
        with open(p, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Could not parse JSON in [{path}]: {e}")
        sys.exit(1)
    if 'scan_meta' not in data or 'files' not in data:
        print(f"Error: [{path}] does not look like a media-scan output (missing scan_meta or files).")
        sys.exit(1)
    return data

def build_key(file_entry, use_name, use_size, use_hash, use_birthtime):
    """Build a tuple comparison key from whichever fields are active."""
    parts = []
    if use_name:
        parts.append(Path(file_entry['path']).name.lower())
    if use_size:
        parts.append(file_entry['size'])
    if use_hash:
        parts.append(file_entry.get('quick_hash'))
    if use_birthtime:
        parts.append(file_entry.get('birthtime'))
    return tuple(parts)

def make_rm_path(file_entry, hostname):
    """
    Return a shell-safe rm target.
    - Same host as runner: absolute local path
    - Different host: //hostname/path for network rm
    """
    path = file_entry['path']
    file_host = file_entry['_hostname']
    if file_host == hostname:
        return path
    else:
        # Network path: //hostname/absolute/path
        return f"//{file_host}{path}"

def shell_escape(path):
    """Wrap path in single quotes, escaping any embedded single quotes."""
    return "'" + path.replace("'", "'\\''") + "'"

# ---------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Compare media-scan JSON files and produce a commented shell cleanup script.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Match flags (combine freely — applied as a pipeline, cheapest first):
  --size        Match on file size in bytes
  --name        Match on filename (case-insensitive)
  --hash        Match on MD5 of first 1MB
  --birthtime   Match on file birthtime (immutable across copies; macOS/BSD/Windows only)

Examples:
  media-compare.py scan1.json scan2.json --size --hash
  media-compare.py scan1.json --name
  media-compare.py a.json b.json c.json --size --hash --name
        """
    )

    parser.add_argument('jsons', nargs='*',  help="Paths to one or more scan JSON files")
    parser.add_argument('--size',      action='store_true', help="Match on file size")
    parser.add_argument('--name',      action='store_true', help="Match on filename")
    parser.add_argument('--hash',      action='store_true', help="Match on quick_hash (MD5 first 1MB)")
    parser.add_argument('--birthtime', action='store_true', help="Match on birthtime (creation time)")
    parser.add_argument('--output',    help="Override output .sh file path")
    args = parser.parse_args()

    # --- Validate: at least one JSON ---
    if not args.jsons:
        parser.print_help()
        sys.exit(1)

    # --- Validate: at least one match flag ---
    if not any([args.size, args.name, args.hash, args.birthtime]):
        print("Error: Specify at least one match flag: --size, --name, --hash, --birthtime")
        print("       Recommended starting point: --size --hash")
        sys.exit(1)

    # --- Load and validate all JSONs up front — fail fast ---
    print("-" * 55)
    print("MEDIA COMPARE")
    print("-" * 55)

    datasets = []
    for json_path in args.jsons:
        data = load_json(json_path)
        meta = data['scan_meta']
        print(f"  Loaded: {json_path}")
        print(f"          Host: {meta['hostname']}  |  Path: {meta['target_path']}")
        print(f"          Scanned: {meta['scan_time']}  |  Files: {meta['file_count']:,}  |  Size: {meta['total_size_human']}")
        # Tag each file record with its source hostname and json path
        for f in data['files']:
            f['_hostname'] = meta['hostname']
            f['_source_json'] = str(json_path)
        datasets.append(data)

    # Determine running hostname (for local vs network rm paths)
    import socket
    running_hostname = socket.gethostname().split('.')[0]

    # Build active match criteria label
    criteria = []
    if args.size:      criteria.append("size")
    if args.name:      criteria.append("name")
    if args.hash:      criteria.append("hash")
    if args.birthtime: criteria.append("birthtime")
    criteria_str = " + ".join(criteria)

    print(f"\n  Match criteria: {criteria_str}")
    print(f"  Running on:     {running_hostname}")
    print("-" * 55)

    # --- Pool all files ---
    all_files = []
    for data in datasets:
        all_files.extend(data['files'])

    total_files = len(all_files)
    print(f"\n  Total files across all inputs: {total_files:,}")
    print(f"  Building duplicate index...")

    start_time = datetime.now()

    # --- Group by key ---
    groups = defaultdict(list)
    skipped = 0
    for f in all_files:
        key = build_key(f, args.name, args.size, args.hash, args.birthtime)
        # Skip files where any requested field is None (e.g. birthtime on Linux)
        if None in key:
            skipped += 1
            continue
        groups[key].append(f)

    if skipped:
        print(f"  Warning: {skipped:,} files skipped — one or more requested fields were null")
        print(f"           (birthtime is unavailable on Linux systems)")

    # --- Keep only groups with more than one file ---
    duplicates = {k: v for k, v in groups.items() if len(v) > 1}

    elapsed = (datetime.now() - start_time).total_seconds()

    dup_file_count  = sum(len(v) for v in duplicates.values())
    dup_group_count = len(duplicates)
    # Recoverable space = all copies minus one per group
    recoverable     = sum(
        sum(f['size'] for f in v) - max(f['size'] for f in v)
        for v in duplicates.values()
    )

    print(f"  Duplicate groups found: {dup_group_count:,}")
    print(f"  Files involved:         {dup_file_count:,}")
    print(f"  Potentially recoverable: {format_size(recoverable)}")
    print(f"  Comparison time:        {format_duration(elapsed)}")
    print("-" * 55)

    if not duplicates:
        print("\n  No duplicates found. Nothing to write.")
        sys.exit(0)

    # --- Build output path ---
    script_stem = Path(sys.argv[0]).stem          # "media-compare"
    output_dir  = Path.home() / script_stem
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp   = datetime.now().strftime("%Y%m%d_%H%M")
    default_out = output_dir / f"cleanup_{criteria_str.replace(' + ', '-')}_{timestamp}.sh"
    output_file = Path(args.output) if args.output else default_out

    # --- Write shell script ---
    with open(output_file, 'w', encoding='utf-8') as sh:

        sh.write("#!/bin/sh\n")
        sh.write("#\n")
        sh.write("# media-compare — duplicate file cleanup script\n")
        sh.write(f"# Generated:   {datetime.now().isoformat(timespec='seconds')}\n")
        sh.write(f"# Run on host: {running_hostname}\n")
        sh.write(f"# Match criteria: {criteria_str}\n")
        sh.write("#\n")
        sh.write("# Source scan files:\n")
        for data in datasets:
            m = data['scan_meta']
            sh.write(f"#   [{m['hostname']}] {m['target_path']}  (scanned {m['scan_time']}, {m['file_count']:,} files)\n")
        sh.write("#\n")
        sh.write(f"# Duplicate groups: {dup_group_count:,}\n")
        sh.write(f"# Files involved:   {dup_file_count:,}\n")
        sh.write(f"# Potentially recoverable: {format_size(recoverable)}\n")
        sh.write("#\n")
        sh.write("# HOW TO USE:\n")
        sh.write("#   All rm commands are commented out — this script is safe to inspect.\n")
        sh.write("#   Review each group, decide which copy to keep, then uncomment the\n")
        sh.write("#   rm lines you want to execute and run:  sh cleanup_....sh\n")
        sh.write("#   Network paths (//hostname/path) require the remote host to be\n")
        sh.write("#   reachable and the share to be mounted.\n")
        sh.write("#\n")
        sh.write("# " + "-" * 53 + "\n\n")

        for i, (key, group) in enumerate(sorted(duplicates.items(), key=lambda x: -x[1][0]['size']), 1):
            # Sort group: local files first, then by birthtime (oldest first) as a hint
            group_sorted = sorted(
                group,
                key=lambda f: (f['_hostname'] != running_hostname, f.get('birthtime') or 0)
            )

            size_str  = format_size(group_sorted[0]['size'])
            hosts     = sorted({f['_hostname'] for f in group_sorted})
            host_note = ", ".join(hosts)

            sh.write(f"# --- Group {i} of {dup_group_count}  |  match: {criteria_str}  |  size: {size_str}  |  host(s): {host_note}\n")

            for f in group_sorted:
                rm_path  = make_rm_path(f, running_hostname)
                escaped  = shell_escape(rm_path)
                size_note = format_size(f['size'])
                host_tag  = f['_hostname']
                bt        = f.get('birthtime')
                try:
                    bt_str = datetime.fromtimestamp(bt).strftime('%Y-%m-%d %H:%M:%S') if bt else 'n/a'
                    if bt and datetime.fromtimestamp(bt).year < 2000:
                        bt_str = 'n/a (invalid)'
                except (OSError, ValueError, TypeError):
                    bt_str = 'n/a (invalid)'
                sh.write(f"# rm {escaped}   # {size_note}  |  host: {host_tag}  |  born: {bt_str}\n")

            sh.write("\n")

    print(f"\n  Cleanup script written to:")
    print(f"  {os.path.abspath(output_file)}")
    print("-" * 55)
