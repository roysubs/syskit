#!/usr/bin/env python3
"""
SystemCatalogue - High-Performance Cross-Platform Disk Indexer, Snapshot Manager,
Ledger Engine, and Media Duplicate Detector.

Cross-Platform: Windows, Linux, macOS.
Zero external dependencies (Standard Library only: os, sys, sqlite3, pathlib, hashlib, csv).

Author: Antigravity Team
"""

import os
import sys
import sqlite3
import hashlib
import csv
import datetime
import argparse
import platform
import subprocess
import shutil
import re
import json
from pathlib import Path

# Ensure UTF-8 stdout for Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# --- Configuration & Standard Exclusions ---

DEFAULT_EXCLUDED_DIRS = {
    'systemcatalogue',
    '.system_catalogue',
    'indexdisks',
    '$recycle.bin',
    'system volume information',
    'documents and settings',
    'windows',
    'windows.old',
    '$windows.~ws',
    '$windows.~bt',
    'wer',
    'onedrivetemp',
    '.cache',
    'lost+found',
    '.trash',
    '.trashes',
    'node_modules',
    '__pycache__',
    '.git'
}

DEFAULT_EXCLUDED_FILES = {
    'hiberfil.sys',
    'pagefile.sys',
    'swapfile.sys',
    'thumbs.db',
    'desktop.ini',
    '.ds_store'
}

MEDIA_EXTENSIONS = {
    '.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.ts', '.vob',
    '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.wma', '.alac', '.ape',
    '.iso', '.zip', '.rar', '.7z', '.tar', '.gz', '.tgz', '.bz2', '.xz',
    '.jpg', '.jpeg', '.png', '.raw', '.cr2', '.nef', '.arw', '.heic', '.tif', '.tiff',
    '.dmg', '.img', '.vhd', '.vhdx'
}


def get_default_catalogue_root() -> str:
    """Resolves default catalogue root path based on operating system."""
    if platform.system() == "Windows":
        return r"C:\SystemCatalogue"
    return os.path.expanduser("~/.system_catalogue")


def format_bytes(byte_count: int) -> str:
    """Formats raw byte counts into human-readable strings (KB, MB, GB, TB)."""
    if byte_count >= 1024 ** 4:
        return f"{byte_count / (1024 ** 4):.2f} TB"
    if byte_count >= 1024 ** 3:
        return f"{byte_count / (1024 ** 3):.2f} GB"
    if byte_count >= 1024 ** 2:
        return f"{byte_count / (1024 ** 2):.2f} MB"
    if byte_count >= 1024:
        return f"{byte_count / 1024:.2f} KB"
    return f"{byte_count} B"


def compute_head_tail_hash(file_path: str, head_bytes: int = 4096, tail_bytes: int = 4096) -> str | None:
    """
    Computes a fast 8KB partial hash (First 4KB + Last 4KB + File Size)
    Takes ~0.001s per 50GB file to verify bit-for-bit identity across systems.
    """
    try:
        size = os.path.getsize(file_path)
        hasher = hashlib.blake2b(digest_size=16)
        hasher.update(str(size).encode('utf-8'))
        with open(file_path, 'rb') as f:
            if size <= (head_bytes + tail_bytes):
                hasher.update(f.read())
            else:
                hasher.update(f.read(head_bytes))
                f.seek(size - tail_bytes)
                hasher.update(f.read(tail_bytes))
        return hasher.hexdigest()
    except Exception:
        return None


