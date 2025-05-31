#!/bin/bash
# Author: Roy Wiseman 2025-01

parse_docker_yaml_normalize() {
    local yaml_file="$1"

    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: File '$yaml_file' not found." >&2
        return 1
    fi

    # Awk script to parse and normalize the Docker YAML
    # Note: \xA0 is the NO-BREAK SPACE character.
    awk '
    # Function to print collected service info in the desired normalized format
    function print_and_normalize_service_info() {
        if (current_service_name_for_data != "") { # Ensure we have a service to print
            # Determine the container name to print (explicit or default to service name)
            actual_container_name_to_print = (current_container_name_val != "") ? current_container_name_val : current_service_name_for_data

            # --- Format ports ---
            ports_output_string = ""
            if (port_idx > 0) {
                # Strip surrounding quotes from individual port items if present, then join
                temp_port_item = current_ports[1]
                if (temp_port_item ~ /^".*"$/) { sub(/^"/, "", temp_port_item); sub(/"$/, "", temp_port_item) }
                ports_output_string = temp_port_item
                
                for (i = 2; i <= port_idx; i++) {
                    temp_port_item = current_ports[i]
                    if (temp_port_item ~ /^".*"$/) { sub(/^"/, "", temp_port_item); sub(/"$/, "", temp_port_item) }
                    ports_output_string = ports_output_string ";" temp_port_item
                }
            }
            # Enclose the entire joined port string in quotes
            final_formatted_ports = "\"" ports_output_string "\""

            # --- Format volumes ---
            volumes_output_string = ""
            if (volume_idx > 0) {
                # Volumes are joined directly; original quoting of items is preserved by trim_list_item_value
                volumes_output_string = current_volumes[1]
                for (i = 2; i <= volume_idx; i++) {
                    volumes_output_string = volumes_output_string ";" current_volumes[i]
                }
            }
            # No additional quoting around the joined volume string

            # Print the normalized line
            printf "%s, %s, %s\n", actual_container_name_to_print, final_formatted_ports, volumes_output_string
        }
        
        # Reset variables for the next service
        current_service_name_for_data = ""
        current_service_raw_key_name = "" 
        current_container_name_val = ""
        delete current_ports; port_idx = 0
        delete current_volumes; volume_idx = 0
        
        parsing_ports_list = 0
        parsing_volumes_list = 0
        
        # Reset indent markers; they will be re-detected for robustness,
        # though service_definition_indent should ideally be consistent within one services block.
        service_definition_indent = -1 
        # key_indent and item_indent are derived from service_definition_indent
    }

    # Function to get current line indentation (counts leading spaces, tabs, and NO-BREAK SPACE \xA0)
    function get_indentation(line_str) {
        match(line_str, /^[ \t\xA0]*/)
        return RLENGTH
    }
    
    # Function to trim the value part of a list item (text after "- ")
    function trim_list_item_value(raw_item_value) {
        sub(/^[ \t\xA0]+/, "", raw_item_value) # Remove leading whitespace from the value part
        sub(/[ \t\xA0]+$/, "", raw_item_value) # Remove trailing whitespace from the value part
        return raw_item_value 
    }

    # BEGIN block: Initialize state variables
    BEGIN {
        in_services_block = 0          # Flag: are we inside the top-level "services:" block?
        services_block_indent = -1     # Indentation level of the "services:" line itself

        current_service_name_for_data = "" # Clean name of the service being processed (e.g., "portainer")
        current_service_raw_key_name = ""  # Raw key for the service (e.g., "  portainer:") to detect changes
        current_container_name_val = ""    # Value of "container_name:" if found

        delete current_ports; port_idx = 0    # Array and index for port mappings
        delete current_volumes; volume_idx = 0 # Array and index for volume mappings
        
        parsing_ports_list = 0         # Flag: are we currently parsing lines for the "ports:" list?
        parsing_volumes_list = 0       # Flag: are we currently parsing lines for the "volumes:" list?

        service_definition_indent = -1 # Indentation level of a service definition line (e.g., "  portainer:")
        key_indent = -1                # Expected indent for keys like "ports:", "container_name:" under a service
        item_indent = -1               # Expected indent for list items like "- value"
    }

    # Per-line processing block 1: Clean up line (remove CR, comments), skip if effectively empty
    {
        gsub(/\r$/,""); # Remove carriage returns (for Windows-style line endings)
        original_line_for_indent = $0 # Preserve original line for accurate indentation measurement
        sub(/[ \t\xA0]*#.*/, "")      # Remove comments (and any preceding whitespace if comment is on its own)
                                      # This leaves leading spaces of the actual YAML content intact if any.
        if ($0 ~ /^[ \t\xA0]*$/) next # Skip if line is now empty or only whitespace
    }

    # Per-line processing block 2: Main parsing logic
    {
        current_line_actual_indent = get_indentation(original_line_for_indent)
        
        # Prepare line content for key matching (remove leading/trailing whitespace and comments already gone)
        line_content_for_key_compare = $0 
        sub(/^[ \t\xA0]+/, "", line_content_for_key_compare) 
        sub(/[ \t\xA0]+$/, "", line_content_for_key_compare)

        # --- Handle "services:" block context ---
        if (line_content_for_key_compare == "services:") {
            if (!in_services_block) { # Entering the services block
                in_services_block = 1
                services_block_indent = current_line_actual_indent
                # Reset service-specific states
                parsing_ports_list = 0; parsing_volumes_list = 0; service_definition_indent = -1;
            }
            next # Move to next line after processing "services:" keyword
        }

        if (!in_services_block) next # Ignore anything outside a "services:" block

        # If current line indent is less/equal to services_block_indent, we have exited the services block
        if (current_line_actual_indent <= services_block_indent) {
            print_and_normalize_service_info() # Print data for the last service
            in_services_block = 0          # Reset flag
            services_block_indent = -1     # Reset indent
            # Check if this line itself is a new "services:" block (e.g. concatenated files)
            if (line_content_for_key_compare == "services:") {
                in_services_block = 1; services_block_indent = current_line_actual_indent;
                parsing_ports_list = 0; parsing_volumes_list = 0; service_definition_indent = -1;
            }
            next
        }
        
        # --- Handle Service Definitions (e.g., "  portainer:") ---
        # Try to determine the service_definition_indent from the first service encountered
        if (service_definition_indent == -1 && current_line_actual_indent > services_block_indent && $0 ~ /:[ \t\xA0]*$/) {
             service_definition_indent = current_line_actual_indent
             # Assuming consistent indentation steps (e.g., 2 spaces) for sub-keys and list items
             key_indent = service_definition_indent + 2 
             item_indent = key_indent + 2               
        }

        # Is this line a new service definition? (matches expected indent and ends with colon)
        if (current_line_actual_indent == service_definition_indent && $0 ~ /:[ \t\xA0]*$/) {
            temp_service_raw_key = $0; sub(/[ \t\xA0]+$/, "", temp_service_raw_key); # Get "  servicename:"

            if (current_service_raw_key_name != "" && temp_service_raw_key != current_service_raw_key_name) {
                 print_and_normalize_service_info() # Print previous service before starting new one
            }
            # Update current service if it is new or the first one
            if (temp_service_raw_key != current_service_raw_key_name) {
                current_service_raw_key_name = temp_service_raw_key
                
                current_service_name_for_data = line_content_for_key_compare # This is "servicename:"
                sub(/:$/, "", current_service_name_for_data)                 # Now "servicename"
                
                current_container_name_val = "" # Reset for the new service      
                parsing_ports_list = 0; parsing_volumes_list = 0;
                
                # Re-confirm key/item indents for this service (should be consistent from first detection)
                key_indent = service_definition_indent + 2 
                item_indent = key_indent + 2  
            }
            next 
        }

        # --- Handle keys within a service (container_name, ports, volumes) ---
        if (current_service_name_for_data != "") { # Must be inside a service block
            # Check for "container_name:"
            if (current_line_actual_indent == key_indent && line_content_for_key_compare ~ /^container_name:/) {
                current_container_name_val = line_content_for_key_compare # "container_name: value"
                sub(/^container_name:[ \t\xA0]*/, "", current_container_name_val) # "value"
                parsing_ports_list = 0; parsing_volumes_list = 0; # This key ends any list parsing
                next
            }

            # Check for "ports:" keyword
            if (current_line_actual_indent == key_indent && line_content_for_key_compare == "ports:") {
                parsing_ports_list = 1; parsing_volumes_list = 0;
                next
            }

            # Check for "volumes:" keyword
            if (current_line_actual_indent == key_indent && line_content_for_key_compare == "volumes:") {
                parsing_volumes_list = 1; parsing_ports_list = 0;
                next
            }
            
            # Process port list items (e.g., "      - \"9443:9443\"")
            # $0 is the line after comment removal, still has leading spaces for structure
            if (parsing_ports_list && current_line_actual_indent == item_indent && $0 ~ /^[ \t\xA0]*-[ \t\xA0]/) {
                list_item_content = $0
                sub(/^[ \t\xA0]*-[ \t\xA0]*/, "", list_item_content) # Remove leading "- " and surrounding spaces
                current_ports[++port_idx] = trim_list_item_value(list_item_content)
                next
            }

            # Process volume list items
            if (parsing_volumes_list && current_line_actual_indent == item_indent && $0 ~ /^[ \t\xA0]*-[ \t\xA0]/) {
                list_item_content = $0
                sub(/^[ \t\xA0]*-[ \t\xA0]*/, "", list_item_content)
                current_volumes[++volume_idx] = trim_list_item_value(list_item_content)
                next
            }
            
            # If we encounter another key at the `key_indent` level, it signals the end of any active list.
            if (current_line_actual_indent == key_indent && !(line_content_for_key_compare ~ /^[ \t\xA0]*-/)) {
                parsing_ports_list = 0; parsing_volumes_list = 0; 
                # This line is another key (e.g. "image:", "restart:"); we ignore it but stop list parsing.
                next
            }
            
            # If indentation decreases from item_indent but still within the service context, stop list parsing.
            if ((parsing_ports_list || parsing_volumes_list) && 
                current_line_actual_indent < item_indent && current_line_actual_indent > service_definition_indent) {
                 parsing_ports_list = 0; parsing_volumes_list = 0;
                 # The current line might be a new key or something else; it will be re-evaluated if not "nexted".
            }
        }
    }
    # END block: Ensure the last service parsed is printed
    END {
        print_and_normalize_service_info()
    }
    ' "$yaml_file"
}

# --- How to use ---
# 1. Save the entire script above into a file, for example, `parse_yaml.sh`.
# 2. Make it executable: `chmod +x parse_yaml.sh`.
# 3. Create your `docker-managers.yaml` file with the content you provided.
# 4. Run the script: `./parse_yaml.sh docker-managers.yaml`

# Example of direct execution for testing (if you paste the function into your shell):
# create_dummy_yaml() {
# cat > docker-managers.yaml << EOL
# # Paste your YAML content here
# services:
#   portainer: # Note: The space before portainer might be a non-breaking space (U+00A0)
#     image: portainer/portainer-ce:latest
#     container_name: portainer
#     restart: unless-stopped
#     ports:
#       # Portainer Web UI (HTTPS by default on this port if Portainer generates SSL)
#       - "9443:9443"
#       # Portainer Web UI (HTTP - useful if you manage SSL externally or for initial setup)
#       - "9000:9000"
#     volumes:
#       - /var/run/docker.sock:/var/run/docker.sock
#       - ~/.config/portainer-docker:/data
#   yacht:
#     image: ghcr.io/selfhostedpro/yacht:latest
#     container_name: yacht
#     restart: unless-stopped
#     ports:
#       - "8001:8000"
#     volumes:
#       - /var/run/docker.sock:/var/run/docker.sock
#       - ~/.config/yacht-docker:/config
#   dockge:
#     image: louislam/dockge:latest
#     container_name: dockge
#     restart: unless-stopped
#     ports:
#       - "5001:5001"
#     volumes:
#       - /var/run/docker.sock:/var/run/docker.sock
#       - ~/.config/dockge-docker/data:/app/data
#       - ~/dockge_compose_stacks:/opt/stacks
# EOL
# }

# run_parser_test() {
#   create_dummy_yaml
#   echo "Parsing docker-managers.yaml:"
#   parse_docker_yaml_normalize "docker-managers.yaml"
#   rm -f "docker-managers.yaml"
# }

# To test, uncomment and run:
# run_parser_test
