#!/bin/bash
# Author: Roy Wiseman 2025-02
#
# Purpose: Script to toggle tmux advanced features, manage basic TPM setup,
# automatically attempt to install TPM plugins, and inject custom git status
# into the Dracula theme script.
#
# WARNING: This script directly modifies a Dracula theme file. This is inherently risky
# and changes may be overwritten by theme updates. Proceed with caution.

# ===== CONFIGURATION - TMUX ADVANCED SETTINGS =====

SETTING_NAME="advanced tmux features"
CONFIG_FILE="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"
TPM_REPO_URL="https://github.com/tmux-plugins/tpm"

# For Dracula script injection
DRACULA_SCRIPT_TARGET_PATH="$HOME/.tmux/plugins/tmux/scripts/dracula.sh" # Standard path for dracula/tmux plugin script
DRACULA_SCRIPT_ANCHOR_LINE="tmux set-option -g status-right \"\""
GIT_POWERLINE_SCRIPT_PATH="$HOME/syskit/0-scripts/git-powerline-tmux.sh"
LINE_TO_INJECT_IN_DRACULA="tmux set-option -ag status-right \"#[fg=cyan]#(${GIT_POWERLINE_SCRIPT_PATH}) #[default]\""


START_MARKER="# --- BEGIN TOGGLE-TMUX-ADVANCED SETTINGS ---"
END_MARKER="# --- END TOGGLE-TMUX-ADVANCED SETTINGS ---"

DESC_STYLE_1="# Advanced Tmux options are ENABLED:
# - C-b g (unusued binding) set to toggle mouse mode
# - Vim keymaps for pane switching (PREFIX h,j,k,l)
# - Dracula plugin ENABLED via TPM (auto-install attempted)
# - Dracula theme customized (plugins: cpu, ram, time)
# - Detailed Git status injected into Dracula theme script
# - Time format: Day MM/DD HH:MM (24-hour)
# - Session name and vampire icon on left status"

DESC_STYLE_2="# Advanced Tmux options are DISABLED:
# - Leader key: Ctrl+b (default)
# - Pane switching keymaps: Default (custom PREFIX h,j,k,l removed)
# - Dracula plugin DISABLED via TPM (commented out)
# - TPM execution line REMOVED (TPM will not run)
# - Dracula theme customizations: Removed
# - Custom Git status injection in Dracula theme script: REMOVED"

STYLE_1_NAME="Advanced Tmux (Injected Git Status)"
STYLE_1_SETTINGS="${DESC_STYLE_1}

# Leader key: Ctrl+b (default)
# set -g prefix C-b
# bind-key C-b send-prefix

# Custom set -g trigger (g is often free after prefix) for mouse toggle
bind g set -g mouse \; display-message \"Mouse mode: #{?mouse,on,off}\"

# Vim keymaps for pane switching (activated by PREFIX h,j,k,l)
bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R

# Dracula Plugin and Theme Configurations
set -g @plugin 'dracula/tmux' # Enable Dracula plugin for TPM

# List of plugins/segments for Dracula to display
set -g @dracula-plugins \"cpu-usage ram-usage time\"

# Time Format: Day MM/DD HH:MM (24-hour)
set -g @dracula-time-format \"%a %m/%d %H:%M\"

# Configure left status: show session module with custom icon (session name + vampire)
set -g @dracula-show-left-icon \"[#S] 🧛\"
set -g @dracula-session-icon \"[#S] 🧛\"

# Adjust status bar lengths
set -g status-left-length 40
set -g status-right-length 90 # Increased for detailed git + other modules

set -g @dracula-show-fahrenheit false
set -g @dracula-show-location false
"

STYLE_2_NAME="Basic Tmux"
STYLE_2_SETTINGS="${DESC_STYLE_2}

# Revert to default leader key (Ctrl+b only)
# set -g prefix C-b # Default
# bind-key C-b send-prefix # Default

# Unbind custom keymaps
unbind-key g # Changed from m to g
unbind-key h; unbind-key j; unbind-key k; unbind-key l

