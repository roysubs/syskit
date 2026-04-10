# 🛡️ Btrfs Guide: Large Drive Optimization (4TB–20TB+)

Btrfs is the "industrial strength" filesystem for Linux. It protects against data corruption and has built-in compression. For a large storage drive (like your 8TB HDD), special considerations are needed for maximum performance and reliability.

## 🚀 8TB+ Strategy: Best Practices

| Strategy | Rationale |
| :--- | :--- |
| **Metadata Duplication (`-m dup`)** | **Reliability:** Writes two copies of vital filesystem metadata. If one sector dies, your whole 8TB drive isn't lost. |
| **Subvolumes (`@data`, `@snaps`)** | **Management:** Cleanly separates your data from your snapshots. Makes mount points much easier to handle. |
| **Compression (`zstd:3`)** | **Performance & Space:** Saves 20-40% space and reduces physical HDD head movement (less IO). |
| **1MiB Alignment** | **Speed:** Ensures the partition starts exactly on a 4k physical sector boundary. Prevents "write amplification" slowness. |

---

## 🛠️ Step-by-Step Build Syntax

### 1. Build the Low-Level Partition & Format
The script aligns the partition and forces `metadata DUP` for you:
```bash
sudo ./disk-tool.sh -create sda -type btrfs -label STORAGE_8TB
```

### 2. Setup the High-Level Subvolumes
Once the disk is formatted, this command creates the "invisible" subfolders:
```bash
sudo ./disk-tool.sh -setup-btrfs sda1
```
It will output the following:
- `@data` subvolume (for your files)
- `@snapshots` subvolume (for backups)
- `@backups` subvolume (for other disk images)

---

## ⚙️ Optimized `/etc/fstab` Options
For a large HDD, your `fstab` line should look like this (the script will generate the UUID for you):

```fstab
UUID=<UUID>  /mnt/data  btrfs  subvol=@data,compress=zstd:3,noatime,autodefrag,space_cache=v2  0  0
```

### Why these flags?
*   `compress=zstd:3`: Excellent balance of speed and space. Best for large 8TB+ drives.
*   `noatime`: Disables writing "last accessed time" on every read. Massively reduces disk noise/writes.
*   `autodefrag`: **Crucial for HDDs.** Keeps fragmented files (like databases or game libraries) defragmented in the background.
*   `space_cache=v2`: Faster mounting and better safety for large filesystems.

---

## 🔍 Managing your Btrfs Drive
| Command | Action |
| :--- | :--- |
| `btrfs filesystem usage /mnt/data` | Check actual vs. raw space (shows compression ratio). |
| `btrfs scrub start /mnt/data` | Scan disk for errors and fix them (checksum verification). |
| `btrfs subvolume list /mnt/data` | List all subvolumes. |

---

## 💡 Pro Tip: NoCOW on Large Files
If you store **Virtual Machine images** or **Database files** on your 8TB drive, Btrfs "Copy on Write" (COW) can cause extreme fragmentation. Run this on specific large files or folders to speed them up:
```bash
sudo chattr +C /mnt/data/vms/windows_10.qcow2
```
