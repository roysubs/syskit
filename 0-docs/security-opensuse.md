# openSUSE Security Architecture & Administration Guide

A comprehensive guide to openSUSE Leap & Tumbleweed security mechanisms, networking defaults, file permissions, and system hardening rules.

---

## 1. Executive Summary: openSUSE vs. Debian/Ubuntu

Unlike Debian or Ubuntu (which ship with minimal default firewall rules and ext4 filesystems), openSUSE is engineered with **security-by-default**, **resilient rollbacks**, and **enterprise audit tools** out-of-the-box.

| Security Feature | openSUSE Leap / Tumbleweed | Debian / Ubuntu |
| :--- | :--- | :--- |
| **Default LSM** | **AppArmor** (Active & pre-configured) | AppArmor (Ubuntu) / None (Debian default) |
| **Firewall** | **`firewalld`** (Active `public` zone blocks all ports) | `ufw` (Inactive by default on Debian) |
| **Permission Audit** | **`chkstat`** (`/etc/sysconfig/security`) | None |
| **Default Root FS** | **Btrfs** with Snapper Read-Only Snapshots | ext4 |
| **Desktop Elevation** | **Polkit** (Requires root password for YaST) | `sudo` user password |
| **Brute-Force Protection** | **`pam_faillock`** (Locks account after 3-5 failures) | Manual `fail2ban` required |

---

## 2. Network & Storage Sharing Security

### 2.1 The Two-Layer Security Model (Samba & NFS)

When sharing storage across a network on openSUSE, access is evaluated through **two independent security layers**:

```
[ Remote PC / Client ]
         │
         ▼
┌─────────────────────────────────────────┐
│ Layer 1: Samba Protocol (smb.conf)      │  <-- Network share options (writable = yes)
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Layer 2: Linux Kernel Filesystem (POSIX)│  <-- Local folder permissions (chmod / chown)
└─────────────────────────────────────────┘
         │
         ▼
[ Hard Drive Storage / Btrfs / NTFS ]
```

* **Layer 1 (Samba/NFS Layer):** Governed by `/etc/samba/smb.conf` or `/etc/exports`. Defines whether a share is network-writable (`writable = yes`).
* **Layer 2 (Linux Filesystem Layer):** Governed by local Linux POSIX permissions on `/mnt/` or `/data`. 
* **The Gotcha:** Even if `smb.conf` permits writing, if the local folder is owned by `root:root` with `755` permissions, the Linux kernel will block network write attempts with **`Permission Denied`**.

---

### 2.2 Decoding `chmod -R a+rwX`

When granting filesystem permissions for shared volumes, `chmod -R a+rwX /mnt/drive` is the standard command. Here is how each character works:

* **`-R` (Recursive):** Applies permissions to the target folder **and all files/subfolders** inside it.
* **`a+` (All Users, Add):**
  * `a` = **All** user categories (User Owner `u`, Group `g`, and Others `o`).
  * `+` = **Add** permissions (without stripping existing permissions).
* **`r` (Read):** Grants file reading and directory listing privileges.
* **`w` (Write):** Grants file editing, creation, and deletion privileges.
* **`X` (Conditional Execute — Capital 'X'):**
  * *Lowercase `x`* makes **every single file** executable (making text files and images look like runnable scripts).
  * *Uppercase `X`* is **conditional**: It ONLY adds execute permissions to **directories** (which Linux requires so users can enter subfolders) and to files that already have execute permissions!

---

### 2.3 openSUSE `firewalld` Integration

Because `firewalld` is active by default on openSUSE, network services (Samba, NFS, Cockpit, SSH) must be allowed through the firewall:

```bash
# Allow Samba permanently through openSUSE firewalld
sudo firewall-cmd --permanent --add-service=samba
sudo firewall-cmd --reload

# Allow NFS permanently
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --reload

# Check currently open services
sudo firewall-cmd --list-services
```

---

## 3. openSUSE Core System Hardening

### 3.1 Security Levels (`/etc/sysconfig/security`) & `chkstat`

openSUSE includes a security management tool called **`chkstat`**.
* System security profiles are configured in `/etc/sysconfig/security` (`PERMISSION_SECURITY="easy local"`).
* **Security Profiles:**
  * **`easy` / `local`:** Default workstation profile.
  * **`secure`:** Disables SUID bits on binaries like `ping` or `mount` for unprivileged users.
  * **`paranoid`:** Maximum isolation for high-security servers.
* `chkstat` runs periodically (and during package installation) to check binary permissions against policy files in `/etc/permissions*` and automatically reset unauthorized modifications.

---

### 3.2 AppArmor Mandatory Access Control (vs. SELinux on Red Hat)

openSUSE uses **AppArmor** as its default Linux Security Module (LSM).

* **On openSUSE (AppArmor):** **No interference!** AppArmor's default Samba profile (`/etc/apparmor.d/usr.sbin.smbd`) permits reading and writing to `/mnt/`, `/media/`, and `/srv/` out of the box. You do not need SELinux labels or booleans.
* **On Red Hat / RHEL (SELinux):** SELinux **will** block Samba shares on custom folders like `/mnt/sda1` unless you label the directory or set the SELinux boolean:
  ```bash
  # Option A (Red Hat): Label directory for Samba
  sudo chcon -t samba_share_t /mnt/sda1

  # Option B (Red Hat): Allow Samba to share any folder
  sudo setsebool -P samba_export_all_rw 1
  ```

---

### 3.3 Account Lockout (`pam_faillock`)

openSUSE protects against SSH and local login brute-force attacks out of the box using `pam_faillock`.
* If a user enters an incorrect password 3–5 consecutive times, the account is temporarily locked.
* To check or unlock a locked account:

```bash
# Check failed login attempts for user 'boss'
sudo faillock --user boss

# Unlock account 'boss'
sudo faillock --user boss --reset
```

---

### 3.4 Strict Desktop Polkit Elevation

openSUSE configures **Polkit (PolicyKit)** strictly:
* Administrative GUI tools (YaST, partition managers, network config) prompt for the **root user's password**, rather than the logged-in user's personal password.
* Prevents unprivileged users with `sudo` rights from silently altering system configurations without root authentication.

---

### 3.5 Btrfs Snapper System Resilience

openSUSE installs with Btrfs root partitioning and **Snapper** snapshot management enabled by default:
* **Pre/Post Snapshots:** Every time `zypper` installs or updates software, Snapper automatically takes a pre-install and post-install snapshot.
* **Bootable Snapshots:** If an update or configuration change corrupts the system, GRUB displays a **"Bootable Snapshots"** sub-menu.
* **Rollback:** Booting into a snapshot mounts root as **Read-Only**. Running `snapper rollback` converts the clean snapshot into the active system state.

---

## 4. Admin Quick Reference Cheatsheet

| Task | openSUSE Command |
| :--- | :--- |
| **Restart Samba Service** | `sudo systemctl restart smb` *(Note: `smb`, not `smbd`)* |
| **Test Samba Config** | `sudo testparm -s` |
| **Check Firewall Status** | `sudo firewall-cmd --state` |
| **Open Samba in Firewall** | `sudo firewall-cmd --permanent --add-service=samba && sudo firewall-cmd --reload` |
| **List Btrfs Snapshots** | `sudo snapper list` |
| **Rollback System Snapshot** | `sudo snapper rollback` |
| **Unlock Failed Login User** | `sudo faillock --user <username> --reset` |
| **Check System Security Profile** | `cat /etc/sysconfig/security | grep PERMISSION_SECURITY` |