# Dracula Plugin and Theme Configurations (Disabled)
# set -g @plugin 'dracula/tmux'
"

APPLY_COMMAND="tmux source-file \"\${CONFIG_FILE}\""

# ===== END CONFIGURATION =====

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
TIMESTAMP="" 

# ... (ensure_tpm_installed, attempt_install_tpm_plugins, manage_tpm_run_line functions remain the same as last good version) ...
# I will paste them here for completeness, assuming they are from the last working version you had success with the toggle script.

ensure_tpm_installed() {
    echo -e "${BLUE}Checking TPM installation...${NC}"
    local tpm_was_just_installed=false
    local tpm_run_line_std="run '$HOME/.tmux/plugins/tpm/tpm'" # Standard TPM run line
    if [ -d "$TPM_DIR" ]; then
        echo -e "${GREEN}TPM found at $TPM_DIR.${NC}"
    else
        echo -e "${BLUE}TPM not found. Attempting to install TPM...${NC}"
        if ! command -v git &>/dev/null; then echo -e "${RED}Error: git command not found. Cannot clone TPM.${NC}"; return 1; fi
        mkdir -p "$(dirname "$TPM_DIR")" 2>/dev/null
        if git clone --depth 1 "$TPM_REPO_URL" "$TPM_DIR"; then
            echo -e "${GREEN}TPM cloned successfully to $TPM_DIR.${NC}"
            tpm_was_just_installed=true
        else
            echo -e "${RED}Error: Failed to clone TPM from $TPM_REPO_URL.${NC}"
            return 1
        fi
    fi
    if [ "$tpm_was_just_installed" = true ] && [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}No existing $CONFIG_FILE found. Creating a minimal one for TPM...${NC}"
        {
            echo "set -g @plugin 'tmux-plugins/tpm' # TPM itself";
            echo "set -g @plugin 'tmux-plugins/tmux-sensible' # Recommended base settings";
            echo ""; 
            echo "$tpm_run_line_std # Initialize TMUX plugin manager (MUST BE LAST LINE!)";
        } > "$CONFIG_FILE"
        echo -e "${GREEN}Minimal $CONFIG_FILE created with TPM setup.${NC}"
        echo -e "${YELLOW}IMPORTANT: After tmux starts, press 'Prefix + I' (Shift+i) to fetch these initial plugins.${NC}"
    fi
    return 0
}

attempt_install_tpm_plugins() {
    echo -e "${BLUE}Attempting to automatically install/update TPM plugins...${NC}"
    local tpm_install_script_path="$TPM_DIR/bin/install_plugins"

    if [ ! -f "$tpm_install_script_path" ]; then
        echo -e "${RED}TPM install script not found at $tpm_install_script_path.${NC}"
        echo -e "${YELLOW}This usually means TPM itself is not correctly installed at $TPM_DIR.${NC}"
        echo -e "${YELLOW}Automatic plugin installation skipped. You may need to run 'Prefix + I' manually in tmux.${NC}"
        return 1
    fi

    echo -e "${BLUE}Running TPM plugin installer ($tpm_install_script_path)...${NC}"
    if bash "$tpm_install_script_path"; then 
        echo -e "${GREEN}TPM plugins installation/update process completed by script.${NC}"
        echo -e "${YELLOW}Review output above. Some plugins might require manual steps or tmux restart.${NC}"
        return 0
    else
        echo -e "${RED}Failed to execute TPM install script automatically ($tpm_install_script_path).${NC}"
        echo -e "${YELLOW}Please try running 'Prefix + I' manually inside tmux to install plugins.${NC}"
        return 1 
    fi
}

