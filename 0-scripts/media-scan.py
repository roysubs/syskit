import os
import hashlib
import json
import sys
import socket
import argparse
from datetime import datetime
from pathlib import Path

# --- CONFIGURATION ---
TARGET_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.m4v',} # '.pdf', '.epub', '.mobi'}

GLOBAL_EXCLUSIONS = {
    # macOS
    'Library', 'System', 'Volumes', 'dev', 'cores', 'private', 'var', 'bin', 'sbin',
    # Windows
    'Windows', 'Program Files', 'Program Files (x86)', '$Recycle.Bin', 'System Volume Information',
    # Linux / General
    'proc', 'sys', 'run', 'boot', 'lost+found', '.Trash', '.thumbnails',
}

# Pre-compute lowercase set once for efficient comparisons
_EXCLUSIONS_LOWER = {x.lower() for x in GLOBAL_EXCLUSIONS}
# ---------------------

def get_hostname():
    """Return hostname with .local / domain suffix stripped."""
    return socket.gethostname().split('.')[0]

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

def get_quick_hash(filepath):
    hasher = hashlib.md5()
    try:
        with open(filepath, 'rb') as f:
            chunk = f.read(1024 * 1024)  # First 1MB only — not a full-file hash
            if not chunk:
                return None
            hasher.update(chunk)
        return hasher.hexdigest()
    except Exception:
        return None

def get_birthtime(stats):
    """
    Return file birthtime (creation time) where available.
    - macOS / BSD: st_birthtime (immutable across copies)
    - Linux:       not reliably available, returns None
    - Windows:     st_ctime is creation time on NTFS
    """
    if hasattr(stats, 'st_birthtime'):
        return stats.st_birthtime       # macOS / BSD
    if sys.platform == 'win32':
        return stats.st_ctime           # Windows: ctime IS birthtime on NTFS
    return None                         # Linux: not available

def scan_directory(root_path, output_file, hostname):
    files = []
    root = Path(root_path)
    count = 0
    last_printed_dir = None

    ext_list = ", ".join(sorted(TARGET_EXTENSIONS))

    print("-" * 50)
    print(f"SCAN STARTING")
    print("-" * 50)
    print(f"Hostname:     {hostname}")
    print(f"Target Path:  {root.absolute()}")
    print(f"Extensions:   {ext_list}")
    print(f"Collecting:   Path, Size, mtime, birthtime (where available), MD5 (first 1MB)")
    print(f"Excluding:    Common macOS / Windows / Linux system folders")
    print(f"Output File:  {output_file}")
    print("-" * 50)

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in _EXCLUSIONS_LOWER]

        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext not in TARGET_EXTENSIONS:
                continue

            full_path = Path(dirpath) / filename

            # Print folder name when we first find a matching file in it
            if dirpath != last_printed_dir:
                print(f"  [{dirpath}]")
                last_printed_dir = dirpath

            try:
                stats = full_path.stat()
                if stats.st_size > 0:
                    files.append({
                        "path":       str(full_path.absolute()),
                        "size":       stats.st_size,
                        "mtime":      stats.st_mtime,
                        "birthtime":  get_birthtime(stats),   # None on Linux
                        "quick_hash": get_quick_hash(full_path)
                    })
                    count += 1
                    if count % 100 == 0:
                        print(f"  ... {count} files indexed so far", end='\r', flush=True)
            except (PermissionError, OSError):
                continue

    print()  # Clear the \r progress line
    return files


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Index video/ebook files by size and partial hash.")
    parser.add_argument("path", nargs="?", help="Directory to scan")
    parser.add_argument("--output", help="Override output JSON file path")
    args = parser.parse_args()

    path_to_scan = args.path or input("Enter path to scan: ")

    # Defensive cleanup: handles drag-and-drop artifacts, quoted paths, escaped spaces
    cleaned_path = path_to_scan.strip().replace('"', '').replace("'", "").replace('\\ ', ' ')
    if cleaned_path.endswith('\\'):
        cleaned_path = cleaned_path[:-1]

    if not os.path.exists(cleaned_path):
        print(f"Error: Path does not exist: [{cleaned_path}]")
        sys.exit(1)

    hostname = get_hostname()

    # Output path: ~/scan-media/<hostname>@<folder>_YYYYMMDD_HHMM.json
    script_stem  = Path(sys.argv[0]).stem          # e.g. "scan-media"
    output_dir   = Path.home() / script_stem
    output_dir.mkdir(parents=True, exist_ok=True)

    folder_slug  = Path(cleaned_path).name or "root"
    timestamp    = datetime.now().strftime("%Y%m%d_%H%M")
    default_file = output_dir / f"{hostname}@{folder_slug}_{timestamp}.json"
    output_file  = Path(args.output) if args.output else default_file

    scan_time  = datetime.now().isoformat(timespec='seconds')
    start_time = datetime.now()
    files      = scan_directory(cleaned_path, output_file, hostname)
    elapsed    = (datetime.now() - start_time).total_seconds()

    total_size = sum(f["size"] for f in files)

    # Self-describing metadata envelope
    output = {
        "scan_meta": {
            "hostname":    hostname,
            "scan_time":   scan_time,
            "target_path": str(Path(cleaned_path).absolute()),
            "file_count":  len(files),
            "total_size":  total_size,
            "total_size_human": format_size(total_size),
        },
        "files": files
    }

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=4)

    print(f"\nScan Complete!")
    print(f"Total files indexed: {len(files)}")
    print(f"Total size:          {format_size(total_size)}")
    print(f"Time elapsed:        {format_duration(elapsed)}")
    print(f"Data saved to:       {os.path.abspath(output_file)}")
    print("-" * 50)
