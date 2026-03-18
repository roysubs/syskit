This summary outlines the "Best Path" for a high-performance, ransomware-resilient personal cloud on Debian. This architecture avoids the "packaging mess" by using containers for apps and the Linux Kernel (Btrfs) for data integrity.

### **Phase 1: The OS Foundation**

* **Distro:** Install **Debian Stable** (Bookworm or Trixie/13).
* **Disk Layout:**
* **240 GB SSD:** OS (`/`) using Ext4 or Btrfs.
* **8 TB HDD:** Dedicated for data, formatted as **Btrfs**.


* **Btrfs Mount Options:** Edit `/etc/fstab` for the 8 TB drive to maximize performance and longevity:
`noatime,compress=zstd:3,space_cache=v2,autodefrag`
* **Structure:** Create Btrfs subvolumes for organization:
* `/mnt/data/live_sync` (The active data pool).
* `/mnt/data/.snapshots` (The root-only vault).



### **Phase 2: The Container Engine**

* **Tooling:** Install **Docker** and **Docker Compose**.
* **Rationale:** Even though the industry is shifting toward Podman/Kubernetes, Docker remains the most pragmatic, idempotent choice for Debian servers in 2026 due to its stable Compose spec.
* **Hardening:** Ensure the Docker daemon is configured, but plan to run your specific containers as a non-root user (UID 1000) inside the Compose file.

### **Phase 3: The Application Layer (Containers)**

Deploy **Syncthing** and **SFTPGo** via a single `docker-compose.yml`:

* **Syncthing:** Handles the "Transport Layer" (syncing across the internet).
* **SFTPGo:** Provides a high-performance interface for file access/management.
* **Isolation:** Only map the `/mnt/data/live_sync` subvolume into these containers. **Do not** map the root of the data drive or the snapshot folder.

### **Phase 4: Tooling & Maintenance**

* **Maintenance:** Schedule a monthly **Btrfs Scrub** via crontab to detect and repair bit-rot on the 8 TB platter:
`0 2 1 * * /usr/sbin/btrfs scrub start -B /mnt/data`
* **Monitoring:** Use `htop` and `iotop` to monitor the 8 GB RAM usage; Btrfs and Docker together will comfortably fit in this footprint for 4 TB–8 TB of data.

---

### **Phase 5: The "Bunker" & Hardening (Summary)**

* **The Concept:** Create a "Temporal Air-Gap." The sync apps are allowed to be "messy," but the Host OS is the ultimate arbiter of truth.
* **Kernel-Level Protection:** Use a **Root-owned Cron script** to take periodic **Read-Only (`-r`)** Btrfs snapshots of the `live_sync` subvolume.
* **Access Control:**
* The **Sync User** can see and modify `live_sync`.
* Only **Super-Root** can see or enter the `.snapshots` directory (`chmod 700`).


* **Ransomware Mitigation:** If a remote client syncs encrypted files, the "Bunker" holds the clean, immutable blocks from 4–24 hours ago. Recovery is a simple `btrfs subvolume delete` (of the corrupted live data) and a `btrfs subvolume snapshot` (of the clean backup) to restore the state instantly.
* **Churn Management:** Manually prune snapshots or wipe the vault and "re-snap" after massive data migrations to reclaim space on the 8 TB drive.

---

Smart choice. There is a massive "pragmatism" argument for sticking with what you’ve already automated. In the words of the Linux philosophy: **"If it ain't broke, don't fix it."**

Since your Syncthing logic is already idempotent and ready to go, the only thing left is to "lock the vault." Here is the **Bunker Script** and the hardening steps to make your Debian + Btrfs + Docker setup virtually bulletproof.

---

## The "Bunker" Snapshot Script

Save this as `/usr/local/bin/btrfs-bunker` and `chmod +x` it. This script takes your live Syncthing data and creates a **read-only** snapshot that even a hijacked Docker container can't see.

```bash
#!/bin/bash
# Configuration
SOURCE="/mnt/data/live_sync"
DEST_DIR="/mnt/data/.snapshots"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
KEEP_DAYS=30

# 1. Ensure snapshot directory exists and is root-only
mkdir -p "$DEST_DIR"
chmod 700 "$DEST_DIR"

# 2. Create the Read-Only snapshot
btrfs subvolume snapshot -r "$SOURCE" "$DEST_DIR/snapshot_$TIMESTAMP"

# 3. Clean up snapshots older than X days
find "$DEST_DIR" -maxdepth 1 -name "snapshot_*" -mtime +$KEEP_DAYS -exec btrfs subvolume delete {} \;

```

## The Hardening Checklist

