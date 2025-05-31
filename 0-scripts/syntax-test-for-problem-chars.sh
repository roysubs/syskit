#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script to find files with potentially problematic characters.
# Run it from the root of your project directory.

# Exclude .git directory, and common binary file extensions by default.
# You can add more extensions to exclude if needed.
EXCLUDE_DIRS_PATTERN="-path ./git -prune" # Exclude .git directory
# Add more -o -name '*.ext' -prune if needed for specific binary files you don't want checked by content
# For now, we'll rely on the 'file' command for type detection primarily.

find . \( $EXCLUDE_DIRS_PATTERN \) -o -type f -print0 | while IFS= read -r -d $'\0' filepath; do
    # Use 'file' command to guess if it's a text file
    # -b: brief mode (no filename)
    # --mime-type: output MIME type
    # --mime-encoding: output MIME encoding
    mimetype=$(file -b --mime-type "$filepath")
    mimeencoding=$(file -b --mime-encoding "$filepath")

    is_text=0
    if [[ "$mimetype" == text/* ]]; then
        is_text=1
    elif [[ "$mimetype" == "application/octet-stream" || "$mimetype" == "application/x-empty" ]]; then
        # For unknown or empty files, try to see if they look like text
        # by checking if they are valid in a common encoding like UTF-8
        # and don't contain too many NULLs. This is heuristic.
        if ! grep -qP '\x00' "$filepath"; then # If no NULL bytes
             if iconv -f UTF-8 -t UTF-8 "$filepath" >/dev/null 2>&1; then # And is valid UTF-8
                is_text=1 # Tentatively treat as text
             fi
        fi
    fi

    if [[ $is_text -eq 1 ]]; then
        # 1. Check for NULL bytes (shouldn't be in valid text files)
        if LC_ALL=C grep -qP '\x00' "$filepath"; then
            echo "WARNING: NULL byte(s) found in (presumed text file): \"$filepath\" (MIME: $mimetype, Encoding: $mimeencoding)"
        fi

        # 2. Check for invalid UTF-8 sequences (if encoding is UTF-8 or not binary)
        #    This check is more reliable if mimeencoding is utf-8
        if [[ "$mimeencoding" == "utf-8" ]]; then
            if ! iconv -f UTF-8 -t UTF-8 "$filepath" >/dev/null 2>&1; then
                echo "ERROR: Invalid UTF-8 sequence in: \"$filepath\" (Declared UTF-8)"
            fi
        elif [[ "$mimeencoding" == "us-ascii" || "$mimeencoding" == "unknown-8bit" ]]; then
            # For ASCII or unknown, try to validate as UTF-8 anyway, as it's common.
            # If it fails, it *might* be an issue or just a different encoding.
             if ! iconv -f UTF-8 -t UTF-8 "$filepath" >/dev/null 2>&1; then
                echo "INFO: May not be valid UTF-8 (or is another encoding): \"$filepath\" (Declared: $mimeencoding)"
            fi
        fi
        
        # 3. Check for other non-printable ASCII control characters (excluding Tab, LF, CR)
        #    Regex: [\x00-\x08\x0B\x0C\x0E-\x1F\x7F]
        #    This can be noisy for some legitimate files, use with caution.
        if LC_ALL=C grep -qP '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' "$filepath"; then
             echo "INFO: Non-standard ASCII control characters (other than TAB/LF/CR/NULL) found in: \"$filepath\""
        fi

    # Optional: Report on files that are not identified as text but also not common binary types
    # elif [[ "$mimetype" != application/* && "$mimetype" != image/* && "$mimetype" != audio/* && "$mimetype" != video/* && "$mimetype" != "inode/x-empty" ]]; then
    #    echo "INFO: File of undetermined text/binary type: \"$filepath\" (MIME: $mimetype, Encoding: $mimeencoding)"
    fi
done

echo "Character check script finished."
