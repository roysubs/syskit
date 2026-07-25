#!/usr/bin/env bash

# ===================================================================================
# CONFIGURATION & INITIALIZATION
# ===================================================================================
EBOOK_CONVERT="/Applications/Calibre.app/Contents/MacOS/ebook-convert"
SUPPORTED_EXTENSIONS=("epub" "mobi" "docx" "doc" "odt" "pdf" "txt" "azw")

# ANSI Color Codes for clean Terminal output
CYAN='\033[0;36m'
DARK_CYAN='\033[0;34m'
YELLOW='\033[1;33m'
DARK_YELLOW='\033[0;33m'
GREEN='\033[0;32m'
DARK_GREEN='\033[0;32m'
RED='\033[0;31m'
DARK_GRAY='\033[1;30m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Counter Tracking
TOTAL_PROCESSED=0
SUCCESS_COUNT=0
FAILURE_COUNT=0
SKIPPED_COUNT=0

# Arrays to hold summary logs
SUCCESSFUL_CONVERSIONS=()
FAILED_CONVERSIONS=()
SKIPPED_FILES=()
CONFLICTED_FILES=()

# Robust helper function to get file size across standard macOS and GNU stat environments
get_file_size_mb() {
    local filepath="$1"
    local size_bytes=0
    
    # Check if stat supports GNU style (-c%s) or macOS style (-f%z)
    if stat --help >/dev/null 2>&1 || stat -c%s "$filepath" >/dev/null 2>&1; then
        size_bytes=$(stat -c%s "$filepath" 2>/dev/null)
    else
        size_bytes=$(stat -f%z "$filepath" 2>/dev/null)
    fi

    # Fallback if stat completely fails to return a clean number
    if [[ ! "$size_bytes" =~ ^[0-9]+$ ]]; then
        echo "Unknown"
        return
    fi

    echo "scale=2; $size_bytes / 1048576" | bc
}

# ===================================================================================
# USAGE HELP FUNCTION
# ===================================================================================
show_usage() {
    echo -e ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         AZW3 Book Conversion Tool (Kindle Format)          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${YELLOW}DESCRIPTION:${NC}"
    echo -e "  Converts ebook files to AZW3 format using Calibre's ebook-convert tool."
    echo -e "  Supports: .epub, .mobi, .docx, .doc, .odt, .pdf, .txt, .azw"
    echo -e ""
    echo -e "  • Successfully converted files are archived to '_originals/<format>/'" ${GREEN}
    echo -e "  • Failed conversions are moved to '_cannot_convert/'" ${RED}
    echo -e "  • Duplicate filenames are handled automatically with _1, _2 suffixes" ${DARK_GRAY}
    echo -e "  • Detailed summary report shows all conversions and duplicates" ${DARK_GRAY}
    echo -e ""
    echo -e "${YELLOW}USAGE:${NC}"
    echo -e "  ./convert-books-to-azw3.sh -f <path> [-r]"
    echo -e ""
    echo -e "${YELLOW}PARAMETERS:${NC}"
    echo -e "  -f <path>     ${WHITE}(Required)${NC} Path to folder containing ebook files"
    echo -e "  -r            ${WHITE}(Optional)${NC} Process all subfolders recursively"
    echo -e ""
    echo -e "${YELLOW}EXAMPLES:${NC}"
    echo -e "  ./convert-books-to-azw3.sh -f \"/Users/Benny/Books\""
    echo -e "  ./convert-books-to-azw3.sh -f \"/Users/Benny/Books\" -r"
    echo -e ""
    echo -e "${YELLOW}REQUIREMENTS:${NC}"
    echo -e "  • Calibre must be installed in your Applications folder."
    echo -e "  • Download: https://calibre-ebook.com/download"
    echo -e ""
    exit 0
}

# Parse Input Arguments
FOLDER=""
RECURSE=false

while getopts "f:rh" opt; do
    case ${opt} in
        f ) FOLDER="$OPTARG" ;;
        r ) RECURSE=true ;;
        h ) show_usage ;;
        \? ) show_usage ;;
    esac
done

if [ -z "$FOLDER" ]; then
    show_usage
fi

# ===================================================================================
# PRE-RUN CHECKS
# ===================================================================================
if [ ! -f "$EBOOK_CONVERT" ]; then
    echo -e "${RED}Error: Calibre 'ebook-convert' not found at expected path.${NC}"
    echo -e "Expected: $EBOOK_CONVERT"
    echo -e "Please install Calibre or check your installation path."
    exit 1
fi

if [ ! -d "$FOLDER" ]; then
    echo -e "${RED}Error: The specified folder does not exist: $FOLDER${NC}"
    exit 1
