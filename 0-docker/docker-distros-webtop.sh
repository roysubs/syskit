#!/bin/bash
# Author: Roy Wiseman 2025-03

RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\033[0m' # No Color

LSIO_WEBTOP_IMAGE="lscr.io/linuxserver/webtop"

# Check if docker is installed:
# If you have a custom script for this, ensure it's executable and in PATH or current dir.
# if [ -f "./docker-setup-deb-variants.sh" ]; then "./docker-setup-deb-variants.sh"; fi

set -e # Exit immediately if a command exits with a non-zero status.

echo -e "${BOLD}${BLUE}=====================================================${NC}"
echo -e "${BOLD}${BLUE}     Linuxserver.io Webtop Container Launcher      ${NC}"
echo -e "${BOLD}${BLUE}=====================================================${NC}"
echo

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
    echo -e "${YELLOW}You can try: curl -fsSL https://get.docker.com | sh${NC}"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    # Attempt to start Docker if systemd is present
    if command -v systemctl &> /dev/null && systemctl is-active docker --quiet; then
        echo -e "${YELLOW}Attempting to start Docker service...${NC}"
        sudo systemctl start docker
        sleep 3
        if ! docker info &>/dev/null; then
            echo -e "${RED}❌ Failed to start Docker daemon.${NC}"
            exit 1
        fi
        echo -e "${GREEN}Docker daemon started successfully.${NC}"
    else
        exit 1
    fi
fi

# Define available webtop flavors
# Format: "ImageTag|Description|ContainerNameSuffix|UserFriendlyDistro|UserFriendlyDE"
declare -A WEBTOP_FLAVORS
WEBTOP_FLAVORS[1]="latest|Alpine XFCE (Default)|alpine-xfce|Alpine|XFCE"
WEBTOP_FLAVORS[2]="alpine-kde|Alpine KDE|alpine-kde|Alpine|KDE"
WEBTOP_FLAVORS[3]="alpine-mate|Alpine MATE|alpine-mate|Alpine|MATE"
WEBTOP_FLAVORS[4]="alpine-i3|Alpine i3|alpine-i3|Alpine|i3"
WEBTOP_FLAVORS[5]="alpine-openbox|Alpine Openbox|alpine-openbox|Alpine|Openbox"
WEBTOP_FLAVORS[6]="alpine-icewm|Alpine IceWM|alpine-icewm|Alpine|IceWM"

WEBTOP_FLAVORS[7]="ubuntu-xfce|Ubuntu XFCE|ubuntu-xfce|Ubuntu|XFCE"
WEBTOP_FLAVORS[8]="ubuntu-kde|Ubuntu KDE|ubuntu-kde|Ubuntu|KDE"
WEBTOP_FLAVORS[9]="ubuntu-mate|Ubuntu MATE|ubuntu-mate|Ubuntu|MATE"
WEBTOP_FLAVORS[10]="ubuntu-i3|Ubuntu i3|ubuntu-i3|Ubuntu|i3"
WEBTOP_FLAVORS[11]="ubuntu-openbox|Ubuntu Openbox|ubuntu-openbox|Ubuntu|Openbox"
WEBTOP_FLAVORS[12]="ubuntu-icewm|Ubuntu IceWM|ubuntu-icewm|Ubuntu|IceWM"

WEBTOP_FLAVORS[13]="fedora-xfce|Fedora XFCE|fedora-xfce|Fedora|XFCE"
WEBTOP_FLAVORS[14]="fedora-kde|Fedora KDE|fedora-kde|Fedora|KDE"
WEBTOP_FLAVORS[15]="fedora-mate|Fedora MATE|fedora-mate|Fedora|MATE"
WEBTOP_FLAVORS[16]="fedora-i3|Fedora i3|fedora-i3|Fedora|i3"
WEBTOP_FLAVORS[17]="fedora-openbox|Fedora Openbox|fedora-openbox|Fedora|Openbox"
WEBTOP_FLAVORS[18]="fedora-icewm|Fedora IceWM|fedora-icewm|Fedora|IceWM"

WEBTOP_FLAVORS[19]="arch-xfce|Arch XFCE|arch-xfce|Arch Linux|XFCE"
WEBTOP_FLAVORS[20]="arch-kde|Arch KDE|arch-kde|Arch Linux|KDE"
WEBTOP_FLAVORS[21]="arch-mate|Arch MATE|arch-mate|Arch Linux|MATE"
WEBTOP_FLAVORS[22]="arch-i3|Arch i3|arch-i3|Arch Linux|i3"
WEBTOP_FLAVORS[23]="arch-openbox|Arch Openbox|arch-openbox|Arch Linux|Openbox"
WEBTOP_FLAVORS[24]="arch-icewm|Arch IceWM|arch-icewm|Arch Linux|IceWM"

WEBTOP_FLAVORS[25]="debian-xfce|Debian XFCE|debian-xfce|Debian|XFCE"
WEBTOP_FLAVORS[26]="debian-kde|Debian KDE|debian-kde|Debian|KDE"
WEBTOP_FLAVORS[27]="debian-mate|Debian MATE|debian-mate|Debian|MATE"
WEBTOP_FLAVORS[28]="debian-i3|Debian i3|debian-i3|Debian|i3"
WEBTOP_FLAVORS[29]="debian-openbox|Debian Openbox|debian-openbox|Debian|Openbox"
WEBTOP_FLAVORS[30]="debian-icewm|Debian IceWM|debian-icewm|Debian|IceWM"

# Function to display menu
show_menu() {
    echo -e "${BOLD}${CYAN}Available Linuxserver.io Webtop Flavors:${NC}"
    echo
    for i in $(seq 1 ${#WEBTOP_FLAVORS[@]}); do
        if [[ -n "${WEBTOP_FLAVORS[$i]}" ]]; then
            IFS='|' read -ra FLAVOR_INFO <<< "${WEBTOP_FLAVORS[$i]}"
            printf "%2d) ${GREEN}%-25s${NC} (Image Tag: ${LSIO_WEBTOP_IMAGE}:${FLAVOR_INFO[0]})\n" "$i" "${FLAVOR_INFO[1]}"
        fi
    done
    echo
    echo -e "${YELLOW}Note: Ensure your system architecture (amd64, arm64) is supported by the chosen image.${NC}"
    echo -e "${YELLOW}The script will use general tags; Docker should pick the correct architecture.${NC}"
    echo
}

# Function to check if a port is in use
# Uses ss if available (preferred), otherwise falls back to netstat
# Returns 0 if port is in use, 1 if free
check_port() {
    local port_to_check=$1
    local tool_output
    if command -v ss &> /dev/null; then
        tool_output=$(ss -tulnp 2>/dev/null)
    elif command -v netstat &> /dev/null; then
        tool_output=$(netstat -tulnp 2>/dev/null)
    else
        echo -e "${YELLOW}⚠️  Cannot check port availability: neither 'ss' nor 'netstat' command found. Assuming port is free.${NC}"
        return 1 # Assume free if tools are missing
    fi

    if echo "$tool_output" | grep -q ":${port_to_check}[[:space:]]"; then
        return 0 # Port is in use
    else
        return 1 # Port is free
    fi
}


# Function to show container management commands
show_container_management_commands() {
    local container_name="$1"
    local image_tag="$2"
    local http_port="$3"
    local https_port="$4"

    echo -e "${BOLD}${CYAN}Container Management for '${container_name}':${NC}"
    echo
    echo -e "${BOLD}Access Webtop:${NC}"
    echo -e "  HTTP:  ${GREEN}http://$(hostname -I | awk '{print $1}'):${http_port}${NC}"
    echo -e "  HTTPS: ${GREEN}https://$(hostname -I | awk '{print $1}'):${https_port}${NC} (self-signed certificate)"
    echo
    echo -e "${BOLD}Shell Access (for debugging/management):${NC}"
    echo -e "  Execute new shell:    ${GREEN}docker exec -it ${container_name} /bin/bash${NC}"
    echo
    echo -e "${BOLD}Container Logs:${NC}"
    echo -e "  View live logs:       ${GREEN}docker logs -f ${container_name}${NC}"
    echo
    echo -e "${BOLD}Container Control:${NC}"
    echo -e "  Stop container:       ${GREEN}docker stop ${container_name}${NC}"
    echo -e "  Start container:      ${GREEN}docker start ${container_name}${NC}"
    echo -e "  Restart container:    ${GREEN}docker restart ${container_name}${NC}"
    echo
    echo -e "${BOLD}Container Information:${NC}"
    echo -e "  View container details: ${GREEN}docker inspect ${container_name}${NC}"
    echo -e "  View all containers:    ${GREEN}docker ps -a${NC}"
    echo -e "  View running containers:${GREEN}docker ps${NC}"
    echo
    echo -e "${BOLD}Container Cleanup:${NC}"
    echo -e "  Remove this container (must be stopped): ${GREEN}docker rm ${container_name}${NC}"
    echo -e "  Force remove running container:          ${GREEN}docker rm -f ${container_name}${NC}"
    echo -e "  Remove unused containers:                ${GREEN}docker container prune${NC}"
    echo
    echo -e "${BOLD}Image Management:${NC}"
    echo -e "  Remove webtop image:    ${GREEN}docker rmi ${LSIO_WEBTOP_IMAGE}:${image_tag}${NC}"
    echo -e "  Remove unused images:   ${GREEN}docker image prune${NC}"
    echo -e "  Remove all unused data: ${GREEN}docker system prune${NC} (Caution!)"
    echo -e "  Nuclear option (all):   ${GREEN}docker system prune -a${NC} (Extreme Caution!)"
    echo
}

get_container_name() {
    local suffix="$1"
    echo "webtop-${suffix}"
}

# Function to check if container name exists
container_exists() {
    local container_name="$1"
    docker ps -a --format '{{.Names}}' | grep -Eq "^${container_name}$"
}

# Function to pull and run container
run_webtop_container() {
    local image_tag="$1"
    local container_suffix="$2"
    local full_image_name="${LSIO_WEBTOP_IMAGE}:${image_tag}"
    local container_name

    container_name=$(get_container_name "$container_suffix")

    echo -e "${CYAN}🔍 Checking if container '${container_name}' already exists...${NC}"
    if container_exists "$container_name"; then
        echo -e "${YELLOW}⚠️ Container '${container_name}' already exists.${NC}"
        local existing_http_port=$(docker port "$container_name" 3000/tcp | cut -d: -f2)
        local existing_https_port=$(docker port "$container_name" 3001/tcp | cut -d: -f2)

        if [[ -z "$existing_http_port" ]]; then # Might be stopped or ports not mapped as expected
            existing_http_port="<not found>"
            existing_https_port="<not found>"
        fi

        echo -e "It might be accessible at: HTTP on port ${existing_http_port}, HTTPS on port ${existing_https_port}"
        read -p "Stop and remove existing container to create a new one? (y/N): " replace_existing
        if [[ "$replace_existing" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Stopping and removing existing container '${container_name}'...${NC}"
            docker stop "$container_name" >/dev/null 2>&1 || true
            docker rm "$container_name" >/dev/null 2>&1 || true
            echo -e "${GREEN}Existing container removed.${NC}"
        else
            echo -e "${YELLOW}Skipping new container creation.${NC}"
            show_container_management_commands "$container_name" "$image_tag" "$existing_http_port" "$existing_https_port"
            return 0
        fi
    fi

    echo
    echo -e "${BOLD}${CYAN}--- Container Configuration ---${NC}"

    # Get PUID/PGID
    default_puid=$(id -u)
    default_pgid=$(id -g)
    read -p "Enter PUID [default: ${default_puid}]: " puid
    puid=${puid:-$default_puid}
    read -p "Enter PGID [default: ${default_pgid}]: " pgid
    pgid=${pgid:-$default_pgid}

    # Get Timezone
    default_tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "Etc/UTC")
    read -p "Enter Timezone (e.g., America/New_York, Europe/London) [default: ${default_tz}]: " tz
    tz=${tz:-$default_tz}

    # Get Host Ports
    local host_http_port
    local host_https_port
    while true; do
        read -p "Enter host port for HTTP (e.g., 3000) [default: 3000]: " host_http_port
        host_http_port=${host_http_port:-3000}
        if [[ ! "$host_http_port" =~ ^[0-9]+$ ]] || [ "$host_http_port" -lt 1024 ] || [ "$host_http_port" -gt 65534 ]; then
            echo -e "${RED}Invalid port. Please enter a number between 1024 and 65534.${NC}"
            continue
        fi
        host_https_port=$((host_http_port + 1))

        port_free_http=1
        port_free_https=1

        echo -e "${CYAN}Checking port ${host_http_port} (HTTP)...${NC}"
        if check_port "$host_http_port"; then
            echo -e "${YELLOW}⚠️ Port ${host_http_port} (for HTTP) appears to be in use.${NC}"
            port_free_http=0
        else
            echo -e "${GREEN}✅ Port ${host_http_port} (for HTTP) appears to be free.${NC}"
        fi

        echo -e "${CYAN}Checking port ${host_https_port} (HTTPS)...${NC}"
        if check_port "$host_https_port"; then
            echo -e "${YELLOW}⚠️ Port ${host_https_port} (for HTTPS) appears to be in use.${NC}"
            port_free_https=0
        else
            echo -e "${GREEN}✅ Port ${host_https_port} (for HTTPS) appears to be free.${NC}"
        fi

        if [[ "$port_free_http" -eq 1 && "$port_free_https" -eq 1 ]]; then
            echo -e "${GREEN}Ports ${host_http_port} (HTTP) and ${host_https_port} (HTTPS) are available.${NC}"
            break
        else
            read -p "One or both ports are in use. Try different starting port? (Y/n): " try_again_port
            if [[ "$try_again_port" =~ ^[Nn]$ ]]; then
                echo -e "${RED}❌ Cannot proceed without available ports. Aborting container setup.${NC}"
                return 1
            fi
        fi
    done

    # Get Volume Path
    local host_volume_path
    local default_volume_path="$HOME/.config/webtop/${container_suffix}"
    while true; do
        read -e -p "Enter host path for /config volume [default: ${default_volume_path}]: " host_volume_path
        host_volume_path=${host_volume_path:-$default_volume_path}
        
        # Expand tilde
        host_volume_path_expanded="${host_volume_path/#\~/$HOME}"

        if [ -z "$host_volume_path_expanded" ]; then
            echo -e "${RED}Volume path cannot be empty.${NC}"
            continue
        fi

        if [ ! -d "$host_volume_path_expanded" ]; then
            echo -e "${YELLOW}Directory '${host_volume_path_expanded}' does not exist.${NC}"
            read -p "Create it? (Y/n): " create_dir
            if [[ "$create_dir" =~ ^[Nn]$ ]]; then
                echo -e "${YELLOW}Please create the directory or choose an existing one.${NC}"
                continue
            else
                if sudo mkdir -p "$host_volume_path_expanded" && sudo chown "${puid}:${pgid}" "$host_volume_path_expanded"; then
                    echo -e "${GREEN}Directory '$host_volume_path_expanded' created and permissions set for PUID/PGID.${NC}"
                else
                    echo -e "${RED}❌ Failed to create directory '$host_volume_path_expanded' or set permissions. Please check permissions or create it manually with correct ownership.${NC}"
                    echo -e "${YELLOW}Try: mkdir -p \"${host_volume_path_expanded}\" && sudo chown ${puid}:${pgid} \"${host_volume_path_expanded}\"${NC}"
                    continue
                fi
            fi
        elif ! [ -w "$host_volume_path_expanded" ] || ! [ -r "$host_volume_path_expanded" ] ; then
             echo -e "${YELLOW}Warning: Current user may not have read/write permissions for $host_volume_path_expanded.${NC}"
             echo -e "${YELLOW}Ensure the directory is owned by PUID ${puid} and PGID ${pgid} on the host for proper functioning.${NC}"
             read -p "Continue anyway? (y/N): " perm_continue
             if [[ ! "$perm_continue" =~ ^[Yy]$ ]]; then
                 continue
             fi
        fi
        break
    done
    
    # Optional Docker parameters
    local security_opt_seccomp=""
    read -p "Enable --security-opt seccomp=unconfined (recommended for some apps, older hosts)? (Y/n): " enable_seccomp
    if [[ ! "$enable_seccomp" =~ ^[Nn]$ ]]; then
        security_opt_seccomp="--security-opt seccomp=unconfined"
        echo -e "${GREEN}Seccomp unconfined will be enabled.${NC}"
    else
        echo -e "${YELLOW}Seccomp unconfined will NOT be enabled.${NC}"
    fi

    local shm_size_opt=""
    read -p "Set --shm-size=\"1gb\" (recommended to prevent browser crashes)? (Y/n): " enable_shm
    if [[ ! "$enable_shm" =~ ^[Nn]$ ]]; then
        shm_size_opt="--shm-size=\"1gb\""
        echo -e "${GREEN}SHM size will be set to 1GB.${NC}"
    else
        echo -e "${YELLOW}SHM size will NOT be explicitly set.${NC}"
    fi

    local dri_device_opt=""
    if [ -d "/dev/dri" ]; then
        read -p "Enable GPU acceleration by mapping /dev/dri (Linux hosts, Open Source drivers only)? (Y/n): " enable_dri
        if [[ ! "$enable_dri" =~ ^[Nn]$ ]]; then
            dri_device_opt="--device /dev/dri:/dev/dri"
            echo -e "${GREEN}DRI device will be mapped for GPU acceleration.${NC}"
        else
            echo -e "${YELLOW}DRI device will NOT be mapped.${NC}"
        fi
    else
        echo -e "${YELLOW}/dev/dri not found on host, skipping GPU acceleration option.${NC}"
    fi

    echo
    echo -e "${CYAN}📥 Pulling image: ${full_image_name}... (This may take a while)${NC}"
    if ! docker pull "$full_image_name"; then
        echo -e "${RED}❌ Failed to pull image: ${full_image_name}${NC}"
        echo -e "${YELLOW}This image may not be available for your architecture or may have been moved/renamed.${NC}"
        return 1
    fi

    echo -e "${CYAN}🚀 Creating and starting new container: ${container_name}...${NC}"

    # Construct docker command
    local docker_cmd
    docker_cmd="docker run -d \\
  --name=\"${container_name}\" \\
  ${security_opt_seccomp} \\
  -e PUID=${puid} \\
  -e PGID=${pgid} \\
  -e TZ=\"${tz}\" \\
  -p ${host_http_port}:3000 \\
  -p ${host_https_port}:3001 \\
  -v \"${host_volume_path_expanded}:/config\" \\
  ${dri_device_opt} \\
  ${shm_size_opt} \\
  --restart unless-stopped \\
  ${full_image_name}"

    echo -e "${BOLD}${YELLOW}The following command will be executed:${NC}"
    echo -e "${CYAN}${docker_cmd}${NC}"
    echo

    read -p "Proceed with container creation? (Y/n): " confirm_run
    if [[ "$confirm_run" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Container creation aborted by user.${NC}"
        return 1
    fi

    # Execute the command
    # Use eval to correctly interpret quotes and parameters like shm_size
    if eval "$docker_cmd"; then
        echo
        echo -e "${GREEN}✅ Container '${container_name}' started successfully!${NC}"
        echo -e "${YELLOW}It might take a minute for the webtop interface to be fully available.${NC}"
        echo
        show_container_management_commands "$container_name" "$image_tag" "$host_http_port" "$host_https_port"
    else
        echo -e "${RED}❌ Failed to start container '${container_name}'.${NC}"
        echo -e "${YELLOW}Check Docker logs for more details: docker logs ${container_name}${NC}"
        return 1
    fi
}

# Main script logic
main() {
    echo -e "${GREEN}Welcome to the Linuxserver.io Webtop Container Launcher!${NC}"
    echo -e "This script helps you quickly spin up a Webtop environment in Docker."
    echo

    while true; do
        show_menu

        local choice
        read -p "Select a Webtop flavor (1-${#WEBTOP_FLAVORS[@]}) or 'q' to quit: " choice

        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            echo -e "${GREEN}👋 Thanks for using the Webtop Container Launcher!${NC}"
            exit 0
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#WEBTOP_FLAVORS[@]} ]]; then
            echo -e "${RED}❌ Invalid selection. Please enter a number between 1 and ${#WEBTOP_FLAVORS[@]}.${NC}"
            echo
            continue
        fi

        if [[ -z "${WEBTOP_FLAVORS[$choice]}" ]]; then # Should not happen with the check above, but good practice
            echo -e "${RED}❌ Invalid selection number.${NC}"
            echo
            continue
        fi

        IFS='|' read -ra FLAVOR_INFO <<< "${WEBTOP_FLAVORS[$choice]}"
        local image_tag="${FLAVOR_INFO[0]}"
        local description="${FLAVOR_INFO[1]}"
        local container_suffix="${FLAVOR_INFO[2]}" # e.g., alpine-xfce

        echo
        echo -e "${BOLD}Selected: ${GREEN}${description}${NC}"
        echo -e "Image: ${CYAN}${LSIO_WEBTOP_IMAGE}:${image_tag}${NC}"
        echo

        read -p "Continue with this selection? (Y/n): " confirm_selection
        if [[ "$confirm_selection" =~ ^[Nn]$ ]]; then
            echo
            continue
        fi

        echo
        if run_webtop_container "$image_tag" "$container_suffix"; then
             echo -e "${GREEN}🎉 Webtop setup process completed.${NC}"
        else
             echo -e "${RED}❗ Webtop setup process encountered an error or was aborted.${NC}"
        fi


        echo
        # read -p "Would you like to launch another Webtop container? (y/N): " another
        # if [[ ! "$another" =~ ^[Yy]$ ]]; then
        #     echo -e "${GREEN}👋 Thanks for using the Webtop Container Launcher!${NC}"
        #     exit 0
        # fi
        # echo
        exit 0
    done
}

# Run main function
main