manage_tpm_run_line() {
    local action="$1" 
    local tpm_run_line_to_add="run '$HOME/.tmux/plugins/tpm/tpm'"
    local tpm_run_patterns=("run '$HOME/.tmux/plugins/tpm/tpm'" "run '~/.tmux/plugins/tpm/tpm'")

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: $CONFIG_FILE not found during TPM run line management.${NC}"
        return 1
    fi

    local temp_config_file; temp_config_file=$(mktemp) || { echo -e "${RED}mktemp failed for config processing.${NC}"; return 1; }
    current_content=$(cat "$CONFIG_FILE")
    filtered_content="$current_content"
    for pattern in "${tpm_run_patterns[@]}"; do
        filtered_content=$(printf '%s\n' "$filtered_content" | grep -vF "$pattern")
    done
    printf '%s\n' "$filtered_content" | awk 'NF {p=1} p' > "$temp_config_file"

    if [ "$action" = "enable" ]; then
        echo -e "${BLUE}Ensuring TPM run line is present and at the end of $CONFIG_FILE...${NC}"
        if [ -s "$temp_config_file" ] && [ "$(tail -c1 "$temp_config_file" | wc -l)" -eq 0 ]; then
            echo "" >> "$temp_config_file"
        fi
        echo "$tpm_run_line_to_add # Initialize TMUX plugin manager (MUST BE LAST LINE!)" >> "$temp_config_file"
    elif [ "$action" = "disable" ]; then
        echo -e "${BLUE}Removing TPM run line from $CONFIG_FILE...${NC}"
    else
        echo -e "${RED}Invalid action '$action' for manage_tpm_run_line.${NC}"; rm "$temp_config_file"; return 1;
    fi

    if mv "$temp_config_file" "$CONFIG_FILE"; then return 0; else
        echo -e "${RED}Error writing changes to $CONFIG_FILE during TPM run line management.${NC}"; rm "$temp_config_file" 2>/dev/null; return 1;
    fi
}