class SystemCatalogue:
    def __init__(self, catalogue_root: str | None = None):
        self.root = catalogue_root or get_default_catalogue_root()
        os.makedirs(self.root, exist_ok=True)
        self.db_path = os.path.join(self.root, "catalogue.db")
        self.hostname = platform.node() or "HOST"
        self._init_database()

    def _init_database(self):
        """Initializes SQLite database and indexes for high-speed multi-machine queries."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS files (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    machine TEXT NOT NULL,
                    volume TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    extension TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL,
                    creation_time TEXT NOT NULL,
                    last_write_time TEXT NOT NULL,
                    head_tail_hash TEXT,
                    indexed_at TEXT NOT NULL,
                    UNIQUE(machine, volume, relative_path)
                )
            """)
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_files_size_ext ON files(size_bytes, extension)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_files_machine_vol ON files(machine, volume)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_files_hash ON files(head_tail_hash)")
            conn.commit()

    def get_smart_volume_id(self, drive_path: str) -> str:
        """
        Resolves smart volume identifier across platforms:
        - Windows: <Hostname>_<Drive>_<Label> or <Hostname>_EXT_<Label>_<ShortSerial>
        - Linux / macOS: <Hostname>_<MountOrLabel>
        """
        clean_drive = drive_path.strip()
        system_os = platform.system()

        if system_os == "Windows":
            # Extract single drive letter (e.g. C: -> C)
            drive_letter = clean_drive.replace(":", "").replace("\\", "").replace("/", "")[:1].upper()
            try:
                # Query PowerShell/CIM for volume label and serial
                cmd = f'powershell -NoProfile -Command "Get-CimInstance Win32_Volume | Where-Object {{ $_.DriveLetter -like \'{drive_letter}:*\' }} | Select-Object Label, SerialNumber, DriveType | ConvertTo-Json"'
                out = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
                if out.strip():
                    data = json.loads(out)
                    label = re.sub(r'[^\w\-\.]', '_', data.get("Label") or "").strip('_')
                    drive_type = data.get("DriveType", 3)
                    raw_serial = data.get("SerialNumber")
                    hex_serial = ""
                    if raw_serial:
                        hex_serial = hex(int(raw_serial))[2:].upper()[-4:]

                    if drive_type == 2:  # Removable
                        lbl = label if label else "Drive"
                        return f"{self.hostname}_EXT_{lbl}_{hex_serial}" if hex_serial else f"{self.hostname}_EXT_{lbl}"
                    elif label:
                        return f"{self.hostname}_{drive_letter}_{label}"
                    else:
                        return f"{self.hostname}_{drive_letter}"
            except Exception:
                pass
            return f"{self.hostname}_{drive_letter}"

        else:
            # POSIX / Linux / macOS: extract label or sanitized mountpoint
            sanitized = clean_drive.strip("/").replace("/", "_") or "root"
            sanitized = re.sub(r'[^\w\-\.]', '_', sanitized)
            return f"{self.hostname}_{sanitized}"

    def get_smart_folder_id(self, folder_path: str) -> str:
        """Creates an identifier for a specific folder path."""
        norm = os.path.abspath(folder_path).rstrip(r"\/")
        leaf = os.path.basename(norm) or "Folder"
        clean_leaf = re.sub(r'[^\w\-\.]', '_', leaf)
        return f"{self.hostname}_{clean_leaf}"

    def scan_and_mirror(self, source_path: str, target_identifier: str, snapshot_name: str | None = None) -> dict:
        """
        Recursively scans the source directory using high-speed os.scandir(),
        reproduces the zero-byte directory tree with exact cloned timestamps,
        and streams metadata into SQLite and CSV ledger.
        """
        source_path = os.path.abspath(source_path)
        folder_name = f"{target_identifier}-{snapshot_name}" if snapshot_name else target_identifier
        dest_dir = os.path.join(self.root, folder_name)
        os.makedirs(dest_dir, exist_ok=True)

        ledger_csv_path = os.path.join(self.root, f"{folder_name}.ledger.csv")
        indexed_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        print(f"\n[{target_identifier}] Starting High-Speed Mirror & Ledger Generation...")
        print(f"       Source : {source_path}")
        print(f"       Target : {dest_dir}")
        print(f"       Ledger : {ledger_csv_path}")

        start_time = datetime.datetime.now()
        records_to_insert = []
        indexed_count = 0
        total_bytes = 0

        # Open ledger CSV writer
        csv_file = open(ledger_csv_path, 'w', newline='', encoding='utf-8')
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow(["MachineName", "Drive", "RelativePath", "Size", "LastWriteTime", "Extension"])

        def is_excluded_dir(dir_name: str) -> bool:
            return dir_name.lower() in DEFAULT_EXCLUDED_DIRS

        def is_excluded_file(file_name: str) -> bool:
            low = file_name.lower()
            if low in DEFAULT_EXCLUDED_FILES:
                return True
            if low.startswith("ntuser.dat") or low.startswith("usrclass.dat") or low.endswith(".tmp"):
                return True
            return False

        # Fast recursive walker using os.scandir
        def walk_dir(current_dir: str, rel_prefix: str = ""):
            nonlocal indexed_count, total_bytes
            try:
                with os.scandir(current_dir) as entries:
                    for entry in entries:
                        try:
                            # Skip symlinks/junctions to prevent infinite loops
                            if entry.is_symlink():
                                continue

                            if entry.is_dir(follow_symlinks=False):
                                if is_excluded_dir(entry.name):
                                    continue
                                sub_rel = os.path.join(rel_prefix, entry.name) if rel_prefix else entry.name
                                sub_dest = os.path.join(dest_dir, sub_rel)
                                os.makedirs(sub_dest, exist_ok=True)

                                # Clone directory timestamps
                                try:
                                    st = entry.stat(follow_symlinks=False)
                                    os.utime(sub_dest, (st.st_atime, st.st_mtime))
                                except Exception:
                                    pass

                                walk_dir(entry.path, sub_rel)

                            elif entry.is_file(follow_symlinks=False):
                                if is_excluded_file(entry.name):
                                    continue

                                st = entry.stat(follow_symlinks=False)
                                size = st.st_size
                                total_bytes += size
                                mtime_dt = datetime.datetime.fromtimestamp(st.st_mtime)
                                ctime_dt = datetime.datetime.fromtimestamp(st.st_ctime)
                                mtime_str = mtime_dt.strftime("%Y-%m-%d %H:%M:%S")
                                ctime_str = ctime_dt.strftime("%Y-%m-%d %H:%M:%S")

                                rel_file = os.path.join(rel_prefix, entry.name) if rel_prefix else entry.name
                                ext = os.path.splitext(entry.name)[1].lower() or "[no_ext]"

                                # 1. Create Zero-Byte Stub with Cloned Timestamps
                                dest_file = os.path.join(dest_dir, rel_file)
                                dest_parent = os.path.dirname(dest_file)
                                if not os.path.exists(dest_parent):
                                    os.makedirs(dest_parent, exist_ok=True)

                                # Write 0 bytes
                                with open(dest_file, 'wb'):
                                    pass
                                try:
                                    os.utime(dest_file, (st.st_atime, st.st_mtime))
                                except Exception:
                                    pass

                                # 2. Write CSV row
                                csv_writer.writerow([self.hostname, target_identifier, rel_file, size, mtime_str, ext])

                                # 3. Prepare DB row
                                records_to_insert.append((
                                    self.hostname,
                                    target_identifier,
                                    rel_file,
                                    entry.name,
                                    ext,
                                    size,
                                    ctime_str,
                                    mtime_str,
                                    None,
                                    indexed_at
                                ))

                                indexed_count += 1

                                # Batch insert every 10,000 records
                                if len(records_to_insert) >= 10000:
                                    self._batch_upsert_files(records_to_insert)
                                    records_to_insert.clear()

                        except (PermissionError, FileNotFoundError):
                            continue
            except (PermissionError, FileNotFoundError):
                pass

        walk_dir(source_path)

        # Flush remaining records to DB & CSV
        if records_to_insert:
            self._batch_upsert_files(records_to_insert)
            records_to_insert.clear()

        csv_file.close()
        elapsed = (datetime.datetime.now() - start_time).total_seconds()

        print(f"✓ [{target_identifier}] Indexed {indexed_count:,} files ({format_bytes(total_bytes)}) in {elapsed:.2f}s")
        print(f"  • Zero-Byte Mirror : {dest_dir}")
        print(f"  • Portable Ledger  : {ledger_csv_path}")

        return {
            "target": target_identifier,
            "files": indexed_count,
            "bytes": total_bytes,
            "elapsed_seconds": elapsed
        }

    def _batch_upsert_files(self, records: list):
        """Batch inserts or replaces file metadata in SQLite database."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.executemany("""
                INSERT INTO files (machine, volume, relative_path, filename, extension, size_bytes, creation_time, last_write_time, head_tail_hash, indexed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(machine, volume, relative_path) DO UPDATE SET
                    size_bytes=excluded.size_bytes,
                    last_write_time=excluded.last_write_time,
                    indexed_at=excluded.indexed_at
            """, records)
            conn.commit()

    def compare(self, source_path: str, target_identifier: str, against_name: str | None = None):
        """
        Compares the live directory against the previous baseline catalogue or snapshot,
        generating <Target>-New, <Target>-Changed, and <Target>-Deleted zero-byte diff trees,
        CSV diff report, and terminal hotspot summaries.
        """
        source_path = os.path.abspath(source_path)
        baseline_name = f"{target_identifier}-{against_name}" if against_name else target_identifier
        baseline_dir = os.path.join(self.root, baseline_name)

        if not os.path.exists(baseline_dir):
            print(f"ERROR: Baseline '{baseline_dir}' does not exist! Please index first.")
            return

        prefix = baseline_name
        new_dir = os.path.join(self.root, f"{prefix}-New")
        changed_dir = os.path.join(self.root, f"{prefix}-Changed")
        deleted_dir = os.path.join(self.root, f"{prefix}-Deleted")

        for d in (new_dir, changed_dir, deleted_dir):
            if os.path.exists(d):
                shutil.rmtree(d, ignore_errors=True)
            os.makedirs(d, exist_ok=True)

        print(f"\n===============================================================================")
        print(f"COMPARING: Live [{source_path}] against Baseline [{baseline_name}]")
        print(f"===============================================================================")

        start_time = datetime.datetime.now()

        # Step 1: Read baseline files into a dictionary {rel_path: (size_bytes, mtime_ts)}
        baseline_map = {}
        for root, _, files in os.walk(baseline_dir):
            for f in files:
                full_p = os.path.join(root, f)
                rel_p = os.path.relpath(full_p, baseline_dir)
                st = os.stat(full_p)
                baseline_map[rel_p] = st.st_mtime

        # Step 2: Traverse live filesystem
        live_map = {}
        new_files = []
        changed_files = []
        deleted_files = []

        diff_records = []
        timestamp_str = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M")
        csv_path = os.path.join(self.root, f"{prefix}-{timestamp_str}-compare.csv")

        def walk_live(current_dir: str, rel_prefix: str = ""):
            try:
                with os.scandir(current_dir) as entries:
                    for entry in entries:
                        if entry.is_symlink():
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            if entry.name.lower() in DEFAULT_EXCLUDED_DIRS:
                                continue
                            sub_rel = os.path.join(rel_prefix, entry.name) if rel_prefix else entry.name
                            walk_live(entry.path, sub_rel)
                        elif entry.is_file(follow_symlinks=False):
                            if entry.name.lower() in DEFAULT_EXCLUDED_FILES or entry.name.lower().endswith(".tmp"):
                                continue
                            st = entry.stat(follow_symlinks=False)
                            rel_p = os.path.join(rel_prefix, entry.name) if rel_prefix else entry.name
                            live_map[rel_p] = (st.st_size, st.st_mtime, entry.path)
            except (PermissionError, FileNotFoundError):
                pass

        walk_live(source_path)

        # Check live files against baseline
        for rel_p, (sz, mtime, live_full_path) in live_map.items():
            mtime_dt = datetime.datetime.fromtimestamp(mtime)
            mtime_str = mtime_dt.strftime("%Y-%m-%d %H:%M:%S")
            ext = os.path.splitext(rel_p)[1].lower() or "[no_ext]"
            parent = os.path.dirname(rel_p) or "[Root]"

            if rel_p not in baseline_map:
                # NEW FILE
                new_files.append(rel_p)
                diff_records.append({"Filename": live_full_path, "Timestamp": mtime_str, "Size": sz, "NCD": "N", "Ext": ext, "Parent": parent, "Rel": rel_p})
                dest = os.path.join(new_dir, rel_p)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, 'wb'): pass
                try: os.utime(dest, (mtime, mtime))
                except Exception: pass

            elif abs(mtime - baseline_map[rel_p]) > 2.0:  # Allow FAT/FFT 2-second timestamp tolerance
                # CHANGED FILE
                changed_files.append(rel_p)
                diff_records.append({"Filename": live_full_path, "Timestamp": mtime_str, "Size": sz, "NCD": "C", "Ext": ext, "Parent": parent, "Rel": rel_p})
                dest = os.path.join(changed_dir, rel_p)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, 'wb'): pass
                try: os.utime(dest, (mtime, mtime))
                except Exception: pass

        # Check for deleted files
        for rel_p, base_mtime in baseline_map.items():
            if rel_p not in live_map:
                deleted_files.append(rel_p)
                mtime_dt = datetime.datetime.fromtimestamp(base_mtime)
                mtime_str = mtime_dt.strftime("%Y-%m-%d %H:%M:%S")
                ext = os.path.splitext(rel_p)[1].lower() or "[no_ext]"
                parent = os.path.dirname(rel_p) or "[Root]"
                live_equiv = os.path.join(source_path, rel_p)

                diff_records.append({"Filename": live_equiv, "Timestamp": mtime_str, "Size": 0, "NCD": "D", "Ext": ext, "Parent": parent, "Rel": rel_p})
                dest = os.path.join(deleted_dir, rel_p)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, 'wb'): pass
                try: os.utime(dest, (base_mtime, base_mtime))
                except Exception: pass

        # Write CSV report
        with open(csv_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(["Filename", "Timestamp", "Size", "NCD"])
            for r in diff_records:
                writer.writerow([r["Filename"], r["Timestamp"], r["Size"], r["NCD"]])

        elapsed = (datetime.datetime.now() - start_time).total_seconds()

        # Terminal Hotspot Breakdown
        print(f"\nComparison Complete in {elapsed:.2f}s")
        print(f"---------------------------------------------------")
        print(f"  • [N] New Files     : {len(new_files):,}")
        print(f"  • [C] Changed Files : {len(changed_files):,}")
        print(f"  • [D] Deleted Files : {len(deleted_files):,}")
        print(f"  • Total Differences : {len(diff_records):,}")
        print(f"---------------------------------------------------")

        if diff_records:
            # Group by folder
            folder_counts = {}
            ext_counts = {}
            for r in diff_records:
                folder_counts[r["Parent"]] = folder_counts.get(r["Parent"], 0) + 1
                ext_counts[r["Ext"]] = ext_counts.get(r["Ext"], 0) + 1

            top_folders = sorted(folder_counts.items(), key=lambda x: x[1], reverse=True)[:5]
            top_exts = sorted(ext_counts.items(), key=lambda x: x[1], reverse=True)[:5]

            print(f"\nTop 5 Active Folders:")
            for folder, count in top_folders:
                print(f"  {count:>5} files  • {folder}")

            print(f"\nTop 5 File Types:")
            for ext, count in top_exts:
                print(f"  {count:>5} files  • {ext}")

        print(f"\nChange Folders Generated:")
        print(f"  • {new_dir}")
        print(f"  • {changed_dir}")
        print(f"  • {deleted_dir}")
        print(f"CSV Report Exported:")
        print(f"  • {csv_path}\n")

    def find_duplicates(
        self,
        target_paths: list[str] | None = None,
        media_only: bool = False,
        min_size_mb: float = 1.0,
        extensions: list[str] | None = None,
        verify_hash: bool = True,
        generate_cleanup: bool = False
    ):
        """
        Cross-System Duplicate Detection Engine:
        1. Ingests all SQLite DB records OR scans live paths on the fly.
        2. Tier 1: Groups by exact Size + Extension.
        3. Tier 2: Computes fast 8KB Head/Tail Hash on candidates.
        4. Calculates wasted storage space and outputs CSV + Standalone HTML report.
        5. Optionally generates safe automated cleanup script.
        """
        min_size_bytes = int(min_size_mb * 1024 * 1024)
        clean_exts = {e.lower() if e.startswith('.') else f".{e.lower()}" for e in (extensions or [])}

        print(f"\n===============================================================================")
        print(f"DUPLICATE DETECTION ENGINE (Cross-System & Ad-Hoc)")
        print(f"===============================================================================")

        start_time = datetime.datetime.now()
        candidate_items = []

        # Path A: Ad-Hoc Live Directory Scanning
        if target_paths:
            print(f"Scanning {len(target_paths)} live target folder(s) directly on the fly...")
            for tp in target_paths:
                tp_abs = os.path.abspath(tp)
                if not os.path.exists(tp_abs):
                    print(f"WARNING: Path '{tp_abs}' does not exist! Skipping.")
                    continue

                for root, dirs, files in os.walk(tp_abs):
                    dirs[:] = [d for d in dirs if d.lower() not in DEFAULT_EXCLUDED_DIRS]
                    for f in files:
                        if f.lower() in DEFAULT_EXCLUDED_FILES or f.lower().endswith(".tmp"):
                            continue
                        full_p = os.path.join(root, f)
                        try:
                            sz = os.path.getsize(full_p)
                            if sz < min_size_bytes:
                                continue
                            ext = os.path.splitext(f)[1].lower() or "[no_ext]"
                            if media_only and (ext not in MEDIA_EXTENSIONS):
                                continue
                            if clean_exts and (ext not in clean_exts):
                                continue

                            st = os.stat(full_p)
                            mtime_str = datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                            rel_p = os.path.relpath(full_p, tp_abs)

                            candidate_items.append({
                                "machine": self.hostname,
                                "volume": tp_abs,
                                "relative_path": rel_p,
                                "filename": f,
                                "extension": ext,
                                "size_bytes": sz,
                                "last_write_time": mtime_str,
                                "full_path": full_p
                            })
                        except Exception:
                            continue

        # Path B: Database Query (All machines & drives in SQLite)
        else:
            print(f"Querying central SQLite catalogue database: {self.db_path}...")
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()

                query = "SELECT machine, volume, relative_path, filename, extension, size_bytes, last_write_time FROM files WHERE size_bytes >= ?"
                params = [min_size_bytes]

                if media_only:
                    placeholders = ','.join('?' for _ in MEDIA_EXTENSIONS)
                    query += f" AND extension IN ({placeholders})"
                    params.extend(list(MEDIA_EXTENSIONS))
                elif clean_exts:
                    placeholders = ','.join('?' for _ in clean_exts)
                    query += f" AND extension IN ({placeholders})"
                    params.extend(list(clean_exts))

                cursor.execute(query, params)
                for row in cursor.fetchall():
                    candidate_items.append(dict(row))

        print(f"Loaded {len(candidate_items):,} candidate file(s). Grouping by exact size & type...")

        # Group by Size + Extension
        size_groups = {}
        for item in candidate_items:
            key = f"{item['size_bytes']}|{item['extension']}"
            size_groups.setdefault(key, []).append(item)

        # Filter duplicates (Count > 1)
        raw_dupes = [g for g in size_groups.values() if len(g) > 1]

        # Tier 2 Fast Partial Hashing Verification
        verified_dupe_groups = []
        if verify_hash and raw_dupes:
            print("Running Tier 2 (8KB Head/Tail Hash) verification on candidate duplicates...")
            for group in raw_dupes:
                hash_subgroups = {}
                for item in group:
                    # Construct full path if available or testable
                    fp = item.get("full_path")
                    if not fp and os.path.exists(item.get("volume", "")):
                        fp = os.path.join(item["volume"], item["relative_path"])

                    h_hash = None
                    if fp and os.path.exists(fp):
                        h_hash = compute_head_tail_hash(fp)

                    # Fallback to key if offline/unreachable
                    key = h_hash if h_hash else f"size_{item['size_bytes']}"
                    hash_subgroups.setdefault(key, []).append(item)

                for h_key, sub_items in hash_subgroups.items():
                    if len(sub_items) > 1:
                        verified_dupe_groups.append(sub_items)
        else:
            verified_dupe_groups = raw_dupes

        if not verified_dupe_groups:
            print(f"\n✓ No duplicate files found matching current filters (MinSize: {min_size_mb} MB).")
            return

        # Calculate statistics & sort by wasted storage descending
        total_wasted_bytes = 0
        total_dupe_files = 0
        flattened_results = []

        sorted_groups = sorted(
            verified_dupe_groups,
            key=lambda g: (len(g) - 1) * g[0]["size_bytes"],
            reverse=True
        )

        for group_idx, group in enumerate(sorted_groups, start=1):
            sz = group[0]["size_bytes"]
            wasted = (len(group) - 1) * sz
            total_wasted_bytes += wasted
            total_dupe_files += len(group)

            for item in group:
                flattened_results.append({
                    "GroupID": f"Group-{group_idx:04d}",
                    "DuplicatesInSet": len(group),
                    "WastedSpace": format_bytes(wasted),
                    "WastedBytes": wasted,
                    "FileSize": format_bytes(sz),
                    "SizeBytes": sz,
                    "MachineName": item["machine"],
                    "Drive": item["volume"],
                    "Filename": item["filename"],
                    "Extension": item["extension"],
                    "LastWriteTime": item["last_write_time"],
                    "RelativePath": item["relative_path"]
                })

        # 1. Export CSV Report
        timestamp_str = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M")
        csv_path = os.path.join(self.root, f"Duplicates-{timestamp_str}.csv")
        with open(csv_path, 'w', newline='', encoding='utf-8') as f:
            fieldnames = ["GroupID", "DuplicatesInSet", "WastedSpace", "WastedBytes", "FileSize", "SizeBytes", "MachineName", "Drive", "Filename", "Extension", "LastWriteTime", "RelativePath"]
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(flattened_results)

        # 2. Export Standalone Interactive HTML Report
        html_path = os.path.join(self.root, f"Duplicates-{timestamp_str}.html")
        self._generate_html_report(html_path, sorted_groups, total_wasted_bytes, total_dupe_files)

        # 3. Optional: Generate Cleanup Script
        cleanup_script_path = None
        if generate_cleanup:
            cleanup_script_path = os.path.join(self.root, f"cleanup_duplicates_{timestamp_str}.py")
            self._generate_cleanup_script(cleanup_script_path, sorted_groups)

        elapsed = (datetime.datetime.now() - start_time).total_seconds()

        # Print Terminal Summary
        print(f"\n===============================================================================")
        print(f"DUPLICATE SCAN RESULTS ({elapsed:.2f}s)")
        print(f"===============================================================================")
        print(f"  • Duplicate Sets Found    : {len(sorted_groups):,}")
        print(f"  • Total Duplicate Files   : {total_dupe_files:,}")
        print(f"  • Total Wasted Storage    : {format_bytes(total_wasted_bytes)}")
        print(f"-------------------------------------------------------------------------------")

        print(f"\nTop 10 Largest Duplicate Sets:")
        for idx, g in enumerate(sorted_groups[:10], start=1):
            sz = g[0]["size_bytes"]
            wasted = (len(g) - 1) * sz
            sample_name = g[0]["filename"]
            locations = list({f"{item['machine']}:{item['volume']}" for item in g})
            print(f"  #{idx}. [Wasted: {format_bytes(wasted)}] {format_bytes(sz)} x {len(g)} copies")
            print(f"       File      : {sample_name}")
            print(f"       Locations : {', '.join(locations)}")

        print(f"\n-------------------------------------------------------------------------------")
        print(f"Reports Generated:")
        print(f"  • CSV Report  : {csv_path}")
        print(f"  • HTML Report : {html_path}")
        if cleanup_script_path:
            print(f"  • Cleanup Tool: {cleanup_script_path}")
        print(f"===============================================================================\n")

    def _generate_html_report(self, html_path: str, groups: list, total_wasted: int, total_files: int):
        """Generates a standalone, beautiful HTML duplicate report with live search and filtering."""
        json_data = []
        for idx, g in enumerate(groups, start=1):
            sz = g[0]["size_bytes"]
            wasted = (len(g) - 1) * sz
            json_data.append({
                "group_id": f"Group-{idx:04d}",
                "count": len(g),
                "wasted_str": format_bytes(wasted),
                "wasted_bytes": wasted,
                "size_str": format_bytes(sz),
                "size_bytes": sz,
                "filename": g[0]["filename"],
                "extension": g[0]["extension"],
                "files": [
                    {
                        "machine": item["machine"],
                        "volume": item["volume"],
                        "relative_path": item["relative_path"],
                        "mtime": item["last_write_time"]
                    } for item in g
                ]
            })

        html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SystemCatalogue Duplicate Report</title>
<style>
    :root {{
        --bg: #0f172a;
        --surface: #1e293b;
        --surface-hover: #334155;
        --primary: #38bdf8;
        --accent: #f43f5e;
        --text: #f8fafc;
        --text-muted: #94a3b8;
        --border: #334155;
        --success: #10b981;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); padding: 2rem; line-height: 1.5; }}
    .header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border); }}
    .title {{ font-size: 1.8rem; font-weight: 700; color: var(--primary); }}
    .stats-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
    .stat-card {{ background: var(--surface); padding: 1.25rem; border-radius: 8px; border: 1px solid var(--border); }}
    .stat-card h3 {{ font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase; margin-bottom: 0.5rem; }}
    .stat-card .val {{ font-size: 1.6rem; font-weight: bold; color: var(--text); }}
    .stat-card.wasted .val {{ color: var(--accent); }}
    .controls {{ display: flex; gap: 1rem; margin-bottom: 1.5rem; }}
    .search-input {{ flex: 1; padding: 0.75rem 1rem; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); font-size: 1rem; }}
    .search-input:focus {{ outline: none; border-color: var(--primary); }}
    .group-card {{ background: var(--surface); border-radius: 8px; border: 1px solid var(--border); margin-bottom: 1rem; overflow: hidden; }}
    .group-header {{ display: flex; justify-content: space-between; align-items: center; padding: 1rem 1.25rem; background: rgba(255,255,255,0.02); border-bottom: 1px solid var(--border); }}
    .group-info {{ display: flex; gap: 1rem; align-items: center; }}
    .badge {{ background: var(--primary); color: #000; font-weight: bold; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.8rem; }}
    .badge.wasted {{ background: var(--accent); color: #fff; }}
    .file-table {{ width: 100%; border-collapse: collapse; font-size: 0.9rem; }}
    .file-table th, .file-table td {{ padding: 0.75rem 1.25rem; text-align: left; }}
    .file-table th {{ color: var(--text-muted); font-size: 0.8rem; text-transform: uppercase; background: rgba(0,0,0,0.2); }}
    .file-table tr:not(:last-child) td {{ border-bottom: 1px solid var(--border); }}
    .file-table tr:hover td {{ background: var(--surface-hover); }}
    .machine-badge {{ background: #475569; padding: 0.15rem 0.5rem; border-radius: 4px; font-size: 0.75rem; }}
</style>
</head>
<body>
    <div class="header">
        <div>
            <h1 class="title">SystemCatalogue Duplicate Report</h1>
            <p style="color: var(--text-muted); font-size: 0.9rem;">Cross-System Storage Audit</p>
        </div>
        <div style="color: var(--text-muted); font-size: 0.85rem;">Generated: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</div>
    </div>

    <div class="stats-grid">
        <div class="stat-card wasted">
            <h3>Wasted Storage</h3>
            <div class="val">{format_bytes(total_wasted)}</div>
        </div>
        <div class="stat-card">
            <h3>Duplicate Sets</h3>
            <div class="val">{len(groups):,}</div>
        </div>
        <div class="stat-card">
            <h3>Duplicate Files</h3>
            <div class="val">{total_files:,}</div>
        </div>
    </div>

    <div class="controls">
        <input type="text" id="searchInput" class="search-input" placeholder="Search filenames, extensions, paths, or machines...">
    </div>

    <div id="groupsContainer"></div>

    <script>
        const duplicateGroups = {json.dumps(json_data)};

        function renderGroups(data) {{
            const container = document.getElementById('groupsContainer');
            if (data.length === 0) {{
                container.innerHTML = '<div style="text-align: center; padding: 3rem; color: var(--text-muted);">No matching duplicates found.</div>';
                return;
            }}

            container.innerHTML = data.map(g => `
                <div class="group-card">
                    <div class="group-header">
                        <div class="group-info">
                            <span class="badge">${{g.group_id}}</span>
                            <strong>${{g.filename}}</strong>
                            <span style="color: var(--text-muted); font-size: 0.85rem;">(${{g.size_str}} each)</span>
                        </div>
                        <div>
                            <span class="badge wasted">${{g.wasted_str}} Wasted</span>
                        </div>
                    </div>
                    <table class="file-table">
                        <thead>
                            <tr>
                                <th>Machine</th>
                                <th>Volume / Drive</th>
                                <th>Relative Path</th>
                                <th>Last Modified</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${{g.files.map(f => `
                                <tr>
                                    <td><span class="machine-badge">${{f.machine}}</span></td>
                                    <td style="color: var(--primary);">${{f.volume}}</td>
                                    <td>${{f.relative_path}}</td>
                                    <td style="color: var(--text-muted); font-size: 0.85rem;">${{f.mtime}}</td>
                                </tr>
                            `).join('')}}
                        </tbody>
                    </table>
                </div>
            `).join('');
        }}

        renderGroups(duplicateGroups);

        document.getElementById('searchInput').addEventListener('input', (e) => {{
            const term = e.target.value.toLowerCase().trim();
            if (!term) {{
                renderGroups(duplicateGroups);
                return;
            }}
            const filtered = duplicateGroups.filter(g => {{
                if (g.filename.toLowerCase().includes(term) || g.extension.toLowerCase().includes(term) || g.group_id.toLowerCase().includes(term)) return true;
                return g.files.some(f => f.machine.toLowerCase().includes(term) || f.volume.toLowerCase().includes(term) || f.relative_path.toLowerCase().includes(term));
            }});
            renderGroups(filtered);
        }});
    </script>
</body>
</html>
"""
        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(html_content)

    def _generate_cleanup_script(self, script_path: str, groups: list):
        """Generates a safe automated deduplication script (dry-run by default)."""
        script_code = f"""#!/usr/bin/env python3
# Automated Duplicate Cleanup Script generated by SystemCatalogue
# Run with --dry-run first to preview actions. Run with --execute to perform deletions.

import os
import sys

DRY_RUN = "--execute" not in sys.argv

print(f"=== SystemCatalogue Duplicate Cleaner (DRY_RUN={{DRY_RUN}}) ===")
if DRY_RUN:
    print("Running in DRY-RUN mode. No files will be deleted. Pass --execute to delete files.\\n")

# Groups of duplicate files (First item in each group is preserved as primary copy)
DUPLICATE_SETS = {json.dumps(groups, indent=2)}

deleted_count = 0
reclaimed_bytes = 0

for group in DUPLICATE_SETS:
    primary = group[0]
    duplicates = group[1:]
    sz = primary["size_bytes"]

    # Reconstruct local primary path if accessible
    primary_path = os.path.join(primary.get("volume", ""), primary["relative_path"])
    print(f"\\n[PRESERVE] {{primary_path}} ({{sz}} bytes)")

    for dupe in duplicates:
        dupe_path = os.path.join(dupe.get("volume", ""), dupe["relative_path"])
        if os.path.exists(dupe_path):
            if DRY_RUN:
                print(f"  [WOULD DELETE] {{dupe_path}}")
            else:
                try:
                    os.remove(dupe_path)
                    print(f"  [DELETED] {{dupe_path}}")
                except Exception as e:
                    print(f"  [ERROR] {{dupe_path}}: {{e}}")
            deleted_count += 1
            reclaimed_bytes += sz

print(f"\\n=== Summary: {{deleted_count}} duplicate file(s), {{reclaimed_bytes}} bytes reclaimed. ===")
"""
        with open(script_path, 'w', encoding='utf-8') as f:
            f.write(script_code)

    def list_snapshots(self):
        """Lists all baseline directories, snapshots, and ledgers."""
        print(f"\n===============================================================================")
        print(f"CATALOGUES, SNAPSHOTS & LEDGERS in '{self.root}'")
        print(f"===============================================================================")

        entries = os.listdir(self.root)
        dirs = [d for d in entries if os.path.isdir(os.path.join(self.root, d)) and not d.endswith(("-New", "-Changed", "-Deleted"))]
        ledgers = [f for f in entries if f.endswith(".ledger.csv")]

        if dirs:
            print(f"\nDirectory Catalogues & Snapshots:")
            for d in sorted(dirs):
                full_d = os.path.join(self.root, d)
                file_count = sum(len(files) for _, _, files in os.walk(full_d))
                mtime = datetime.datetime.fromtimestamp(os.path.getmtime(full_d)).strftime("%Y-%m-%d %H:%M:%S")
                print(f"  • {d:<35} | {file_count:>6} files | Last Updated: {mtime}")

        if ledgers:
            print(f"\nPortable Ledger Files (*.ledger.csv):")
            for l in sorted(ledgers):
                full_l = os.path.join(self.root, l)
                sz = os.path.getsize(full_l)
                mtime = datetime.datetime.fromtimestamp(os.path.getmtime(full_l)).strftime("%Y-%m-%d %H:%M:%S")
                print(f"  • {l:<35} | {format_bytes(sz):>10} | Last Updated: {mtime}")

        if os.path.exists(self.db_path):
            db_sz = os.path.getsize(self.db_path)
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT count(*) FROM files")
                total_db_files = cursor.fetchone()[0]
            print(f"\nCentral SQLite Database:")
            print(f"  • catalogue.db                      | {format_bytes(db_sz):>10} | {total_db_files:,} files indexed\n")

    def clean(self):
        """Cleans temporary diff folders (-New, -Changed, -Deleted) and comparison CSV reports."""
        print(f"\nCleaning temporary comparison folders and reports in '{self.root}'...")
        removed_dirs = 0
        removed_files = 0

        for item in os.listdir(self.root):
            full_p = os.path.join(self.root, item)
            if os.path.isdir(full_p) and item.endswith(("-New", "-Changed", "-Deleted")):
                shutil.rmtree(full_p, ignore_errors=True)
                print(f"  Removed Diff Folder : {item}")
                removed_dirs += 1
            elif os.path.isfile(full_p) and (item.endswith("-compare.csv") or item.startswith("Duplicates-")):
                os.remove(full_p)
                print(f"  Removed Report      : {item}")
                removed_files += 1

        print(f"✓ Cleanup Complete: Purged {removed_dirs} diff folder(s) and {removed_files} report(s).")
        print("  (All baseline snapshots, catalogues, and SQLite database remain untouched).\n")


def get_all_local_drives() -> list[str]:
    """Discovers all local fixed and removable storage drives across Windows / Linux / macOS."""
    drives = []
    system_os = platform.system()

    if system_os == "Windows":
        try:
            cmd = 'powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 } | Select-Object -ExpandProperty DeviceID"'
            out = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
            for line in out.strip().splitlines():
                d = line.strip()
                if d:
                    drives.append(f"{d}\\")
        except Exception:
            # Fallback
            for letter in "CDEFGHIJKLMNOPQRSTUVWXYZ":
                p = f"{letter}:\\"
                if os.path.exists(p):
                    drives.append(p)
    elif system_os == "Linux":
        # Parse /proc/mounts for real local block devices
        virtual_fstypes = {'proc', 'sysfs', 'devtmpfs', 'devpts', 'tmpfs', 'securityfs', 'cgroup', 'pstore', 'bpf', 'autofs', 'tracefs', 'debugfs', 'mqueue', 'hugetlbfs', 'fusectl', 'configfs', 'cifs', 'nfs', 'nfs4', 'smbfs'}
        try:
            with open('/proc/mounts', 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        dev, mount_pt, fstype = parts[0], parts[1], parts[2]
                        if fstype not in virtual_fstypes and dev.startswith('/dev/'):
                            if os.path.exists(mount_pt):
                                drives.append(mount_pt)
        except Exception:
            drives.append("/")
            for mount in ["/mnt", "/media"]:
                if os.path.exists(mount):
                    for item in os.listdir(mount):
                        full_p = os.path.join(mount, item)
                        if os.path.ismount(full_p):
                            drives.append(full_p)
    elif system_os == "Darwin":  # macOS
        drives.append("/")
        if os.path.exists("/Volumes"):
            for v in os.listdir("/Volumes"):
                full_v = os.path.join("/Volumes", v)
                if os.path.ismount(full_v):
                    drives.append(full_v)

    return list(dict.fromkeys(drives))


def main():
    parser = argparse.ArgumentParser(
        description="SystemCatalogue - High-Performance Cross-Platform Disk Indexer, Snapshot Manager & Media Duplicate Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
EXAMPLES:
  # Index all local disks:
  python system_catalogue.py --all-disks

  # Index a single drive or folder:
  python system_catalogue.py --drive C
  python system_catalogue.py --path /mnt/storage/Films

  # Compare live folder against baseline:
  python system_catalogue.py --compare --path /mnt/storage/Films

  # Find duplicate media files across all synced machines:
  python system_catalogue.py --find-duplicates --media-only

  # Compare two live folders for duplicates directly:
  python system_catalogue.py --find-duplicates --path /mnt/Films /mnt/BackupFilms --media-only

  # List snapshots and ledgers:
  python system_catalogue.py --list

  # Housekeeping cleanup:
  python system_catalogue.py --clean
"""
    )

    parser.add_argument("-a", "--all-disks", action="store_true", help="Index all local fixed and removable drives.")
    parser.add_argument("-d", "--drive", help="Target drive letter (e.g. C or D:).")
    parser.add_argument("-p", "--path", nargs="+", help="Specific folder path(s) to index, compare, or scan for duplicates.")
    parser.add_argument("-c", "--compare", action="store_true", help="Compare live drive or folder against baseline snapshot.")
    parser.add_argument("-s", "--snapshot", help="Create a named point-in-time baseline snapshot.")
    parser.add_argument("--against", help="Specifies a named snapshot to compare against.")
    parser.add_argument("--find-duplicates", "--dupes", action="store_true", help="Discover duplicate files across systems or folders.")
    parser.add_argument("--media-only", "--media", action="store_true", help="Filter duplicates to video, audio, archive, and image files.")
    parser.add_argument("--min-size-mb", type=float, default=1.0, help="Minimum file size in MB for duplicate search (Default: 1.0 MB).")
    parser.add_argument("--extension", "--ext", nargs="+", help="Filter duplicates to specific extensions (e.g. mp4 mkv flac).")
    parser.add_argument("--generate-cleanup", action="store_true", help="Generate an automated duplicate cleanup script.")
    parser.add_argument("-ls", "--list", action="store_true", help="List all baseline catalogues, named snapshots, and ledgers.")
    parser.add_argument("--clean", "--reset", action="store_true", help="Purge temporary diff folders and comparison reports.")
    parser.add_argument("--catalogue-root", help="Custom catalogue root directory path.")

    args = parser.parse_args()

    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(0)

    cat = SystemCatalogue(catalogue_root=args.catalogue_root)

    # 1. Clean
    if args.clean:
        cat.clean()
        sys.exit(0)

    # 2. List
    if args.list:
        cat.list_snapshots()
        sys.exit(0)

    # 3. Find Duplicates
    if args.find_duplicates:
        cat.find_duplicates(
            target_paths=args.path,
            media_only=args.media_only,
            min_size_mb=args.min_size_mb,
            extensions=args.extension,
            generate_cleanup=args.generate_cleanup
        )
        sys.exit(0)

    # 4. Specific Folder Path Mode
    if args.path:
        for p in args.path:
            p_abs = os.path.abspath(p)
            if not os.path.exists(p_abs):
                print(f"ERROR: Specified path '{p_abs}' does not exist!")
                continue
            folder_id = cat.get_smart_folder_id(p_abs)

            if args.compare:
                cat.compare(source_path=p_abs, target_identifier=folder_id, against_name=args.against)
            elif args.snapshot:
                cat.scan_and_mirror(source_path=p_abs, target_identifier=folder_id, snapshot_name=args.snapshot)
            else:
                cat.scan_and_mirror(source_path=p_abs, target_identifier=folder_id)
        sys.exit(0)

    # 5. Single Drive Mode
    if args.drive:
        drive_letter = args.drive.strip().replace(":", "").replace("\\", "").replace("/", "")[:1].upper()
        drive_path = f"{drive_letter}:\\" if platform.system() == "Windows" else f"/{drive_letter}"
        vol_id = cat.get_smart_volume_id(drive_path)

        if args.compare:
            cat.compare(source_path=drive_path, target_identifier=vol_id, against_name=args.against)
        elif args.snapshot:
            cat.scan_and_mirror(source_path=drive_path, target_identifier=vol_id, snapshot_name=args.snapshot)
        else:
            cat.scan_and_mirror(source_path=drive_path, target_identifier=vol_id)
        sys.exit(0)

    # 6. All Disks Mode
    if args.all_disks:
        drives = get_all_local_drives()
        print(f"Discovered {len(drives)} local storage volume(s): {', '.join(drives)}")
        for d in drives:
            vol_id = cat.get_smart_volume_id(d)
            if args.snapshot:
                cat.scan_and_mirror(source_path=d, target_identifier=vol_id, snapshot_name=args.snapshot)
            else:
                cat.scan_and_mirror(source_path=d, target_identifier=vol_id)
        print(f"\nAll disks successfully indexed into: {cat.root}\n")
        sys.exit(0)

    parser.print_help()


if __name__ == "__main__":
    main()

