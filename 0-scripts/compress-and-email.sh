#!/bin/bash
# Author: Roy Wiseman 2025-03

# Purpose: Compress a folder, display details, and then email it.
# See 0-new-system/new6-email-with-gmail-relay.sh to auto-install gmail with relay on console. 

# $1 = path to the folder to be compressed and emailed.
# $2 = email to send the file to.
# NOTE: Password of 1234 will be used to circumvent email virus scans.

# The traditional 'mail' app does not support attachments easily so we need mailx or mutt.
# We use mutt as it has better MIME handling for attachments than mailx.
# Show current mail application
#    ls -l $(which mail) $(which mailx)
#    mail --version
#    sudo apt install mailutils   # includes mailx, which supports attachments
#    sudo apt install mutt        # supports attachments with -a
#    sudo apt install bsd-mailx   # For Debian/Ubuntu-based systems
#    sudo update-alternatives --config mailx
# Following is a mutt example:
#    echo "Body of email..." | mutt -s "Subject here" -a "$attachmentpath" -- "user@gmail.com"
# In mutt, the -- is a delimiter to signify the end of command-line options and the beginning of positional arguments (such as email recipients).
# If you omit -- in most cases, the command still works unless the email address is unusual (e.g., -test@example.com).
# Using -- is a good practice with mutt to avoid potential issues.
# Other options are sendmail, ssmtp, but require a lot more effort to implement (see end of this script for more details).

# Validate inputs
if [[ -z "$1" || -z "$2" ]]; then
  echo "Purpose: Compress a folder, display details, and then email it.
  echo "Usage: ${0##*/}  <folderpath>  <email>"
  exit 1
fi

FOLDER_PATH="$1"
EMAIL="$2"

# Validate folder
if [[ ! -d "$FOLDER_PATH" ]]; then
  echo "Error: '$FOLDER_PATH' is not a valid folder."
  exit 1
fi

# Validate email
if ! [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Error: '$EMAIL' is not a valid email address."
  exit 1
fi

# Install required tools
echo "Ensuring required tools are installed..."
if ! command -v zip &>/dev/null; then
  echo "Installing zip..."
  sudo apt update && sudo apt install -y zip
fi
if ! command -v 7z &>/dev/null; then
  echo "Installing 7zip..."
  sudo apt update && sudo apt install -y 7zip
fi
if ! command -v expect &>/dev/null; then
  echo "Installing expect for email..."
  sudo apt update && sudo apt install -y expect
fi
if ! command -v mutt &>/dev/null; then
  echo "Installing mutt for email..."
  sudo apt update && sudo apt install -y mailutils mutt
fi

# Compress the folder
ZIP_FILE="${FOLDER_PATH%/}.7z"
echo "Compressing folder '$FOLDER_PATH' to '$ZIP_FILE'..."
# zip -r "$ZIP_FILE" "$FOLDER_PATH" -9
7z a -p1234 "$ZIP_FILE" "$FOLDER_PATH"
if [[ $? -ne 0 ]]; then
  echo "Error: Failed to compress the folder."
  exit 1
fi
# set timeout -1
# set password "your_password_here"
# 
# spawn zip -e secure_archive.zip script1.sh script2.sh
# expect "Enter password:" { send "$password\r" }
# expect "Verify password:" { send "$password\r" }
# expect eof

# Display file details
FILE_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
NUM_FILES=$(7z l "$ZIP_FILE" | grep -oP '\d+ files')
# NUM_FILES=$(zipinfo -t "$ZIP_FILE" | grep -oP '\d+ files')  # Doesn't work with .7z files

echo "Compression complete."
echo "File: $ZIP_FILE"
echo "Size: $FILE_SIZE"
echo "Number of files: $NUM_FILES"

# Email the file
echo "Sending '$ZIP_FILE' to '$EMAIL'..."
MAIL_OUTPUT=$(echo "Attached is the compressed folder $FOLDER_PATH." | mutt -s "Compressed Folder: '$FOLDER_PATH'" -a "$ZIP_FILE" -- "$EMAIL" 2>&1)
echo "Check the Postfix logs:   sudo tail -f /var/log/mail.log"
echo "A successful delivery looks like:   status=sent (250 2.0.0 OK ...)"

# Check mail status
if [[ $? -eq 0 ]]; then
  echo "Email sent successfully to $EMAIL."
else
  echo "Error: Failed to send email."
  echo "Details: $MAIL_OUTPUT"
  exit 1
fi

echo "Script completed successfully. 7zip password used was '1234'."

# sendmail requires a bit more effort to create the email body with attachment headers manually:
#   sudo apt install sendmail
#   (
#     echo "Subject: Compressed Folder: $FOLDER_PATH"
#     echo "To: $EMAIL"
#     echo "MIME-Version: 1.0"
#     echo "Content-Type: multipart/mixed; boundary=\"boundary\""
#     echo
#     echo "--boundary"
#     echo "Content-Type: text/plain; charset=utf-8"
#     echo
#     echo "Attached is the compressed folder $FOLDER_PATH."
#     echo
#     echo "--boundary"
#     echo "Content-Type: application/zip; name=\"$(basename $ZIP_FILE)\""
#     echo "Content-Disposition: attachment; filename=\"$(basename $ZIP_FILE)\""
#     echo "Content-Transfer-Encoding: base64"
#     echo
#     base64 "$ZIP_FILE"
#     echo "--boundary--"
#   ) | sendmail "$EMAIL"
# ssmtp can send the attachment using uuencode:
#    sudo apt install ssmtp sharutils
#   (
#     echo "To: $EMAIL"
#     echo "Subject: Compressed Folder: $FOLDER_PATH"
#     echo "MIME-Version: 1.0"
#     echo "Content-Type: multipart/mixed; boundary=\"boundary\""
#     echo
#     echo "--boundary"
#     echo "Content-Type: text/plain; charset=utf-8"
#     echo
#     echo "Attached is the compressed folder $FOLDER_PATH."
#     echo
#     echo "--boundary"
#     uuencode "$ZIP_FILE" "$(basename $ZIP_FILE)"
#   ) | ssmtp "$EMAIL"

