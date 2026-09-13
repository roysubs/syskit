#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Resets qBittorrent's WebUI password to a known value by writing a PBKDF2
# hash directly into the config file. Works around a known bug in
# binhex/arch-qbittorrentvpn where the auto-generated temp password is
# unreliable to retrieve (github.com/binhex/arch-qbittorrentvpn/issues/213).
#
# v2: the whole config edit is done in Python (not sed) because GNU sed's
# 'a' (append) command silently eats backslashes in its argument text,
# which was corrupting "WebUI\Password_PBKDF2" into "WebUIPassword_PBKDF2"
# in v1 -- an unrecognized key that qBittorrent just ignored.

set -e

CONTAINER_NAME="qbittorrent"
CONFIG_FILE="$HOME/.config/media-stack/qbittorrent/qBittorrent/config/qBittorrent.conf"
NEW_PASSWORD="${1:-adminadmin}"   # pass a password as arg1, or defaults to adminadmin

echo "--- Resetting qBittorrent Password ---"

echo "1. Stopping container..."
docker compose stop "$CONTAINER_NAME"

echo "2. Verifying config file exists..."
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found at: $CONFIG_FILE"
    exit 1
fi

echo "3. Rewriting WebUI password in config (Python, no sed)..."
python3 << PYEOF
import base64, hashlib, os

config_file = "$CONFIG_FILE"
password = """$NEW_PASSWORD"""

salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), salt, 100000, dklen=64)
salt_b64 = base64.b64encode(salt).decode('utf-8')
hash_b64 = base64.b64encode(dk).decode('utf-8')
hash_line = 'WebUI\\\\Password_PBKDF2="@ByteArray(' + salt_b64 + ':' + hash_b64 + ')"'

with open(config_file, 'r') as f:
    lines = f.readlines()

# Strip any existing password lines (legacy Password_ha1 and PBKDF2 formats)
lines = [l for l in lines if not l.lstrip().startswith('WebUI\\\\Password')]

out = []
inserted = False
for line in lines:
    out.append(line)
    if line.strip() == '[Preferences]' and not inserted:
        out.append(hash_line + '\n')
        inserted = True

if not inserted:
    out.append('\n[Preferences]\n')
    out.append(hash_line + '\n')

with open(config_file, 'w') as f:
    f.writelines(out)

# Sanity check: read it back and confirm the key name survived intact
with open(config_file, 'r') as f:
    content = f.read()
if 'WebUI\\\\Password_PBKDF2=' not in content:
    print("ERROR: verification failed -- key not found after write")
    exit(1)
print("Verified: WebUI\\\\Password_PBKDF2 written correctly.")
PYEOF

if [ $? -ne 0 ]; then
    echo "❌ Failed to write password to config. Aborting."
    exit 1
fi

echo "4. Double-checking the exact bytes on disk..."
grep "Password_PBKDF2" "$CONFIG_FILE"

echo "5. Starting container..."
docker compose start "$CONTAINER_NAME"

echo "6. Waiting 5 seconds for qBittorrent to fully come up..."
sleep 5

echo "7. Confirming config wasn't overwritten after start..."
grep -q "Password_PBKDF2" "$CONFIG_FILE" && echo "✅ Still present after startup." || echo "⚠️  WARNING: line disappeared after startup -- something is resetting the config."

echo -e "\n✅ Password set."
echo "----------------------------------"
echo "👉 Go to http://localhost:8080"
echo "   Username: admin"
echo "   Password: $NEW_PASSWORD"
echo "----------------------------------"
