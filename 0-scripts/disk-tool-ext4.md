# 🛡️ Ext4 Guide: Classic Reliability

Ext4 is the standard, rock-solid filesystem for most Linux distributions. If you're building a system drive or a partition for standard apps/tools, Ext4 is the classic, zero-hassle choice.

## 🚀 Strategy: Best Practices

| Strategy | Rationale |
| :--- | :--- |
| **Journaling (`ordered`)** | **Safety:** Protects your filesystem from power loss or system crashes. |
| **Reserved Block Management** | **Efficiency:** By default, Ext4 reserves 5% of your disk for root. On an 8TB drive, that's 400GB! You should lower this to 1%. |
| **Stride/Stripe Alignment** | **Speed:** My script aligns the GPT partition to 1MiB to keep your HDD "happy" and fast. |

---

## 🛠️ Step-by-Step Build Syntax

### 1. Build the Low-Level Partition & Format
The script Align and format the GPT label automatically:
```bash
sudo ./disk-tool.sh -create sda -type ext4 -label SYSTEM_DATA
```

### 2. Post-Build: The "8TB Extra Space" Hack
Because Ext4 reserves 5% by default (meant for OS/Root drives), on a large data drive, you can "reclaim" hundreds of gigabytes:
```bash
sudo tune2fs -m 1 /dev/sda1
```
*This changes the reserved space from 5% down to 1%—liberating roughly 320GB on an 8TB drive!*

---

## ⚙️ Optimized `/etc/fstab` Options
For Ext4 on a large data drive, use these flags in `fstab`:

```fstab
UUID=<UUID>  /mnt/data  ext4  defaults,noatime,commit=60  0  2
```

### Why these flags?
*   `noatime`: Stops the HDD from writing "accessed time" on every read. Massively speeds up your system.
*   `commit=60`: Tells Ext4 to wait 60 seconds before flushing changes to the physical disk. Improves performance during heavy write tasks.

---

## 🔍 Managing your Ext4 Drive
| Command | Action |
| :--- | :--- |
| `df -hT /mnt/data` | Check usage (and fs type). |
| `fsck /dev/sda1` | Check and repair the filesystem (use while unmounted). |
| `dumpe2fs /dev/sda1` | Dump the superblocks and metadata status. |

---

## 💡 Pro Tip: When NOT to use Ext4
While Ext4 is amazing for general use, **Btrfs** is often better for a "syskit" 8TB drive because Ext4 lacks **deduplication and compression**. If you have lots of backups or similar files, you'll waste much more physical space on Ext4 than Btrfs.
