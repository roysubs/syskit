# Author: Roy Wiseman 2025-01
testparm -s 2>&1 | awk '
# awk script starts here - CORRECTED
BEGIN {
    # Initialize variables and arrays
    current_share = ""
    share_count = 0
    # Define headers
    headers[0] = "Name"
    headers[1] = "CreateMask"
    headers[2] = "DirMask"
    headers[3] = "Read-Only"
    headers[4] = "ValidUsers"
    headers[5] = "Path"
    headers[6] = "Comment"

    # Initialize max widths with header lengths
    for (i = 0; i <= 6; i++) {
        max_widths[i] = length(headers[i])
    }
}

{ # Main processing block for every line
    # Check if the line is a share header
    if ($0 ~ /^\[.*\]$/) {
        # If we were processing a previous share (and it is not the global section)
        if (current_share != "" && current_share != "global") {
            # Store the order of the previous share
            share_order[share_count++] = current_share
        }

        # Extract the new share name
        first_bracket = index($0, "[")
        last_bracket = index($0, "]")
        current_share = substr($0, first_bracket + 1, last_bracket - first_bracket - 1)

        # Initialize the entry for the new share in the shares array with default values
        shares[current_share, "createmask"] = "default"
        shares[current_share, "dirmask"] = "default"
        shares[current_share, "path"] = "n.a."
        shares[current_share, "readonly"] = "default"
        shares[current_share, "validusers"] = "n.a."
        shares[current_share, "comment"] = "n.a."

    } else if (current_share != "" && current_share != "global") { # Process lines within a share (excluding global)
        # Trim leading and trailing whitespace (spaces and tabs) for processing
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)

        # Use pattern matching and extraction for parameters, assigning directly to the shares array
        if (match(line, /^create mask *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value) # Trim spaces from the value
            shares[current_share, "createmask"] = value
        } else if (match(line, /^directory mask *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "dirmask"] = value
        } else if (match(line, /^path *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "path"] = value
        } else if (match(line, /^read only *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            if (value == "Yes") shares[current_share, "readonly"] = "Yes"
            else if (value == "No") shares[current_share, "readonly"] = "No"
            else shares[current_share, "readonly"] = value
        } else if (match(line, /^valid users *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "validusers"] = value
        } else if (match(line, /^comment *=/)) { # Extract comment
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "comment"] = value
        }
    }
}

END {
    # Process the last share data (if it exists and is not the global section)
     if (current_share != "" && current_share != "global") {
        share_order[share_count++] = current_share # Store the order of the last share
    }

    # Determine the maximum width for each column based on data and headers
    for (i = 0; i < share_count; i++) {
        share_name = share_order[i]
        if (length(share_name) > max_widths[0]) max_widths[0] = length(share_name)
        if (length(shares[share_name, "createmask"]) > max_widths[1]) max_widths[1] = length(shares[share_name, "createmask"])
        if (length(shares[share_name, "dirmask"]) > max_widths[2]) max_widths[2] = length(shares[share_name, "dirmask"])
        if (length(shares[share_name, "readonly"]) > max_widths[3]) max_widths[3] = length(shares[share_name, "readonly"])
        if (length(shares[share_name, "validusers"]) > max_widths[4]) max_widths[4] = length(shares[share_name, "validusers"])
        if (length(shares[share_name, "path"]) > max_widths[5]) max_widths[5] = length(shares[share_name, "path"])
        if (length(shares[share_name, "comment"]) > max_widths[6]) max_widths[6] = length(shares[share_name, "comment"])
    }

    # Print headers with dynamic width
    printf "%-*s  ", max_widths[0], headers[0]
    printf "%-*s  ", max_widths[1], headers[1]
    printf "%-*s  ", max_widths[2], headers[2]
    printf "%-*s  ", max_widths[3], headers[3]
    printf "%-*s  ", max_widths[4], headers[4]
    printf "%-*s  ", max_widths[5], headers[5]
    printf "%-*s\n", max_widths[6], headers[6]

    # Print the separator line made of '=' characters
    for (i = 0; i <= 6; i++) {
        for (j = 0; j < max_widths[i]; j++) {
            printf "="
        }
        if (i < 6) {
            printf "  "
        }
    }
    printf "\n"

    # Print share data with dynamic width
    for (i = 0; i < share_count; i++) {
        share_name = share_order[i]
        printf "%-*s  ", max_widths[0], share_name
        printf "%-*s  ", max_widths[1], shares[share_name, "createmask"]
        printf "%-*s  ", max_widths[2], shares[share_name, "dirmask"]
        printf "%-*s  ", max_widths[3], shares[share_name, "readonly"]
        printf "%-*s  ", max_widths[4], shares[share_name, "validusers"]
        printf "%-*s  ", max_widths[5], shares[share_name, "path"]
        printf "%-*s\n", max_widths[6], shares[share_name, "comment"]
    }
}'
# awk script ends here