To ensure your "Ultra-Root" protection works, verify these three things:

* **Path Isolation:** Ensure your Docker volume mapping points *only* to `/mnt/data/live_sync`. **Never** map the parent `/mnt/data` or the `.snapshots` directory into the container.
* **The Docker User:** In your `docker-compose.yml`, specify a non-root user (e.g., `user: "1000:1000"`). This ensures that even if there's a container breakout, the attacker doesn't land in your host as `root`.
* **The Cron Job:** Run the bunker script via the **root crontab** (`sudo crontab -e`).
* *Example (Every 4 hours):* `0 */4 * * * /usr/local/bin/btrfs-bunker`

## Why this setup is "Endgame"

* **Performance:** You're using native Debian + Btrfs. No Kubernetes networking overhead, no complex "overlay" filesystems.
* **Safety:** If ransomware encrypts your files, Syncthing will sync the "garbage" to `live_sync`. You simply go to `.snapshots`, find the one from 4 hours ago, and `cp` or `btrfs send` the clean data back.
* **Simplicity:** You’re using tools that will still be around in 20 years.

---

### Final Tip for the 8 TB Drive

Since you are using Btrfs on a large mechanical drive, run a **scrub** once a month to check for "bit rot" (silent data corruption). Btrfs will use its checksums to verify every single block on that 8 TB disk.

`sudo btrfs scrub start /mnt/data`

---

In practice, Btrfs snapshots are elegant because they are **invisible**. There is no "blob," no "vault file," and no reserved partition.

Here is exactly how it works on your 8 TB disk:

### 1. Where do snapshots "live"?

Snapshots are just special **subvolumes**. In your filesystem, a snapshot looks exactly like a normal folder.

* You can `cd` into it.
* You can `ls` the files.
* You can even `cp` a single file out of a snapshot if you accidentally deleted it in your "live" folder.

Because they are subvolumes, you can choose where they appear in your directory tree. As we discussed, for security, you should put them in a folder like `/mnt/data/.snapshots/` and set that folder to `chmod 700` so only **root** can see into it.

### 2. Is there a "massive blob"?

**No.** This is the "magic" of Copy-on-Write (CoW).
When you take a snapshot of a 4 TB folder, Btrfs doesn't copy a single byte of data. It simply creates a new "index" (a B-tree) that points to the exact same data blocks on the physical disk that the original folder uses.

* **Initial Size:** A new snapshot takes up a few **kilobytes** of metadata.
* **The "Blob" concept:** There is no blob. There is just a pool of data blocks on your 8 TB drive. Some blocks are "claimed" by your live folder, some are "claimed" by your snapshots, and most are shared by both.

### 3. Does the available space change?

Yes, but only as you **modify** data.

* **Scenario A (Static Data):** You have 4 TB of data and 10 snapshots. If you never change a file, your disk usage remains exactly 4 TB. The snapshots cost you nothing.
* **Scenario B (The Churn):** You have a 1 GB file. You take a snapshot. Then, you delete that 1 GB file in your "live" folder.
* On a normal OS (Ext4), your free space would increase by 1 GB.
* On Btrfs, **your free space stays the same.** Why? Because that 1 GB of data is still being "held" by the snapshot.


* **When do you get space back?** Only when the **last** reference to a data block is deleted. If you delete the file *and* delete all snapshots that saw that file, the 1 GB is finally marked as "free."

### 4. How the "Delta Space" works

Think of your 8 TB drive as a big bucket of blocks.

1. You fill **4 TB** with your personal cloud.
2. You have **4 TB of empty space** remaining.
3. Every time you change or delete a file, Btrfs doesn't overwrite the old version; it writes the *new* version into that 4 TB of empty space.
4. As long as you keep the snapshot, the "old" version stays where it was.

In your case, having 4 TB of free space on an 8 TB drive means you could literally **overwrite every single file in your cloud** and still have enough room to keep the old versions in a snapshot.

### Summary: Why you don't need the 8 TB secondary

You only need a second 8 TB disk if you are worried about the **physical hardware** of the first disk dying (motor failure, head crash).

For **Ransomware Protection**, the "Deltas" (the previous versions of your files) are stored in the unused parts of your primary 8 TB disk. Btrfs manages this automatically—it's like having an "undo" button that can go back as far as your oldest snapshot, without ever needing a second drive.

---

**Would you like me to show you the command to see "Real" space usage? (Standard `df -h` lies on Btrfs because it doesn't understand shared blocks!)**

**Would you like me to help you refine your existing idempotent scripts to include the Btrfs subvolume creation logic so the whole drive setup is automated too?**
