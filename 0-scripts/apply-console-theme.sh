#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to attempt to set the terminal emulator's palette and
# default foreground/background colors for the current SSH session
# via OSC escape sequences.
#
# This needs to be run on the server (Debian) and requires the client
# (e.g., Windows Terminal hosting PowerShell) to support these sequences.
#
# Usage: ./apply_ssh_theme.sh <theme_name>

# --- Helper function to apply palette and main FG/BG ---
apply_colors() {
    local theme_name="$1"
    # Associative array for palette passed as name
    declare -n palette_ref="$2"
    local background_color="$3"
    local foreground_color="$4"

    echo "Attempting to set '$theme_name' palette for your SSH client..."

    # Apply the 16 ANSI colors
    for i in {0..15}; do
        if [ -n "${palette_ref[$i]}" ]; then
            printf "\033]4;%d;%s\007" "$i" "${palette_ref[$i]}"
        fi
    done

    # Set default background (OSC 11) and foreground (OSC 10)
    if [ -n "$background_color" ]; then
        printf "\033]11;%s\007" "$background_color"
    fi
    if [ -n "$foreground_color" ]; then
        printf "\033]10;%s\007" "$foreground_color"
    fi

    echo "'$theme_name' palette commands sent."
}

# --- Theme Definitions ---

apply_theme_default() {
    echo "Attempting to reset to your terminal's default palette..."
    printf "\033]104\007" # Resets the color palette (ANSI 0-255)
    printf "\033]10\007"  # Resets default foreground color
    printf "\033]11\007"  # Resets default background color
    echo "Terminal default palette reset commands sent."
}

apply_theme_solarized_dark() {
    declare -A p
    p[0]="#073642";  p[1]="#dc322f";  p[2]="#859900";  p[3]="#b58900"
    p[4]="#268bd2";  p[5]="#d33682";  p[6]="#2aa198";  p[7]="#eee8d5"
    p[8]="#002b36";  p[9]="#cb4b16";  p[10]="#586e75"; p[11]="#657b83"
    p[12]="#839496"; p[13]="#6c71c4"; p[14]="#93a1a1"; p[15]="#fdf6e3"
    apply_colors "Solarized Dark" p "#002b36" "#839496"
}

apply_theme_gruvbox_dark() {
    declare -A p
    p[0]="#282828";  p[1]="#cc241d";  p[2]="#98971a";  p[3]="#d79921"
    p[4]="#458588";  p[5]="#b16286";  p[6]="#689d6a";  p[7]="#a89984"
    p[8]="#928374";  p[9]="#fb4934";  p[10]="#b8bb26"; p[11]="#fabd2f"
    p[12]="#83a598"; p[13]="#d3869b"; p[14]="#8ec07c"; p[15]="#ebdbb2"
    apply_colors "Gruvbox Dark" p "#282828" "#ebdbb2"
}

apply_theme_dracula() {
    declare -A p
    p[0]="#21222C";  p[1]="#FF5555";  p[2]="#50FA7B";  p[3]="#F1FA8C"
    p[4]="#6272A4";  p[5]="#BD93F9";  p[6]="#8BE9FD";  p[7]="#F8F8F2"
    p[8]="#44475A";  p[9]="#FF6E6E";  p[10]="#69FF94"; p[11]="#FFFFA5"
    p[12]="#7D8AC2"; p[13]="#FF79C6"; p[14]="#A4FFFF"; p[15]="#FFFFFF"
    apply_colors "Dracula" p "#282A36" "#F8F8F2"
}

apply_theme_nord() {
    declare -A p
    p[0]="#2E3440";  p[1]="#BF616A";  p[2]="#A3BE8C";  p[3]="#EBCB8B"
    p[4]="#81A1C1";  p[5]="#B48EAD";  p[6]="#88C0D0";  p[7]="#D8DEE9"
    p[8]="#3B4252";  p[9]="#BF616A";  p[10]="#A3BE8C"; p[11]="#EBCB8B"
    p[12]="#5E81AC"; p[13]="#B48EAD"; p[14]="#8FBCBB"; p[15]="#ECEFF4"
    apply_colors "Nord" p "#2E3440" "#D8DEE9"
}

