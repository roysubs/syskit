#!/bin/bash
# Author: Roy Wiseman 2025-04

if ! command -v glow >/dev/null 2>&1; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install glow
fi

cat <<'EOF' | mdcat | less -R

...
###
### Put Markdown text here
###
...

EOF