fi

# Resolve folder to absolute path
FOLDER=$(cd "$FOLDER" && pwd)

ORIGINALS_ROOT="$FOLDER/_originals"
CANNOT_CONVERT_FOLDER="$FOLDER/_cannot_convert"

# --- Header Display
echo -e ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         AZW3 Book Conversion Tool (Kindle Format)          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "${YELLOW}Source Folder: ${NC}$FOLDER"
echo -e "${YELLOW}Target Format: ${NC}AZW3 (Modern Kindle)"
echo -e "${YELLOW}Recursive:     ${NC}$( $RECURSE && echo -e "${GREEN}ENABLED - Subfolders included${NC}" || echo -e "${DARK_GRAY}DISABLED - Top folder only${NC}" )"
echo -e ""

# Build the file discovery loop command depending on Recursion flag
FILE_LIST=()
while IFS= read -r -d '' file; do
    ext="${file##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    # Check if the extension is in our supported list
    for s_ext in "${SUPPORTED_EXTENSIONS[@]}"; do
        if [ "$ext_lower" == "$s_ext" ]; then
            FILE_LIST+=("$file")
            break
        fi
    done
done < <( if $RECURSE; then find "$FOLDER" -type f -not -path "*/_originals/*" -not -path "*/_cannot_convert/*" -print0; else find "$FOLDER" -maxdepth 1 -type f -print0; fi )

