#!/usr/bin/awk -f
# Save this as, e.g., parse_simple.awk and run: awk -f parse_simple.awk your_docker_file.yaml
# Or: cat your_docker_file.yaml | awk -f parse_simple.awk

BEGIN {
    # Initialize variables for storing data for one service
    current_c_name = ""
    # For ports list
    n_ports = 0
    # For volumes list
    n_volumes = 0
    
    # Flags to know which section we are in
    in_ports_section = 0
    in_volumes_section = 0
}

# Function to process and print the collected data for a service
function output_service_data() {
    if (current_c_name != "") { # Only print if we have a container name
        ports_string = ""
        if (n_ports > 0) {
            # Strip outer quotes from individual port items before joining
            temp_item = ports_list[1]
            if (temp_item ~ /^".*"$/) { sub(/^"/, "", temp_item); sub(/"$/, "", temp_item) }
            ports_string = temp_item
            for (i = 2; i <= n_ports; i++) {
                temp_item = ports_list[i]
                if (temp_item ~ /^".*"$/) { sub(/^"/, "", temp_item); sub(/"$/, "", temp_item) }
                ports_string = ports_string ";" temp_item
            }
        }

        volumes_string = ""
        if (n_volumes > 0) {
            volumes_string = volumes_list[1] # Assumes volume items are already correctly formatted
            for (i = 2; i <= n_volumes; i++) {
                volumes_string = volumes_string ";" volumes_list[i]
            }
        }
        
        # Output in the format: container_name, "port1;port2;...", volume1;volume2;...
        printf "%s, \"%s\", %s\n", current_c_name, ports_string, volumes_string
    }

    # Reset for the next service block
    current_c_name = ""
    delete ports_list
    n_ports = 0
    delete volumes_list
    n_volumes = 0
    in_ports_section = 0
    in_volumes_section = 0
}

# Main processing loop for each line
{
    # 1. Ignore comments fully
    sub(/#.*/, "")

    # 2. Trim leading/trailing whitespace (including non-breaking spaces \xA0 if present)
    gsub(/^[ \t\xA0]+|[ \t\xA0]+$/, "")

    # 3. Skip empty lines
    if ($0 == "") {
        next
    }

    # 4. Look for container_name:
    # If a line starts with "container_name:", it signals a new service entry for our purpose.
    # Output previously collected data before starting a new one.
    if (NF >= 2 && $1 == "container_name:") {
        output_service_data() # Output data for the previous service, if any

        current_c_name = $2
        for (i = 3; i <= NF; i++) current_c_name = current_c_name " " $i # Handle names with spaces

        in_ports_section = 0 # Reset section flags
        in_volumes_section = 0
        next # Move to the next line
    }

    # 5. Look for "ports:" line (assuming it's the whole line after trimming)
    if ($0 == "ports:") {
        in_ports_section = 1
        in_volumes_section = 0
        next # Move to the next line
    }

    # 6. Look for "volumes:" line (assuming it's the whole line after trimming)
    if ($0 == "volumes:") {
        in_volumes_section = 1
        in_ports_section = 0
        next # Move to the next line
    }

    # 7. Process list items (lines starting with "-")
    if ($1 == "-") {
        # Extract the value after "- "
        list_item_value = $0
        sub(/^-[ \t\xA0]*/, "", list_item_value) # Remove the leading "- " and any spaces after it
        # Further trim the extracted value, just in case
        gsub(/^[ \t\xA0]+|[ \t\xA0]+$/, "", list_item_value)


        if (in_ports_section) {
            ports_list[++n_ports] = list_item_value
        } else if (in_volumes_section) {
            volumes_list[++n_volumes] = list_item_value
        }
        next # Move to the next line
    }

    # If a line is none of the above, and we are in a section,
    # it might imply the end of that list section if it's not an item.
    # For simplicity, this script assumes sections continue until a new section keyword
    # or new container_name is found. This might misinterpret other keys if they appear.
}

# END block: Ensure the data for the very last service is printed
END {
    output_service_data()
}
