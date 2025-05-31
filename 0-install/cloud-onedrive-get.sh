#!/bin/bash
# Author: Roy Wiseman 2025-05

# Ensure email argument is provided
if [[ -z "$1" ]]; then
    echo "Usage: $0 your-email@hotmail.com"
    exit 1
fi

EMAIL="$1"

# Install dependencies
echo "Installing dependencies..."
sudo apt update
sudo apt install -y onedrive

# Skip synchronization and logout at this stage
echo "OneDrive is installed. Let's configure it for your account: $EMAIL."
echo "Please follow the authentication process in your browser."
echo "The following steps need to be completed manually:"
echo
echo "1. Run the following command to start the authentication process:"
echo "   onedrive"
echo
echo "2. This will output a URL that you need to copy and paste into your browser."
echo "   Log in with your Microsoft account and authorize OneDrive."
echo
echo "3. After logging in, you will receive a verification code."
echo "   Copy and paste this verification code back into your terminal."
echo
echo "Once authentication is complete, press Enter below to continue."
read -p "Press Enter once authentication is complete."

# Ensure the config folder exists
mkdir -p ~/.config/onedrive


# Provide instructions for enabling OneDrive to sync automatically
echo "Configuring OneDrive service for automatic syncing..."
echo "OneDrive will sync automatically on login once you have completed the authentication."
echo "Enabling the onedrive service (this creates the necessary symlink)"
echo
systemctl --user enable onedrive
# /home/boss/.config/systemd/user/default.target.wants/onedrive.service → /usr/lib/systemd/user/onedrive.service.
systemctl --user status onedrive
echo
echo "To start the OneDrive service manually:"
echo "   systemctl --user start onedrive"
echo
echo "To enable the service to start automatically on login:"
echo "   systemctl --user enable onedrive"
echo
echo "To stop the OneDrive service:"
echo "   systemctl --user stop onedrive"
echo
echo "To upgrade OneDrive to the latest version, use the following commands:"
echo "   sudo apt update"
echo "   sudo apt upgrade onedrive"
echo
echo "Once you're ready to start syncing, run:"
echo "   onedrive --synchronize"
echo
echo "Setup is complete, but syncing is paused until authentication is finished."
echo "Make sure to start the OneDrive service when you're ready to sync."

It looks like there are two separate issues here:

Slow sync speed

The OneDrive CLI sync is much slower than the Windows version, which is a common complaint.
Each file is downloaded individually, unlike Windows, which may batch transfers more efficiently.
Possible fixes:
Increase concurrency with:
bash
Copy
Edit
onedrive --synchronize --verbose --monitor --upload-only --resync
This enables more detailed logging and re-establishes the connection.
Try --single-directory if only certain folders are important:
bash
Copy
Edit
onedrive --synchronize --single-directory "Desktop/Screenshots"
Run in monitor mode:
bash
Copy
Edit
onedrive --monitor --verbose
This may optimize syncing for larger sets of files.
File download size/hash mismatch errors

These errors suggest either network instability or an issue with OneDrive’s integrity checks.
You can try:
bash
Copy
Edit
onedrive --synchronize --disable-download-validation
But this is risky as it disables integrity checks.
Next Steps
Try increasing concurrency
bash
Copy
Edit
onedrive --synchronize --verbose --monitor --upload-only --resync
Check CPU and network load
Run:
bash
Copy
Edit
top
and
bash
Copy
Edit
iftop
to see if OneDrive is being throttled.
Test a smaller sync batch
bash
Copy
Edit
onedrive --synchronize --single-directory "Desktop/Screenshots"
If it’s still slow, I can help you debug further. Let me know if you get any new error messages!







You said:
is sync trying to get all files, or just the stubs?
ChatGPT said:
The OneDrive CLI (onedrive --synchronize) downloads full files, not just stubs. Unlike the Windows OneDrive client, which can use "Files On-Demand" (only downloading files when accessed), the Linux CLI always pulls entire files unless specifically excluded via config.

How to Check What It's Syncing
Run:

bash
Copy
Edit
onedrive --display-config
Look for:

sync_dir → This is where files are being saved.
skip_file → File types that are skipped.
skip_dir → Folders that are ignored.
To see what it's trying to sync without actually downloading:

bash
Copy
Edit
onedrive --synchronize --dry-run
Reducing Download Scope
If you only want certain files or folders, try:

bash
Copy
Edit
onedrive --synchronize --single-directory "Documents"
If you need a Files On-Demand-like behavior, you’d have to manually exclude large files from syncing using a .config/onedrive/sync_list file.

Let me know if you want to tweak what’s being downloaded!
