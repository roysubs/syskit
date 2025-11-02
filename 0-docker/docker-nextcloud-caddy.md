# 🧭 Nextcloud Docker Admin Notes

A quick reference for managing and troubleshooting a **Nextcloud instance running inside a Docker container**.

---

## 🧱 1. Architecture Overview

Nextcloud is a **web application** (PHP + web server + database) running in a Docker container.  
Your DuckDNS domain (e.g. `https://xxx.duckdns.org`) points to this container.

- You **don’t SSH into** the container — instead, you **attach or exec** into it.
- The **host machine** (Linux, Raspberry Pi, VPS, etc.) runs Docker and manages the container.

---

## ⚙️ 2. Accessing the Container

Attach to the running container:

    docker exec -it nextcloud bash

> Replace `nextcloud` with your actual container name.

Once inside, you can explore or run commands.

---

## 📦 3. Package Management Inside the Container

Most official Nextcloud images are based on **Debian Slim**.

You can use `apt` inside the container (changes are temporary unless you rebuild your image):

    apt update
    apt install vim less nano -y

> 🧠 Anything installed this way will be **lost** if the container is rebuilt or updated.

To make it permanent, extend the image with your own Dockerfile:

    FROM nextcloud:latest
    RUN apt-get update && apt-get install -y vim less nano && rm -rf /var/lib/apt/lists/*

---

## 🧾 4. Important File Locations

Inside the container:

| Path | Description |
|------|--------------|
| `/var/www/html/config/config.php` | Main Nextcloud configuration file |
| `/var/www/html/data/` | User data directory (unless mapped externally) |
| `/var/www/html/custom_apps/` | Installed custom apps |
| `/var/www/html/themes/` | Custom themes |
| `/var/www/html/version.php` | Nextcloud version info |
| `/usr/src/nextcloud/` | Base application code (read-only) |

If you’ve mapped volumes, you can edit files safely **from the host** — e.g.:

    sudo nano /srv/nextcloud/config/config.php

---

## 🧰 5. Useful Nextcloud `occ` Commands

The `occ` (ownCloud Console) tool is the CLI interface for Nextcloud.  
Run it **as the web user** (www-data):

    sudo -u www-data php occ <command>

Or from inside the container (often no `sudo` needed):

    php occ <command>

### 🧩 Common Commands

| Command | Description |
|----------|--------------|
| `php occ status` | Show current version, maintenance mode, etc. |
| `php occ app:list` | List all apps and their status |
| `php occ app:enable <app>` / `app:disable <app>` | Enable or disable apps |
| `php occ user:list` | List all users |
| `php occ group:list` | List all groups |
| `php occ maintenance:mode --on/--off` | Enable or disable maintenance mode |
| `php occ db:add-missing-indices` | Fix database index issues |
| `php occ db:convert-filecache-bigint` | Normalize file cache columns |
| `php occ files:scan --all` | Rescan all user files (after manual changes) |
| `php occ files:cleanup` | Remove orphaned entries |
| `php occ log:watch` | Stream Nextcloud logs live in terminal |
| `php occ maintenance:repair` | Run automatic repairs |
| `php occ background:status` | Check cron/background job configuration |

---

## 🔐 6. Logging

Logs are found here:

    /var/www/html/data/nextcloud.log

Follow logs in real time:

    tail -f /var/www/html/data/nextcloud.log

---

## 🌐 7. Host vs Container

| Action | Run on Host | Run in Container |
|---------|--------------|-----------------|
| Manage Docker | ✅ | ❌ |
| Edit mounted config files | ✅ | ✅ (host is safer) |
| Run `occ` commands | ⚠️ (via docker exec) | ✅ |
| Restart web server | ❌ | ✅ (`service apache2 restart`) |
| Backup volumes | ✅ | ❌ |

---

## 🧹 8. Group Folders Notes

- Group Folders are managed via the **Group folders app** (in Admin UI).
- When deleted, the folder may still appear for users until:
  - They refresh or log out/in
  - Background jobs run
  - Orphaned mounts are cleaned up via `php occ files:scan --all`

---

## 🧠 9. Quick Troubleshooting

| Symptom | Likely Cause | Fix |
|----------|---------------|-----|
| Folder still visible after deletion | Cached mount | Refresh, relog, run `files:scan` |
| `apt` doesn’t work | Alpine-based image | Use `apk add` instead |
| “Permission denied” editing files | Wrong user | Use `sudo -u www-data` or edit via host |
| Can’t SSH to DuckDNS host | SSH not exposed | SSH to host directly, not container |
| Updates break customizations | Ephemeral container | Move configs to mounted volumes or custom Docker image |

---

## 📚 10. References

- [Nextcloud Docker Hub Page](https://hub.docker.com/_/nextcloud)
- [Nextcloud Admin Manual](https://docs.nextcloud.com/server/latest/admin_manual/)
- [Nextcloud OCC Command Reference](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html)

---

*Maintainer: [Your Name]*  
*Last updated: {{date}}*

