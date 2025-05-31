#!/bin/bash
# Author: Roy Wiseman 2025-02

# dk-completion-setup.sh
# Sets up bash completion for the 'dk' script in system completions directory:
#    /usr/share/bash-completion/completions/ (requires sudo

# --- Configuration ---
SYSTEM_COMPLETION_DIR="/usr/share/bash-completion/completions"
SYSTEM_COMPLETION_FILE="$SYSTEM_COMPLETION_DIR/dk"

# --- Bash Completion Script Content ---
# This is the content that will be written to the completion file.
# It defines the completion function and associates it with the 'dk' command.
# This content will be placed in the system completions directory and sourced
# by the main bash_completion script.
read -r -d '' DK_COMPLETION_SCRIPT << 'EOF'
# Bash completion for the 'dk' script

_dk_completion() {
    local cur prev commands_needing_container commands_needing_image
    # Get the current word being completed
    cur="${COMP_WORDS[COMP_CWORD]}"
    # Get the previous word (the dk subcommand)
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # List of dk subcommands that expect a container name next
    commands_needing_container="start stop restart rm logs look run it x ex exec"

    # List of dk subcommands that expect an image name next
    commands_needing_image="rmi" # Add "im" if you want to complete image names after "dk im" (less common)

    # Check if the previous word is one of the commands needing a container name
    if [[ " ${commands_needing_container} " =~ " ${prev} " ]]; then
        # If yes, generate completions from the list of container names
        # Use compgen -W to generate matches from a wordlist
        # Use -W "$(command)" to use the output of a command as the wordlist
        # Redirect stderr to /dev/null to suppress errors if docker is not running
        local container_names=$(docker ps -a --format '{{.Names}}' 2>/dev/null)

        # Use compgen -W to handle names with spaces correctly when quoted
        COMPREPLY=( $(compgen -W "${container_names}" -- "$cur") )

    # Check if the previous word is one of the commands needing an image name
    elif [[ " ${commands_needing_image} " =~ " ${prev} " ]]; then
         # If yes, generate completions from the list of image names
         # Use docker images --format to get repository:tag or image ID
         # Using --format '{{.Repository}}:{{.Tag}}' might give more human-readable names
         # Use '{{.ID}}' if you prefer completing by ID
         local image_names=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>') # Exclude <none> images

         # Use compgen -W to handle names with spaces correctly when quoted
         COMPREPLY=( $(compgen -W "${image_names}" -- "$cur") )

    fi
}

# Associate the _dk_completion function with the 'dk' command
# -F specifies that a function should be used for completion
complete -F _dk_completion dk
EOF

# --- Setup Logic ---

echo "Checking for system bash-completion directory..."

# Check if the system completion directory exists
if [ -d "$SYSTEM_COMPLETION_DIR" ]; then
    echo "System bash-completion directory found at $SYSTEM_COMPLETION_DIR."

    echo "Attempting to write 'dk' completion script to $SYSTEM_COMPLETION_FILE..."
    echo "You may be prompted for your sudo password."

    # Write the completion script content to the system file using sudo, forcing overwrite
    echo "$DK_COMPLETION_SCRIPT" | sudo tee "$SYSTEM_COMPLETION_FILE" > /dev/null

    # Check if the sudo command was successful
    if [ $? -eq 0 ]; then
        echo "Successfully wrote 'dk' completion script to $SYSTEM_COMPLETION_FILE."

        # Ensure the file permissions are correct (readable by others)
        sudo chmod a+r "$SYSTEM_COMPLETION_FILE"
        echo "Set a+r permissions on $SYSTEM_COMPLETION_FILE."

        echo ""
        echo "Setup complete!"
        echo "To activate the 'dk' bash completion, you need to reload your shell configuration."
        echo "You can do this by:"
        echo "1. Logging out and logging back in (most reliable), OR"
        echo "2. Opening a new terminal session, OR"
        echo "3. Sourcing the main bash completion script manually (may vary by system):"
        echo "    source /usr/share/bash-completion/bash_completion"
        echo ""
        echo "After reloading, you should be able to type:"
        echo "   'dk start <Tab>' (for container-name completion; also for the dk commands: stop, rm, logs, info, it)"
        echo "   'dk rmi <Tab>'   (for image name completion)"

    else
        echo "Error: Failed to write to $SYSTEM_COMPLETION_FILE using sudo." >&2
        echo "Please check if you have sufficient permissions or if the path is correct." >&2
        exit 1 # Indicate failure
    fi

else
    echo "System bash-completion directory ($SYSTEM_COMPLETION_DIR) not found." >&2
    echo "Bash completion for 'dk' cannot be set up automatically in the system location." >&2
    echo "Please ensure bash-completion is correctly installed on your system." >&2
    exit 1 # Indicate failure
fi

