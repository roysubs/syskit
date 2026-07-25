# SFTPGo Automated Configuration Injection

It is possible to automate the configuration of **SFTPGo** users, virtual folders, and granular permissions using a robust mechanism provided by SFTPGo itself: the `loaddata` command combined with its internal hashing tool.

Instead of manually tinkering with database tables, the most reliable way to "inject" settings is documented below:

### 1. Generate Hashes
Use SFTPGo's internal hashing tool to create secure hashes that the application accepts for user authentication.

```bash
# Example command to generate a hash for a password
sftpgo hash --password "your_password_here"
```

### 2. Create a JSON Template
Generate a temporary `sftpgo_config.json` that defines the structure and permissions for the users and folders you want to share.

- **Users**: Define the username, home directory, shell environment, and any associated metadata.
- **Virtual Folders**: Map external system paths (e.g., `/mnt/storage`, `/home/boss/documents`) to internal SFTP paths.
- **Permissions**: Control access using SFTPGo's granular JSON permission structure.
    - Example: `{"/": ["list", "download"], "/uploads": ["*"]}`

### 3. Inject via `loaddata`
Apply the configuration instantly using the SFTPGo CLI. This typically does not require a service restart.

```bash
# Command to inject the configuration into the active SFTPGo instance
sftpgo loaddata --input /tmp/config.json
```

### Automation Use Cases
This methodology allows for several advanced automation scenarios in the `remote-access-opensuse.sh` environment:

*   **Auto-Share Home**: Automatically create an SFTPGo account for the current system user that points directly to their real home directory.
*   **Media/Storage Mapping**: Scripted mounting of various system paths (like `/photos` or `/backups`) as virtual folders accessible via the SFTPGo Web UI.
*   **Permission Presets**: Pre-configure specific access patterns like "Read-Only (Shared)", "Upload-Only (Drop-box)", or "Full-Access (Admin)".

---
*Documented for Syskit Remote Access Builder V19*