manage_dracula_script_injection() {
    local action="$1" 
    echo -e "${BLUE}Managing Dracula script injection ($action)...${NC}"

    if [ ! -f "$DRACULA_SCRIPT_TARGET_PATH" ]; then
        echo -e "${RED}Dracula script target not found: $DRACULA_SCRIPT_TARGET_PATH${NC}"
        echo -e "${YELLOW}Cannot inject/remove git status line. Please verify Dracula plugin installation and paths.${NC}"
        echo -e "${YELLOW}If you just enabled Advanced Mode, plugins might still be installing or 'Prefix + I' may be needed.${NC}"
        [ "$action" = "enable" ] && return 1 || return 0
    fi

    # Ensure dracula.sh is executable if we are about to modify or use it for "enable"
    # For "disable", we just want to clean it, so exec bit isn't strictly needed for that action itself.
    if [ ! -x "$DRACULA_SCRIPT_TARGET_PATH" ] && [ "$action" = "enable" ]; then
        echo -e "${YELLOW}Warning: $DRACULA_SCRIPT_TARGET_PATH is not executable. Attempting to set +x.${NC}"
        if ! chmod +x "$DRACULA_SCRIPT_TARGET_PATH"; then
             echo -e "${RED}Failed to make $DRACULA_SCRIPT_TARGET_PATH executable. Injection might work, but theme might not run.${NC}"
        fi
    fi

    local dracula_backup_file="${DRACULA_SCRIPT_TARGET_PATH}.bak.inj.${TIMESTAMP}"
    if ! cp "$DRACULA_SCRIPT_TARGET_PATH" "$dracula_backup_file"; then
        echo -e "${RED}Failed to backup $DRACULA_SCRIPT_TARGET_PATH. Aborting its modification.${NC}"; return 1;
    fi
    echo -e "${BLUE}Backup of $DRACULA_SCRIPT_TARGET_PATH created at $dracula_backup_file${NC}"

    local temp_script_content; temp_script_content=$(mktemp) || { echo -e "${RED}Mktemp failed (Dracula inject).${NC}"; return 1; }
    grep -vF "$LINE_TO_INJECT_IN_DRACULA" "$DRACULA_SCRIPT_TARGET_PATH" > "$temp_script_content"

    local injection_performed_or_cleaned=false
    local anchor_found_for_injection=false

    if [ "$action" = "enable" ]; then
        echo -e "${BLUE}Attempting to inject git status line into $DRACULA_SCRIPT_TARGET_PATH...${NC}"
        local temp_script_injected; temp_script_injected=$(mktemp) || { echo -e "${RED}Mktemp failed (Dracula inject stage 2).${NC}"; rm "$temp_script_content"; return 1; }

        awk -v anchor_val="$DRACULA_SCRIPT_ANCHOR_LINE" -v inject_val="$LINE_TO_INJECT_IN_DRACULA" '
            {
                line_to_print = $0; sub(/\r$/, "", line_to_print);
                current_line_for_comparison = $0;
                sub(/\r$/, "", current_line_for_comparison); 
                gsub(/^[ \t\xA0]+|[ \t\xA0]+$/, "", current_line_for_comparison);
                print line_to_print; 
                if (current_line_for_comparison == anchor_val) {
                    print inject_val;
                    found_anchor=1;
                }
            }
            END { if (found_anchor==1) exit 0; else exit 1 }
        ' "$temp_script_content" > "$temp_script_injected"
        
        if [ $? -eq 0 ]; then 
            if ! cmp -s "$temp_script_content" "$temp_script_injected"; then 
                 mv "$temp_script_injected" "$temp_script_content" 
                 injection_performed_or_cleaned=true
            fi
            anchor_found_for_injection=true
            echo -e "${GREEN}Anchor found. Git status line injection command processed.${NC}"
        else
            echo -e "${RED}Anchor line \"$DRACULA_SCRIPT_ANCHOR_LINE\" not found in $DRACULA_SCRIPT_TARGET_PATH (after attempting to clean lines).${NC}"
            echo -e "${YELLOW}Git status line NOT injected. The script remains cleaned of previous injections only.${NC}"
        fi
        rm "$temp_script_injected" 2>/dev/null 
    else 
        if ! cmp -s "$DRACULA_SCRIPT_TARGET_PATH" "$temp_script_content"; then
            injection_performed_or_cleaned=true
        fi
    fi

    if [ "$injection_performed_or_cleaned" = true ]; then
        if mv "$temp_script_content" "$DRACULA_SCRIPT_TARGET_PATH"; then
            echo -e "${GREEN}Successfully modified $DRACULA_SCRIPT_TARGET_PATH for action '$action'.${NC}"
            # ***** FIX: Ensure dracula.sh is executable after modification *****
            if ! chmod +x "$DRACULA_SCRIPT_TARGET_PATH"; then
                echo -e "${RED}Warning: Failed to ensure $DRACULA_SCRIPT_TARGET_PATH is executable after modification! Theme may not run.${NC}"
            fi
            # ***** END FIX *****
            if [ "$action" = "enable" ] && [ "$anchor_found_for_injection" = false ]; then
                 echo -e "${YELLOW}Warning: Anchor for git status injection not found. Line was not injected, only cleaned.${NC}"
            fi
        else
            echo -e "${RED}Error: Failed to write changes to $DRACULA_SCRIPT_TARGET_PATH.${NC}"
            echo -e "${RED}Attempting to restore from backup: $dracula_backup_file ...${NC}"
            if cp "$dracula_backup_file" "$DRACULA_SCRIPT_TARGET_PATH"; then echo -e "${GREEN}Restored $DRACULA_SCRIPT_TARGET_PATH from backup.${NC}";
            else echo -e "${RED}CRITICAL: Failed to restore $DRACULA_SCRIPT_TARGET_PATH. Check manually! Path: $DRACULA_SCRIPT_TARGET_PATH Backup: $dracula_backup_file${NC}"; fi
            rm "$temp_script_content" 2>/dev/null
            return 1
        fi
    else
        echo -e "${BLUE}No effective change needed for $DRACULA_SCRIPT_TARGET_PATH for action '$action'.${NC}"
        if [ "$action" = "enable" ] && [ "$anchor_found_for_injection" = false ]; then
             echo -e "${YELLOW}Note: Injection for git status was desired for 'enable' but anchor was not found.${NC}"
        fi
         # ***** FIX: Ensure dracula.sh is executable even if no textual change, in case it lost it before *****
        if [ -f "$DRACULA_SCRIPT_TARGET_PATH" ] && [ ! -x "$DRACULA_SCRIPT_TARGET_PATH" ]; then
            echo -e "${YELLOW}Ensuring $DRACULA_SCRIPT_TARGET_PATH is executable (permissions were missing).${NC}"
            if ! chmod +x "$DRACULA_SCRIPT_TARGET_PATH"; then
                echo -e "${RED}Warning: Failed to ensure $DRACULA_SCRIPT_TARGET_PATH is executable! Theme may not run.${NC}"
            fi
        fi
        # ***** END FIX *****
    fi
    rm "$temp_script_content" 2>/dev/null
    return 0
}

