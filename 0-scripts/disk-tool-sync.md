# 🛡️ Two-Node Sync Guide: Btrfs + Syncthing

This guide covers the strategy for syncing two semi-identical systems (e.g., a Z240 and an Optiplex 5050) over the internet using **Btrfs** and **Syncthing**. This combination provides both data availability and extreme protection against silent corruption.

---

## 🏗️ The "Industrial Strength" Architecture

| Component | Responsibility |
| :--- | :--- |
| **Btrfs** | **Local Integrity:** Detects bit-rot and hardware errors via checksums. |
| **Syncthing** | **Global Sync:** Moves files between nodes and manages conflicts. |
| **Snapshots** | **Safety Net:** Protects against "synchronized mistakes" (accidental deletes). |

---

## 🚀 Optimized Setup Strategy

### 1. Btrfs Foundation (Both Nodes)
Use the standard "Best Practices" build for your 8TB drives:
```bash
# Node 1 (Z240) & Node 2 (Optiplex)
sudo ./disk-tool.sh -create sda -type btrfs -label SYNC_DATA
sudo ./disk-tool.sh -setup-btrfs sda1
```
*Ensure you use the generated `compress=zstd:3,noatime,autodefrag` flags in your fstab.*

### 2. High-Performance Syncthing Layout
For the best experience on 16GB RAM / NVMe + HDD systems:
*   **Keep the Config/DB on NVMe:** Syncthing performs thousands of tiny database writes. Ensure the Syncthing folder (usually `~/.local/state/syncthing`) stays on your **NVMe OS drive**.
*   **Put the Data on HDD:** Point Syncthing to the `/mnt/data` (which maps to your `@data` subvolume) on the 8TB HDD.

### 3. The "Inotify" Power-Up
Syncthing needs to "watch" your 8TB drive for changes. Large drives with millions of files often hit the default Linux limit. Run this on both nodes:
```bash
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## 🛡️ The "Snapshot Safety Net"
**CRITICAL:** Syncthing is a *Sync* tool, not a *Backup* tool. If you delete a file on the Z240, Syncthing will instantly delete it on the Optiplex. 

**The Solution:** Use Btrfs Snapshots.
Even if Syncthing "syncs a mistake," you can roll back to a point-in-time snapshot on either machine.

*   **Take a manual snapshot before big changes:**
    ```bash
    sudo btrfs subvolume snapshot /mnt/data /mnt/snaps/pre-sync-cleanup
    ```
*   **Recommended Tool:** Setup `snapper` or a simple cron job to take daily snapshots of your `@data` subvolume.

---

## 🔬 Why this beats a standard Cloud Sync
1.  **Bit-rot Detection:** If the HDD on the Optiplex develops a bad sector, Btrfs will catch the checksum error. Syncthing will then see the file "failed to read" and stop, preventing the corruption from syncing back to your Z240.
2.  **Compression:** Using `zstd:3` on the disk means you can store ~10TB of raw data on your 8TB drive (depending on file types).
3.  **No Middleman:** Your data is only on your hardware, encrypted in transit between your own two machines.

---

## 💡 Summary Syntax
**Nodes:** Z240 (Home) <---> Optiplex 5050 (Offsite)
**Filesystem:** Btrfs (Metadata DUP, Data ZSTD)
**Sync Tool:** Syncthing (ID: `<ID-A>` <---> `<ID-B>`)
**Mounts:** `subvol=@data,compress=zstd:3,noatime,autodefrag,space_cache=v2`
