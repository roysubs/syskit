#!/usr/bin/env python3
# Author: Roy Wiseman 2025-02

import yaml
import re
import sys # Import the sys module

def parse_docker_yaml(file_path):
    # ... (your existing parse_docker_yaml function remains the same) ...
    results = []
    try:
        with open(file_path, 'r') as f:
            raw_yaml_content = f.read()

        # Remove comments (text after '#') from each line
        cleaned_yaml_lines = []
        for line in raw_yaml_content.splitlines():
            cleaned_line = line.split('#', 1)[0].rstrip()
            cleaned_yaml_lines.append(cleaned_line)

        # Join the cleaned lines back into a single string,
        # ensuring that empty lines resulting from full-line comments are handled.
        cleaned_yaml = "\n".join(filter(None, cleaned_yaml_lines))

        # Load the cleaned YAML data
        data = yaml.safe_load(cleaned_yaml)

        if not data or 'services' not in data:
            print("No 'services' section found in the YAML file.")
            return results

        for service_name, service_config in data.get('services', {}).items():
            if not isinstance(service_config, dict):
                # Skip if service_config is not a dictionary (e.g., if it's null or malformed)
                print(f"Skipping service '{service_name}' due to unexpected configuration format.")
                continue

            # 1. Find container name
            # If 'container_name' is specified, use it; otherwise, use the service name.
            container_name = service_config.get('container_name', service_name)

            # 2. Find ports
            ports = service_config.get('ports', [])

            # 3. Find mapped volumes
            volumes = service_config.get('volumes', [])

            results.append({
                'service_name': service_name, # Keep track of the original service name
                'container_name': container_name,
                'ports': ports if ports else [], # Ensure it's a list
                'volumes': volumes if volumes else [] # Ensure it's a list
            })

    except FileNotFoundError:
        print(f"Error: File not found at '{file_path}'")
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
    return results

if __name__ == '__main__':
    if len(sys.argv) > 1:
        file_to_parse = sys.argv[1] # Get the filename from the first command-line argument
    else:
        # Fallback or error if no argument is provided
        print("Usage: ./get-docker-compose-params.py <path_to_docker_compose_file>")
        # Optionally, create and parse the dummy file as a default behavior
        # print("\nNo input file specified. Attempting to parse 'docker-compose-example.yml' as a fallback...\n")
        # dummy_docker_compose_content = """
# version: '3.8' # This is a version comment
#
# services:
#   webapp:
#     image: my_custom_app_image
#     container_name: my_web_container # Explicit container name
#     ports:
#       - "8080:80"    # Map host port 8080 to container port 80
#       - "443:443"
#     # - "1234:1234" # This port is commented out
#     volumes:
#       - ./app_data:/usr/src/app    # Mount local directory
#       - named_volume:/data         # Mount a named volume
#     # environment:
#     #   - DEBUG=true
#
#   database: # This service uses its name as the container name
#     image: postgres:15
#     # container_name: my_db_container # Commented out container name
#     ports:
#       - "5432:5432"
#     volumes:
#       - db_storage:/var/lib/postgresql/data # Another named volume
#       - ./init.sql:/docker-entrypoint-initdb.d/init.sql # A file mount
#
#   redis_cache:
#     image: redis:alpine
#     # No explicit container_name, no ports, no volumes defined here for this example
#     # But the script should handle this gracefully
#
#   service_with_no_details: # A service that might have null or missing port/volume sections
#
# volumes: # Top-level volumes declaration (ignored by this parser for specific container details)
#   named_volume:
#   db_storage:
# """
#         dummy_file_path = "docker-compose-example.yml"
#         with open(dummy_file_path, "w") as f:
#             f.write(dummy_docker_compose_content)
#         file_to_parse = dummy_file_path
        sys.exit(1) # Exit if no file is provided and you don't want a default

    print(f"Attempting to parse '{file_to_parse}'...\n")
    parsed_services = parse_docker_yaml(file_to_parse)

    if parsed_services:
        print("--- Extracted Docker Compose Information ---")
        for service_info in parsed_services:
            print(f"\nService: {service_info['service_name']}")
            print(f"  Container Name: {service_info['container_name']}")

            print("  Ports:")
            if service_info['ports']:
                for port_mapping in service_info['ports']:
                    print(f"    - {port_mapping}")
            else:
                print("    - None specified")

            print("  Volumes:")
            if service_info['volumes']:
                for volume_mapping in service_info['volumes']:
                    print(f"    - {volume_mapping}")
            else:
                print("    - None specified")
    else:
        print("\nNo service information could be extracted or an error occurred.")

    # Example of how to use it with a non-existent file:
    # print("\nAttempting to parse a non-existent file:")
    # parse_docker_yaml("non_existent_file.yml")