# ... (check_current_status and apply_settings_block functions remain the same) ...
check_current_status() {
    local desc1_first_line="${DESC_STYLE_1%%$'\n'*}"; local desc2_first_line="${DESC_STYLE_2%%$'\n'*}"
    if awk -v s="$START_MARKER" -v e="$END_MARKER" -v d1="$desc1_first_line" '
        BEGIN{in_block=0; found_desc=0}
        $0 ~ s {in_block=1; next}
        $0 ~ e {in_block=0; next}
        in_block && $0 == d1 {found_desc=1; exit}
        END{exit !found_desc}
    ' "$CONFIG_FILE"; then
        echo -e "${GREEN}Current: $STYLE_1_NAME ENABLED${NC}"; echo "$DESC_STYLE_1" | grep -E '^# - ' | sed 's/^# - /  • /'; return 0
    elif awk -v s="$START_MARKER" -v e="$END_MARKER" -v d2="$desc2_first_line" '
        BEGIN{in_block=0; found_desc=0}
        $0 ~ s {in_block=1; next}
        $0 ~ e {in_block=0; next}
        in_block && $0 == d2 {found_desc=1; exit}
        END{exit !found_desc}
    ' "$CONFIG_FILE"; then
        echo -e "${GREEN}Current: $STYLE_2_NAME ENABLED (Advanced OFF)${NC}"; echo "$DESC_STYLE_2" | grep -E '^# - ' | sed 's/^# - /  • /'; return 1
    else
        echo -e "${BLUE}Current: No specific toggle block detected in $CONFIG_FILE.${NC}";
        echo -e "${YELLOW}Will initialize with '$STYLE_1_NAME' settings.${NC}";
        echo "$DESC_STYLE_1" | grep -E '^# - ' | sed 's/^# - /  • /'; return 2 
    fi
}

apply_settings_block() {
    local content_to_apply="${1}"; local temp_config_file;
    temp_config_file=$(mktemp) || { echo -e "${RED}Mktemp failed for applying settings block.${NC}"; return 1; }
    awk -v s="$START_MARKER" -v e="$END_MARKER" '
        BEGIN{in_managed_block=0}
        $0 ~ s {in_managed_block=1; next}
        $0 ~ e {in_managed_block=0; next}
        !in_managed_block {print}
    ' "$CONFIG_FILE" > "$temp_config_file"
    if [ -s "$temp_config_file" ] && [ "$(tail -c1 "$temp_config_file" | wc -l)" -eq 0 ]; then
        echo "" >> "$temp_config_file"
    fi
    echo "$START_MARKER" >> "$temp_config_file"
    echo "${content_to_apply}" >> "$temp_config_file"
    echo "$END_MARKER" >> "$temp_config_file"
    echo "" >> "$temp_config_file" 
    local final_temp_config_file; final_temp_config_file=$(mktemp) || { echo -e "${RED}Mktemp failed for final cleanup.${NC}"; rm "$temp_config_file"; return 1; }
    awk 'BEGIN{empty_line_count=0} NF{print; empty_line_count=0; next} !NF{empty_line_count++; if(empty_line_count<=1) print}' "$temp_config_file" > "$final_temp_config_file"
    if mv -f "$final_temp_config_file" "$CONFIG_FILE"; then
        rm "$temp_config_file" 
        return 0
    else
        echo -e "${RED}Error: Failed to write final settings block to $CONFIG_FILE.${NC}"; rm "$temp_config_file" "$final_temp_config_file" 2>/dev/null; return 1;
    fi
}


