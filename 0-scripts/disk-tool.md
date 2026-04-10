# 🛠️ disk-tool.sh — Documentation & Safety Guide

Formatting a disk can be a nerve-wracking experience. This tool is designed to provide "industrial-strength" safeguards while performing powerful disk operations. It wraps standard Linux tools (`parted`, `wipefs`, `mkfs`) into a predictable, idempotent, and highly-aligned workflow.

## 🚀 Quick Usage

| Command | Action |
| :--- | :--- |
| `disk-tool.sh` | **Show:** List all disks, partitions, and current usage. |
| `sudo disk-tool.sh -wipe sda` | **Destructive:** Wipe partition table and all signatures from disk `sda`. |
| `sudo disk-tool.sh -create sda -type btrfs -label DATA` | **Build:** Create GPT label + 100% partition + format as Btrfs. |
| `sudo disk-tool.sh -setup-btrfs sda1` | **Optimize:** Create subvolumes (`@data`, etc.) and get `fstab` tips. |

---

## 🛡️ Safety Features
1. **The "YES" Confirmation:** No destructive action happens without you typing `YES` in all caps.
2. **Whole-Disk Protection:** The `-create` command refuses to run on partitions (e.g., `sda2`) to prevent accidental double-nesting or logic errors.
3. **Alignment Intelligence:** Automatically uses **1MiB alignment** for partitions. This is critical for modern "Advanced Format" 4k sector drives (8TB+) to prevent massive performance degradation.

---

## 📂 Supported Filesystems

| Type | Best For | Capabilities |
| :--- | :--- | :--- |
| **Btrfs** | **General Data / Syskit** | Snapshots, Compression, Subvolumes, Checksums. |
| **Ext4** | **Standard Linux / OS** | Rock solid, industry standard, very fast for small files. |
| **XFS** | **Huge Files / Databases** | Excellent parallel IO, great for 20TB+ file servers. |
| **NTFS** | **Windows Compatibility** | Use this if the drive needs to be plugged into a PC. |
| **Ext3** | **Legacy / Simple** | Older variant of Ext4. Rarely used for new builds. |

---

## 📖 Strategy Guides
For detailed optimization, parameters, and large-drive strategies, see the specific guides:

- [Btrfs Guide (Recommended)](file:///Users/boss/syskit/0-scripts/disk-tool-btrfs.md)
- [XFS Guide (Big Data)](file:///Users/boss/syskit/0-scripts/disk-tool-xfs.md)
- [Ext4 Guide (Classic)](file:///Users/boss/syskit/0-scripts/disk-tool-ext4.md)
- [NTFS Guide (Portable)](file:///Users/boss/syskit/0-scripts/disk-tool-ntfs.md)

---

## 💡 Pro Tips
- **The Label is your friend:** Always use `-label` during creation. It makes finding the drive in `/dev/disk/by-label/` much easier than memorizing `sda` vs `sdb`.
- **Always partprobe:** Sometimes the kernel doesn't "see" the new partition immediately. Running `partprobe` (included in the script) helps the OS refresh its view.