apply_theme_material_dark() {
    declare -A p
    p[0]="#263238";  p[1]="#FF5252";  p[2]="#69F0AE";  p[3]="#FFFF00"
    p[4]="#82AAFF";  p[5]="#F06292";  p[6]="#80CBC4";  p[7]="#EEFFFF"
    p[8]="#546E7A";  p[9]="#FF8A80";  p[10]="#B9F6CA"; p[11]="#FFFF8D"
    p[12]="#82B1FF"; p[13]="#FF80AB"; p[14]="#A7FFEB"; p[15]="#FFFFFF"
    apply_colors "Material Dark" p "#263238" "#EEFFFF"
}

apply_theme_one_dark_pro() {
    declare -A p
    p[0]="#282C34";  p[1]="#E06C75";  p[2]="#98C379";  p[3]="#E5C07B"
    p[4]="#61AFEF";  p[5]="#C678DD";  p[6]="#56B6C2";  p[7]="#ABB2BF"
    p[8]="#5C6370";  p[9]="#E06C75";  p[10]="#98C379"; p[11]="#E5C07B"
    p[12]="#61AFEF"; p[13]="#C678DD"; p[14]="#56B6C2"; p[15]="#FFFFFF"
    apply_colors "One Dark Pro" p "#282C34" "#ABB2BF"
}

apply_theme_tomorrow_night_eighties() {
    declare -A p
    p[0]="#2D2D2D";  p[1]="#F2777A";  p[2]="#99CC99";  p[3]="#FFCC66"
    p[4]="#6699CC";  p[5]="#CC99CC";  p[6]="#66CCCC";  p[7]="#CCCCCC"
    p[8]="#999999";  p[9]="#F2777A";  p[10]="#99CC99"; p[11]="#FFCC66"
    p[12]="#6699CC"; p[13]="#CC99CC"; p[14]="#66CCCC"; p[15]="#FFFFFF"
    apply_colors "Tomorrow Night Eighties" p "#2D2D2D" "#CCCCCC"
}

apply_theme_monokai_classic() {
    declare -A p
    p[0]="#272822";  p[1]="#F92672";  p[2]="#A6E22E";  p[3]="#F4BF75"
    p[4]="#66D9EF";  p[5]="#AE81FF";  p[6]="#A1EFE4";  p[7]="#F8F8F2"
    p[8]="#75715E";  p[9]="#F92672";  p[10]="#A6E22E"; p[11]="#F4BF75"
    p[12]="#66D9EF"; p[13]="#AE81FF"; p[14]="#A1EFE4"; p[15]="#F9FAFB"
    apply_colors "Monokai Classic" p "#272822" "#F8F8F2"
}

apply_theme_ayu_mirage() {
    declare -A p
    p[0]="#1F2430";  p[1]="#FF3333";  p[2]="#BAE67E";  p[3]="#FFA759"
    p[4]="#73D0FF";  p[5]="#D4BFFF";  p[6]="#95E6CB";  p[7]="#CBCCC6"
    p[8]="#707A8C";  p[9]="#FF3333";  p[10]="#BAE67E"; p[11]="#FFA759"
    p[12]="#73D0FF"; p[13]="#D4BFFF"; p[14]="#95E6CB"; p[15]="#FFFFFF"
    apply_colors "Ayu Mirage" p "#1F2430" "#CBCCC6"
}

apply_theme_synthwave_84() {
    declare -A p
    p[0]="#0D0221";  p[1]="#FF489A";  p[2]="#20F52E";  p[3]="#F8F52F"
    p[4]="#237AFA";  p[5]="#B339FF";  p[6]="#39F9F8";  p[7]="#F8F8F8"
    p[8]="#6B6A73";  p[9]="#FF7EDD";  p[10]="#50FA5B"; p[11]="#F7F85B"
    p[12]="#5091F8"; p[13]="#D279FF"; p[14]="#60FAFA"; p[15]="#FFFFFF"
    apply_colors "Synthwave '84" p "#2B213A" "#F9F9F9" # Specific BG/FG for Synthwave
}

apply_theme_zenburn() {
    declare -A p
    p[0]="#4D4D4D";  p[1]="#705050";  p[2]="#60B48A";  p[3]="#F0DFAF"
    p[4]="#506070";  p[5]="#C080D0";  p[6]="#88AFBE";  p[7]="#DCDCDC"
    p[8]="#6F6F6F";  p[9]="#CC9393";  p[10]="#7F9F7F"; p[11]="#DFAF8F"
    p[12]="#93A3BC"; p[13]="#DC8CC3"; p[14]="#94BFF3"; p[15]="#FFFFFF"
    apply_colors "Zenburn" p "#3F3F3F" "#DCDCDC"
}

