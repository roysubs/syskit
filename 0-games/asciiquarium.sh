#!/bin/bash
# Author: Roy Wiseman 2025-02

# Install the Term::Animation
sudo apt install libcurses-perl

#!/bin/bash

# Define variables
URL="https://cpan.metacpan.org/authors/id/K/KB/KBAUCOM/Term-Animation-2.5.tar.gz"
FILENAME=$(basename "$URL")
TMP_DIR="/tmp"
TARGET_DIR="/opt/Term-Animation-2.5"

# Check if the file already exists in /tmp
if [[ -f "$TMP_DIR/$FILENAME" ]]; then
    echo "File already exists: $TMP_DIR/$FILENAME"
else
    wget -P "$TMP_DIR" "$URL"
    if [[ $? -ne 0 ]]; then echo "Failed to download file: $URL"; exit 1; fi
fi

# Check if the target directory already exists
if [[ -d "$TARGET_DIR" ]]; then
    echo "Target directory already exists: $TARGET_DIR"
else
    sudo mkdir -p "$TARGET_DIR"
    sudo tar -xzf "$TMP_DIR/$FILENAME" -C "$TARGET_DIR" --strip-components=1
    if [[ $? -ne 0 ]]; then echo "Failed to extract file: $TMP_DIR/$FILENAME"; exit 1; fi
fi

echo "File downloaded and extracted to $TARGET_DIR"

cd "$TARGET_DIR"
perl Makefile.PL
make 
sudo make install

# Install ASCIIaquarium
cd /tmp
wget http://www.robobunny.com/projects/asciiquarium/asciiquarium.tar.gz
tar -zxvf asciiquarium.tar.gz
cd asciiquarium_1.1/
sudo cp asciiquarium /usr/local/bin
sudo chmod 0755 /usr/local/bin/asciiquarium

echo
echo "Binary has been copied to /usr/local/bin, run with:"
echo "asciiquarium"
echo
