# 🛡️ XFS Guide: Huge Data Storage (20TB+)

XFS is the go-to filesystem for massive 20TB+ storage arrays. It is rock-solid, incredibly fast for parallel reads/writes, and scale-out friendly. If you have "BIG DATA" and don't need snapshots or compression, XFS is the industry choice.

## 🚀 20TB+ Strategy: Best Practices

| Strategy | Rationale |
| :--- | :--- |
| **Big Metadata (`crc=1`)** | **Reliability:** Self-describing metadata means its integrity is checked automatically. Default in modern systems. |
| **Log Space Optimization** | **Speed:** Excellent at journaling changes without slowing down the main data drive. |
| **Dynamic Inodes** | **Flexibility:** Scales to billions of files without pre-allocating inode tables (unlike Ext4). |

---

## 🛠️ Step-by-Step Build Syntax

### 1. Build the Low-Level Partition & Format
The script ensures the GPT alignment is correct for 4k sectors:
```bash
sudo ./disk-tool.sh -create sda -type xfs -label MASSIVE_DATA
```
*Note: XFS doesn't have "subvolumes" like Btrfs. It treats the whole partition as one flattened space.*

---

## ⚙️ Optimized `/etc/fstab` Options
XFS is very smart out of the box. Your `fstab` shouldn't have too many "manual" flags:

```fstab
UUID=<UUID>  /mnt/data  xfs  defaults,noatime,logbsize=256k  0  0
```

### Why these flags?
*   `noatime`: As with Btrfs, skip the time-stamp update on every read. Huge speed gain.
*   `logbsize=256k`: For larger drives (8TB+), increasing the log buffer helps with faster throughput.

---

## 🔍 Managing your XFS Drive
| Command | Action |
| :--- | :--- |
| `xfs_info /mnt/data` | Get technical details about the geometry. |
| `xfs_db /dev/sda1` | Examine the structure (advanced debug). |
| `xfs_growfs /mnt/data` | Expand the filesystem instantly if you resize the partition. |

---

## 🆚 XFS vs Btrfs: Which should I choose?
Choose **XFS** if:
1. You have **extremely high throughput** (parallel writes).
2. You don't want the performance overhead of **Compression or Snapshots**.
3. You have **huge files** (1TB+ per file).

Choose **Btrfs** if:
1. You want **Snapshots** and **Versioned Backups**.
2. You want to save **disk space** with `zstd` compression.
3. You want **self-healing** (checksums) to protect against bit-rot.
