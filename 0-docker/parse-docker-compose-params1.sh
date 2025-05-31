#!/bin/bash
# Author: Roy Wiseman 2025-01

parse_docker_yaml_bash() {
    local yaml_file="$1"

    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: File '$yaml_file' not found." >&2
        return 1
    fi

    awk '
    # Function to print collected service info and reset for the next one
    function print_and_reset_service_info() {
        if (current_service_name != "") {
            # Default container_name to service_name if not explicitly set
            actual_container_name = (current_container_name_val != "") ? current_container_name_val : current_service_name_raw
            
            printf "Container Name: %s\n", actual_container_name
            
            printf "Ports:\n"
            if (port_idx > 0) {
                for (i = 1; i <= port_idx; i++) {
                    printf "  - %s\n", current_ports[i]
                }
            } else {
                printf "  - None\n"
            }
            
            printf "Volumes:\n"
            if (volume_idx > 0) {
                for (i = 1; i <= volume_idx; i++) {
                    printf "  - %s\n", current_volumes[i]
                }
            } else {
                printf "  - None\n"
            }
            printf "\n" # Newline for separation between services
        }
        
        # Reset for next service
        current_service_name = ""
        current_service_name_raw = ""
        current_container_name_val = ""
        delete current_ports
        port_idx = 0
        delete current_volumes
        volume_idx = 0
        
        parsing_ports_list = 0
        parsing_volumes_list = 0
        
        service_definition_indent = -1 # Reset: this will be detected for each new service
                                       # relative to the services_block_indent
    }

    # Get current line indentation (count leading spaces)
    function get_indent(line) {
        match(line, /^ */)
        return RLENGTH
    }
    
    # Remove leading/trailing whitespace and the item marker "- " from list items
    function trim_list_item(item_line) {
        sub(/^[ \t]*- /, "", item_line) # Remove "- " prefix
        sub(/^[ \t]+/, "", item_line)   # Remove leading whitespace
        sub(/[ \t]+$/, "", item_line)   # Remove trailing whitespace
        return item_line
    }

    BEGIN {
        in_services_block = 0
        services_block_indent = -1 # Indentation of the "services:" line

        current_service_name = ""      # Name of the service block currently being parsed
        current_service_name_raw = ""  # Service name with colon, for precise matching
        current_container_name_val = "" # Value of container_name

        # Arrays for ports and volumes
        delete current_ports
        port_idx = 0
        delete current_volumes
        volume_idx = 0
        
        # State flags for parsing multi-line sections (ports list, volumes list)
        parsing_ports_list = 0
        parsing_volumes_list = 0

        # Indentation levels for context
        service_definition_indent = -1 # Indent of the service name line itself (e.g., "  webapp:")
        key_indent = -1                # Expected indent of keys like "ports:", "volumes:" under a service
        item_indent = -1               # Expected indent of list items ("- ...")
    }

    # 1. Pre-processing: remove comments and skip fully blank lines
    {
        sub(/#.*/, "")  # Remove comments
        if ($0 ~ /^[ \t]*$/) next # Skip if line is now empty or only whitespace
    }

    # Main parsing logic
    {
        current_line_indent = get_indent($0)
        line_content = $0
        sub(/^[ \t]+/, "", line_content) # Get content without leading spaces for key matching

        # A. Detect start or end of the main "services:" block
        if (line_content == "services:") {
            if (!in_services_block) { # Starting the services block
                in_services_block = 1
                services_block_indent = current_line_indent
                # Reset service-specific parsing states, just in case
                parsing_ports_list = 0
                parsing_volumes_list = 0
                service_definition_indent = -1 # Will be set by the first service
            }
            next
        }

        if (!in_services_block) {
            next # Ignore lines outside the "services:" block
        }

        # If current line is less or equally indented than "services:", the block has ended
        if (current_line_indent <= services_block_indent) {
            print_and_reset_service_info() # Print info for the last service in the block
            in_services_block = 0
            services_block_indent = -1
            # Check if this line is a new "services:" block (unlikely but for robustness)
             if (line_content == "services:") {
                in_services_block = 1
                services_block_indent = current_line_indent
                parsing_ports_list = 0
                parsing_volumes_list = 0
                service_definition_indent = -1
            }
            next
        }

        # B. Inside "services:" block: Detect new service definitions or service properties
        
        # Heuristic: A new service definition is a key ending with ":"
        # and is indented more than services_block_indent but not as much as its sub-keys.
        # We establish service_definition_indent with the first such key encountered.
        if (service_definition_indent == -1 && current_line_indent > services_block_indent && line_content ~ /:$/) {
             # This is likely the first service definition, set its indent level
             service_definition_indent = current_line_indent
        }

        # Check if the current line IS a new service definition
        if (current_line_indent == service_definition_indent && line_content ~ /:$/) {
            # Check if it is NOT a sub-key like "ports:", "volumes:" that might be mis-indented to service level
            # This is a weak check; relies on common service key names not overlapping too much.
            # A service like "ports_manager:" would be fine. A service like "ports:" would confuse this.
            # This condition assumes service names don_t typically clash with keywords like "ports", "volumes" etc.
            # and that those keywords are typically more indented under a service.
            
            if (current_service_name_raw != "" && line_content != current_service_name_raw) { # Make sure it is a *new* service
                 print_and_reset_service_info() # Print previous service details
            }
            if (current_service_name_raw == "" || line_content != current_service_name_raw) {
                current_service_name_raw = line_content # e.g., "webapp:"
                current_service_name = line_content     # Store for default container name
                sub(/:$/, "", current_service_name)     # Remove colon for actual name "webapp"
                current_container_name_val = ""         # Reset for new service
                
                # Reset parsing states for sub-elements
                parsing_ports_list = 0
                parsing_volumes_list = 0

                # Define expected indentation for keys (ports, volumes, etc.) under this service
                # Assuming a common indent step (e.g., 2 spaces)
                key_indent = service_definition_indent + 2 # Adjust '2' if your YAML uses different indent steps
                item_indent = key_indent + 2               # Indent for list items like "- port_mapping"
            }
            next # Processed this line as a service name
        }

        # C. Inside a service definition (current_service_name is set)
        if (current_service_name != "") {
            # 1. Check for container_name
            if (current_line_indent == key_indent && line_content ~ /^container_name:/) {
                current_container_name_val = line_content
                sub(/^container_name:[ \t]*/, "", current_container_name_val)
                parsing_ports_list = 0 # container_name ends any active list parsing
                parsing_volumes_list = 0
                next
            }

            # 2. Check for "ports:" keyword
            if (current_line_indent == key_indent && line_content == "ports:") {
                parsing_ports_list = 1
                parsing_volumes_list = 0 # Stop parsing volumes if "ports:" is encountered
                next
            }

            # 3. Check for "volumes:" keyword
            if (current_line_indent == key_indent && line_content == "volumes:") {
                parsing_volumes_list = 1
                parsing_ports_list = 0 # Stop parsing ports if "volumes:" is encountered
                next
            }

            # 4. Collect port list items
            if (parsing_ports_list && current_line_indent == item_indent && line_content ~ /^[ \t]*- /) {
                current_ports[++port_idx] = trim_list_item(line_content)
                next
            }

            # 5. Collect volume list items
            if (parsing_volumes_list && current_line_indent == item_indent && line_content ~ /^[ \t]*- /) {
                current_volumes[++volume_idx] = trim_list_item(line_content)
                next
            }
            
            # 6. If the line is a new key at key_indent level (e.g. "image:", "environment:")
            #    or if indentation changes unexpectedly, it implies the end of any active list.
            if (current_line_indent == key_indent && !(line_content ~ /^[ \t]*- /) ) {
                parsing_ports_list = 0
                parsing_volumes_list = 0
                # This line is some other key; we ignore it for now but it signals end of lists.
                next
            }
            
            # If indentation is less than item_indent but we were parsing a list, the list ends.
            if ((parsing_ports_list || parsing_volumes_list) && current_line_indent < item_indent) {
                 parsing_ports_list = 0
                 parsing_volumes_list = 0
                 # The current line might be a new key_indent key or new service, will be caught in next iteration.
            }
        }
    }
    END {
        print_and_reset_service_info() # Print info for the very last service in the file
    }
    ' "$yaml_file"
}

# --- Example Usage ---
# Create a dummy docker-compose.yml for demonstration
cat > docker-compose-temp.yml << EOL
# This is a global comment
version: '3.9' # version comment

services: # Root services block
  webapp: # Service 1
    image: my_app_image
    container_name: my_web_container # Explicit container name
    # Ports for webapp
    ports:
      - "8080:80"   # Map host 8080 to container 80
      - "443:443" # HTTPS
      # - "1234:1234" # Commented out port
    volumes: # Volumes for webapp
      - ./app_code:/usr/src/app   # Mount local code
      - shared_data:/data        # Named volume
    environment:
      - DEBUG=true

  database: # Service 2 (no explicit container_name)
    image: postgres:14-alpine
    ports:
      - "5432:5432" # Expose PostgreSQL
    volumes:
      - db_data_volume:/var/lib/postgresql/data # Data persistence

  worker:
    # This service has no ports or volumes specified
    image: my_worker_image
    restart: unless-stopped

# Top-level volumes (ignored by this service-focused parser)
volumes:
  shared_data:
  db_data_volume:

EOL

echo "Parsing docker-compose-temp.yml with bash script:"
parse_docker_yaml_bash "docker-compose-temp.yml"

# Clean up dummy file
rm -f "docker-compose-temp.yml"

# To use with your own file:
# parse_docker_yaml_bash "/path/to/your/docker-compose.yml"