apply_theme_catppuccin_mocha() {
    declare -A p
    p[0]="#1E1E2E";  p[1]="#F38BA8";  p[2]="#A6E3A1";  p[3]="#F9E2AF" # base, red, green, yellow
    p[4]="#89B4FA";  p[5]="#F5C2E7";  p[6]="#94E2D5";  p[7]="#BAC2DE" # blue, pink, teal, subtext1
    p[8]="#313244";  p[9]="#EBA0AC";  p[10]="#A6E3A1"; p[11]="#F9E2AF" # surface0, maroon (alt-red), green, yellow
    p[12]="#74C7EC"; p[13]="#CBA6F7"; p[14]="#89DCEB"; p[15]="#CDD6F4" # sapphire (alt-blue), mauve (alt-pink), sky (alt-teal), text
    apply_colors "Catppuccin Mocha" p "#1E1E2E" "#CDD6F4" # base, text
}

apply_theme_tokyo_night_storm() {
    declare -A p
    p[0]="#1D202F";  p[1]="#F7768E";  p[2]="#9ECE6A";  p[3]="#E0AF68"
    p[4]="#7AA2F7";  p[5]="#BB9AF7";  p[6]="#7DCFFF";  p[7]="#A9B1D6"
    p[8]="#414868";  p[9]="#F7768E";  p[10]="#9ECE6A"; p[11]="#E0AF68"
    p[12]="#7AA2F7"; p[13]="#BB9AF7"; p[14]="#7DCFFF"; p[15]="#C0CAF5"
    apply_colors "Tokyo Night Storm" p "#24283B" "#C0CAF5"
}

apply_theme_palenight_material() {
    declare -A p
    p[0]="#292D3E";  p[1]="#F07178";  p[2]="#C3E88D";  p[3]="#FFCB6B"
    p[4]="#82AAFF";  p[5]="#C792EA";  p[6]="#89DDFF";  p[7]="#A6ACCD"
    p[8]="#434758";  p[9]="#F07178";  p[10]="#C3E88D"; p[11]="#FFCB6B"
    p[12]="#82AAFF"; p[13]="#C792EA"; p[14]="#89DDFF"; p[15]="#FFFFFF"
    apply_colors "Palenight Material" p "#292D3E" "#A6ACCD"
}

# --- Main script logic ---
if [ -z "$1" ]; then
    echo "Usage: $0 <theme_name>"
    echo "Available themes: default, solarized_dark, gruvbox_dark, dracula, nord,"
    echo "                  material_dark, one_dark_pro, tomorrow_night_eighties,"
    echo "                  monokai_classic, ayu_mirage, synthwave_84, zenburn,"
    echo "                  catppuccin_mocha, tokyo_night_storm, palenight_material"
    exit 1
fi

case "$1" in
    default)                       apply_theme_default ;;
    solarized_dark)                apply_theme_solarized_dark ;;
    gruvbox_dark)                  apply_theme_gruvbox_dark ;;
    dracula)                       apply_theme_dracula ;;
    nord)                          apply_theme_nord ;;
    material_dark)                 apply_theme_material_dark ;;
    one_dark_pro)                  apply_theme_one_dark_pro ;;
    tomorrow_night_eighties)       apply_theme_tomorrow_night_eighties ;;
    monokai_classic)               apply_theme_monokai_classic ;;
    ayu_mirage)                    apply_theme_ayu_mirage ;;
    synthwave_84)                  apply_theme_synthwave_84 ;;
    zenburn)                       apply_theme_zenburn ;;
    catppuccin_mocha)              apply_theme_catppuccin_mocha ;;
    tokyo_night_storm)             apply_theme_tokyo_night_storm ;;
    palenight_material)            apply_theme_palenight_material ;;
    *)
        echo "Unknown theme: $1"
        # Re-list available themes for convenience
        echo "Available themes: default, solarized_dark, gruvbox_dark, dracula, nord,"
        echo "                  material_dark, one_dark_pro, tomorrow_night_eighties,"
        echo "                  monokai_classic, ayu_mirage, synthwave_84, zenburn,"
        echo "                  catppuccin_mocha, tokyo_night_storm, palenight_material"
        exit 1
        ;;
esac

echo ""
echo "Reminder: These changes are likely temporary for this SSH session only."
echo "The script changes how your terminal *displays* colors; it does not change server-side settings like LS_COLORS."
echo "Run 'clear' to refresh the full screen with the new theme if needed."