# --- Main Script Execution ---
# (This main logic block remains largely the same as the last good version, ensure it calls the updated functions)
echo -e "${BLUE}Starting ${SETTING_NAME} settings check for $CONFIG_FILE...${NC}"
if ! ensure_tpm_installed; then
    echo -e "${RED}TPM installation or setup encountered issues. Some plugin features might not work automatically.${NC}"
    read -p "Do you want to continue with the toggle script anyway? [y/N] " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo -e "${YELLOW}Operation cancelled by user.${NC}"; if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 1; else return 1; fi; fi
    echo -e "${YELLOW}Proceeding, but be aware TPM might not be fully operational without manual checks.${NC}"
fi
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: $CONFIG_FILE not found and was not created. Cannot proceed.${NC}"; if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 1; else return 1; fi
fi

echo -e "\n${BLUE}--- Checking current ${SETTING_NAME} settings in $CONFIG_FILE ---${NC}"
check_current_status
current_status_code=$? 

new_style_is_style1=false 
settings_to_apply=""
new_style_name_for_display=""
new_style_description_for_display=""

if [ $current_status_code -eq 0 ]; then 
    echo -e "\n${YELLOW}>>> About to disable advanced tmux features (switching to $STYLE_2_NAME)${NC}"
    settings_to_apply="$STYLE_2_SETTINGS"; new_style_name_for_display="$STYLE_2_NAME"; new_style_description_for_display="$DESC_STYLE_2"; new_style_is_style1=false
else 
    echo -e "\n${YELLOW}>>> About to enable advanced tmux features ($STYLE_1_NAME)${NC}"
    if [ $current_status_code -eq 2 ]; then echo -e "${BLUE}(No existing toggle block found, initializing with $STYLE_1_NAME settings.)${NC}"; fi
    settings_to_apply="$STYLE_1_SETTINGS"; new_style_name_for_display="$STYLE_1_NAME"; new_style_description_for_display="$DESC_STYLE_1"; new_style_is_style1=true
fi

echo -e "\n${RED}This script will attempt to modify your $CONFIG_FILE.${NC}"
if [ "$new_style_is_style1" = true ]; then
    echo -e "${RED}It will also try to install TPM plugins and modify the Dracula theme script (if found).${NC}"
    echo -e "${RED}Modifying theme scripts is risky and may be overwritten by theme updates.${NC}"
fi
read -p "Do you want to continue? [y/N] " -n 1 -r; echo 

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}Operation cancelled by user.${NC}"; if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 1; else return 1; fi
fi

TIMESTAMP=$(date +"%Y%m%d.%H%M%S") 
CONFIG_BACKUP_FILE="${CONFIG_FILE}.bak.toggle.${TIMESTAMP}"
if cp -f "$CONFIG_FILE" "$CONFIG_BACKUP_FILE"; then
    echo -e "${BLUE}Backup of $CONFIG_FILE created at $CONFIG_BACKUP_FILE${NC}"
else
    echo -e "${RED}Warning: Could not create backup of $CONFIG_FILE. Proceeding without backup...${NC}"
fi

echo -e "${BLUE}Applying main settings block to $CONFIG_FILE...${NC}"
if ! apply_settings_block "$settings_to_apply"; then
    echo -e "\n${RED}CRITICAL: Failed to apply settings block to $CONFIG_FILE. Restore from backup if necessary: $CONFIG_BACKUP_FILE${NC}"; if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 1; else return 1; fi
fi

