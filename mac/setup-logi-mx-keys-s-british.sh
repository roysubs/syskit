#!/bin/bash

# --- MX Keys S UK Layout Master Fixer (Final Version) ---
APP_PATH="/Applications/Hammerspoon.app"
HS_DIR="$HOME/.hammerspoon"
INIT_LUA="$HS_DIR/init.lua"

echo "----------------------------------------------------"
echo "LOGITECH MX KEYS S: UK-PC LAYOUT AUTOMATION"
echo "----------------------------------------------------"

# 1. ELEVATE PRIVILEGES FIRST
echo "Step 0: Enter your password while the keyboard is still ON:"
sudo -v 

# 2. CLEAR SYSTEM KEYBOARD CACHE
# This forces macOS to treat the keyboard as 'new' on the next connection
sudo rm -f /Library/Preferences/com.apple.keyboardtype.plist
echo "System keyboard cache cleared."

# 3. IDEMPOTENT HAMMERSPOON INSTALL
if [ -d "$APP_PATH" ]; then
    echo "Hammerspoon is already installed."
else
    echo "Hammerspoon not found. Installing latest version from GitHub..."
    URL=$(curl -s https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest | grep "browser_download_url.*zip" | cut -d '"' -f 4)
    curl -L "$URL" -o hs.zip
    unzip -q hs.zip
    mv Hammerspoon.app /Applications/
    rm hs.zip
    echo "Hammerspoon installed successfully."
fi

# 4. SETUP IDEMPOTENT INIT.LUA
mkdir -p "$HS_DIR"

# Define the block we want to ensure exists in init.lua
LUA_BLOCK="-- [[ MX KEYS S UK SWAP START ]]
local function applyKeyboardFix()
    local script = [[hidutil property --set '{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\": 0x700000035, \"HIDKeyboardModifierMappingDst\": 0x700000064}, {\"HIDKeyboardModifierMappingSrc\": 0x700000064, \"HIDKeyboardModifierMappingDst\": 0x700000035}]}']]
    hs.execute(script)
    hs.alert.show(\"MX Keys S: UK Layout Fixed\", 2)
end

applyKeyboardFix()

hs.hotkey.bind({\"cmd\", \"alt\", \"shift\"}, \"R\", function() hs.reload() end)

local usbWatcher = hs.usb.watcher.new(function(data)
    if (data.productName and (data.productName:find(\"MX Keys S\") or data.productName:find(\"Logitech\"))) then
        if (data.eventType == \"added\") then hs.timer.doAfter(2, applyKeyboardFix) end
    end
end)
usbWatcher:start()
-- [[ MX KEYS S UK SWAP END ]]"

if grep -q "MX KEYS S UK SWAP START" "$INIT_LUA" 2>/dev/null; then
    echo "Hammerspoon config block already exists. Skipping write."
else
    echo "Adding fix logic to $INIT_LUA..."
    echo -e "\n$LUA_BLOCK" >> "$INIT_LUA"
fi

# 5. START / RESTART HAMMERSPOON
if pgrep -x "Hammerspoon" > /dev/null; then
    echo "Restarting Hammerspoon..."
    killall Hammerspoon && sleep 1 && open -a Hammerspoon
else
    echo "Starting Hammerspoon..."
    open -a Hammerspoon
fi

# 6. FINAL GUI INSTRUCTIONS (No Reboot Required)
osascript -e 'display dialog "SUCCESS! Hammerspoon is configured.\n\nFINAL MANUAL STEP:\n1. Go to System Settings > Keyboard > Input Sources > Edit.\n2. Click the tiny [+] in the bottom left corner.\n3. Search for \"British - PC\" and add it.\n4. DELETE any other layouts (British or Dutch).\n\nNOTE: If the keys under Esc and next to Shift are still swapped, press Cmd+Alt+Shift+R to refresh." buttons {"All Done!"} default button "All Done!" with title "MX Keys S Setup"'

echo "Process Complete. Enjoy your proper UK layout!"
