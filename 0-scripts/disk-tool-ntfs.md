# 🛡️ NTFS Guide: Portable Compatibility

NTFS is the primary filesystem for Windows. While Btrfs and XFS are Linux-native, if you need to plug your 8TB drive into a PC, use **NTFS**.

## 🚀 Strategy: Best Practices

| Strategy | Rationale |
| :--- | :--- |
| **ACL Management** | **Portability:** NTFS stores Windows permissions, which can be tricky on Linux. I use `ntfs-3g` defaults for compatibility. |
| **Quick Format (`-f`)** | **Speed:** A full format on 8TB would take days! My script uses `-f` to zero just the metadata. |

---

## 🛠️ Step-by-Step Build Syntax

### Build the Low-Level Partition & Format
The script aligns the GPT label and formats as NTFS:
```bash
sudo ./disk-tool.sh -create sda -type ntfs -label WINDOWS_8TB
```

---

## ⚙️ Optimized Linux `/etc/fstab` Options
For NTFS on Linux, you need to tell Linux how to handle Windows users:

```fstab
UUID=<UUID>  /mnt/data  ntfs-3g  defaults,uid=1000,gid=1000,umask=0022  0  0
```

### Why these flags?
*   `uid=1000,gid=1000`: Forces Linux to treat you as the owner of every file on the drive.
*   `umask=0022`: Sets standard Linux "rwxr-xr-x" permissions for files/folders.
*   `windows_names`: Strictly enforces Windows naming rules (useful for cross-compatibility).

---

## 🔍 Managing your NTFS Drive
| Command | Action |
| :--- | :--- |
| `ntfsfix /dev/sda1` | Fix common NTFS metadata corruption from Linux. |
| `ntfsprogs` | A suite of tools like `ntfsclone` and `ntfsresize`. |

---

## 💡 Important Note: BitLocker
If you plan on using this drive with **BitLocker** encryption on Windows, Linux can only read it using a special tool called `dislocker`. For simplicity across both OSes, **unencrypted NTFS** is the most portable option.