if [ "$new_style_is_style1" = true ]; then
    echo -e "${BLUE}Managing TPM run line for Advanced mode (ensuring it's active)...${NC}"
    if manage_tpm_run_line "enable"; then
        echo -e "${BLUE}Attempting to automatically install/update TPM plugins (e.g., Dracula)...${NC}"
        if attempt_install_tpm_plugins; then
            echo -e "${GREEN}TPM plugins processed. Dracula plugin should now be available if defined in config.${NC}"
            echo -e "${BLUE}Attempting to inject Git status into Dracula script...${NC}"
            if ! manage_dracula_script_injection "enable"; then
                echo -e "${RED}Failed to inject Git status into Dracula script.${NC}"
                echo -e "${YELLOW}Verify DRACULA_SCRIPT_TARGET_PATH (${DRACULA_SCRIPT_TARGET_PATH}) and ANCHOR_LINE.${NC}"
            fi
        else
            echo -e "${RED}Automatic TPM plugin installation failed or had issues.${NC}"
            echo -e "${YELLOW}Dracula script injection will be skipped. 'Prefix + I' may be needed in tmux.${NC}"
        fi
    else
        echo -e "${RED}Failed to enable TPM run line in $CONFIG_FILE. Plugin features will likely fail.${NC}"
    fi
else
    echo -e "${BLUE}Attempting to remove Git status injection from Dracula script (if it exists)...${NC}"
    if ! manage_dracula_script_injection "disable"; then
        echo -e "${YELLOW}Note: Could not modify Dracula script (may not exist or already clean). See messages above.${NC}"
    fi
    echo -e "${BLUE}Managing TPM run line for Basic mode (ensuring it's removed)...${NC}"
    if ! manage_tpm_run_line "disable"; then
        echo -e "${RED}Failed to disable TPM run line in $CONFIG_FILE.${NC}"
    fi
fi

echo -e "\n${GREEN}Successfully updated configurations for: $new_style_name_for_display!${NC}"
echo "$new_style_description_for_display" | grep -E '^# - ' | sed 's/^# - /  • /'

echo -e "\n${BLUE}To apply changes to your running tmux session:${NC}"
echo -e "  1. ${YELLOW}RECOMMENDED:${NC} Restart tmux completely (${GREEN}tmux kill-server && tmux${NC})."
echo -e "  2. ${YELLOW}ALTERNATIVELY:${NC} Inside tmux, reload config: ${GREEN}tmux source-file \"$CONFIG_FILE\"${NC}"
if [ "$new_style_is_style1" = true ]; then
    echo -e "\n${YELLOW}IMPORTANT FOR ADVANCED MODE (if plugins were just enabled/installed):${NC}"
    echo -e "  After reloading or restarting tmux, press ${GREEN}'Prefix + I' (Shift+i)${NC} inside tmux."
    echo -e "  This ensures all plugins defined in $CONFIG_FILE are properly fetched and sourced by TPM."
    echo -e "  (The script attempted to do this automatically, but 'Prefix + I' is the definitive way.)"
elif [ "$new_style_is_style1" = false ]; then 
    echo -e "\n${YELLOW}NOTE: TPM is now disabled. Plugins (like Dracula) will not load.${NC}"
    echo -e "${YELLOW}Custom Git status injection (if any) has been removed from the Dracula script.${NC}"
fi

if [[ -n "$TMUX" ]] && [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then 
    echo -e "\n${BLUE}Script was sourced within a running tmux session.${NC}"
    echo -e "${YELLOW}Attempting to reload configuration: ${GREEN}$APPLY_COMMAND${NC}"
    if eval "$APPLY_COMMAND"; then
        echo -e "${GREEN}Tmux configuration reloaded.${NC}"
        if [ "$new_style_is_style1" = true ]; then
             echo -e "  ${YELLOW}Remember to press 'Prefix + I' if plugins need installation/sourcing!${NC}"
        fi
    else
        echo -e "${RED}Auto-reloading tmux configuration failed. Please do it manually.${NC}"
    fi
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then exit 0; else return 0; fi