TOTAL_FILES=${#FILE_LIST[@]}

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo -e "${YELLOW}No supported files found in the specified folder.${NC}"
    exit 0
fi

echo -e "${GREEN}Found $TOTAL_FILES file(s) to process...${NC}"

# ===================================================================================
# SCRIPT PROCESSING LOOP
# ===================================================================================
for source_path in "${FILE_LIST[@]}"; do
    ((TOTAL_PROCESSED++))
    
    file_name=$(basename "$source_path")
    parent_folder=$(dirname "$source_path")
    ext="${file_name##*.}"
    base_name="${file_name%.*}"
    
    # Skip files that are already azw3
    if [ "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" == "azw3" ]; then
        echo -e "${DARK_GRAY}[$TOTAL_PROCESSED/$TOTAL_FILES] Skipping: $file_name (already AZW3)${NC}"
        ((SKIPPED_COUNT++))
        SKIPPED_FILES+=("$file_name (already AZW3)")
        continue
    fi
    
    destination_path="$parent_folder/$base_name.azw3"
    
    # Skip if converted file already exists
    if [ -f "$destination_path" ]; then
        echo -e "${DARK_GRAY}[$TOTAL_PROCESSED/$TOTAL_FILES] Skipping: $file_name (AZW3 already exists)${NC}"
        ((SKIPPED_COUNT++))
        SKIPPED_FILES+=("$file_name (AZW3 exists)")
        continue
    fi
    
    # Log Entry Header using universal size tool
    file_size_mb=$(get_file_size_mb "$source_path")
    
    echo -e ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Processing [$TOTAL_PROCESSED/$TOTAL_FILES]: ${WHITE}$file_name${NC}"
    echo -e "${DARK_CYAN}───────────────────────────────────────────────────────────${NC}"
    echo -e "${DARK_GRAY}  Format: .$ext → .azw3${NC}"
    if [ "$file_size_mb" != "Unknown" ]; then
        echo -e "${DARK_GRAY}  Size:   $file_size_mb MB${NC}"
    fi
    if $RECURSE; then
        relative_path="${source_path#$FOLDER/}"
        echo -e "${DARK_GRAY}  Path:   $relative_path${NC}"
    fi
    echo -e ""
    
    # Execute Conversion
    "$EBOOK_CONVERT" "$source_path" "$destination_path" > /dev/null 2>&1
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        # FAILED CONVERSION HANDLER
        echo -e "${RED}  Conversion FAILED with exit code $exit_code${NC}"
        ((FAILURE_COUNT++))
        FAILED_CONVERSIONS+=("$file_name (Exit code: $exit_code)")
        
        mkdir -p "$CANNOT_CONVERT_FOLDER"
        
        target_path="$CANNOT_CONVERT_FOLDER/$file_name"
        final_path="$target_path"
        counter=1
        
        while [ -f "$final_path" ]; do
            final_path="$CANNOT_CONVERT_FOLDER/${base_name}_${counter}.${ext}"
            ((counter++))
        done
        
        if [ "$final_path" != "$target_path" ]; then
            CONFLICTED_FILES+=("$file_name -> Moved to _cannot_convert as $(basename "$final_path")")
        fi
        
        mv "$source_path" "$final_path"
        echo -e "${RED}   → Moved to: _cannot_convert/$(basename "$final_path")${NC}"
    else
        # SUCCESSFUL CONVERSION HANDLER
        echo -e "${GREEN}  ✓ Conversion SUCCESSFUL${NC}"
        ((SUCCESS_COUNT++))
        SUCCESSFUL_CONVERSIONS+=("$base_name.azw3")
        
        if [ -f "$destination_path" ]; then
            out_size_mb=$(get_file_size_mb "$destination_path")
            if [ "$out_size_mb" != "Unknown" ]; then
                echo -e "${GREEN}   → Created: $base_name.azw3 ($out_size_mb MB)${NC}"
            else
                echo -e "${GREEN}   → Created: $base_name.azw3${NC}"
            fi
        fi
        
        format_folder="$ORIGINALS_ROOT/$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
        mkdir -p "$format_folder"
        
        target_path="$format_folder/$file_name"
        final_path="$target_path"
        counter=1
        
        while [ -f "$final_path" ]; do
            final_path="$format_folder/${base_name}_${counter}.${ext}"
            ((counter++))
        done
        
        if [ "$final_path" != "$target_path" ]; then
            CONFLICTED_FILES+=("$file_name -> Archived to _originals/ as $(basename "$final_path")")
        fi
        
        mv "$source_path" "$final_path"
        echo -e "${DARK_GREEN}   → Archived to: _originals/$(echo "$ext" | tr '[:upper:]' '[:lower:]')/$(basename "$final_path")${NC}"
    fi
done

# ===================================================================================
# CONVERSION SUMMARY REPORT
# ===================================================================================
echo -e ""
echo -e ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    CONVERSION SUMMARY                      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "  Total Files Processed: ${WHITE}$TOTAL_PROCESSED${NC}"
echo -e "  Successful:            ${GREEN}$SUCCESS_COUNT${NC}"
echo -e "  Failed:                ${RED}$FAILURE_COUNT${NC}"
echo -e "  Skipped:               ${DARK_GRAY}$SKIPPED_COUNT${NC}"
echo -e ""

if [ ${#SUCCESSFUL_CONVERSIONS[@]} -gt 0 ]; then
    echo -e "${GREEN}───────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}✓ SUCCESSFULLY CONVERTED:${NC}"
    echo -e ""
    IFS=$'\n' sorted_success=($(sort <<<"${SUCCESSFUL_CONVERSIONS[*]}")); unset IFS
    for book in "${sorted_success[@]}"; do
        echo -e "${GREEN}  • $book${NC}"
    done
    echo -e ""
fi

if [ ${#FAILED_CONVERSIONS[@]} -gt 0 ]; then
    echo -e "${RED}───────────────────────────────────────────────────────────${NC}"
    echo -e "${RED}✗ FAILED CONVERSIONS:${NC}"
    echo -e ""
    IFS=$'\n' sorted_fail=($(sort <<<"${FAILED_CONVERSIONS[*]}")); unset IFS
    for failure in "${sorted_fail[@]}"; do
        echo -e "${RED}  • $failure${NC}"
    done
    echo -e ""
    echo -e "${YELLOW}  → Check the '_cannot_convert' folder for these files${NC}"
    echo -e ""
fi

if [ ${#SKIPPED_FILES[@]} -gt 0 ]; then
    echo -e "${DARK_GRAY}───────────────────────────────────────────────────────────${NC}"
    echo -e "${DARK_GRAY}⊘ SKIPPED FILES:${NC}"
    echo -e ""
    IFS=$'\n' sorted_skip=($(sort <<<"${SKIPPED_FILES[*]}")); unset IFS
    for skipped in "${sorted_skip[@]}"; do
        echo -e "${DARK_GRAY}  • $skipped${NC}"
    done
    echo -e ""
fi

if [ ${#CONFLICTED_FILES[@]} -gt 0 ]; then
    echo -e "${YELLOW}───────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}⚠ CONFLICTED FILES FOUND (Duplicates renamed):${NC}"
    echo -e ""
    IFS=$'\n' sorted_conflict=($(sort <<<"${CONFLICTED_FILES[*]}")); unset IFS
    for conflict in "${sorted_conflict[@]}"; do
        echo -e "${YELLOW}  • $conflict${NC}"
    done
    echo -e ""
fi

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ Successfully converted files are ready for your Kindle!${NC}"
fi

if [ $FAILURE_COUNT -eq 0 ] && [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ All conversions completed successfully!${NC}"
    echo -e "${DARK_GREEN}  You can safely delete the '_originals' folder after verification.${NC}"
fi
echo -e ""
