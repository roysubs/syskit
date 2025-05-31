#!/bin/bash
# Author: Roy Wiseman 2025-02

RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\033[0m'

# Check if docker is installed:
if [ -f "docker-setup-deb-variants.sh" ]; then "./docker-setup-deb-variants.sh"; fi

set -e # Exit immediately if a command exits with a non-zero status.

echo -e "${BOLD}${BLUE}=====================================================${NC}"
echo -e "${BOLD}${BLUE}    Docker Linux Distribution Container Launcher${NC}"
echo -e "${BOLD}${BLUE}=====================================================${NC}"
echo

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Installing...${NC}"
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo -e "${GREEN}Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'.${NC}"
        exit 1
    else
        echo -e "${RED}❌ Failed to install Docker.${NC}"
        exit 1
    fi
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    exit 1
fi

# Define available distributions
declare -A DISTROS
DISTROS[1]="debian:latest|Debian (Latest Stable)|debian"
DISTROS[2]="ubuntu:latest|Ubuntu (Latest LTS)|ubuntu"
DISTROS[3]="linuxmintd/mint20-amd64|Linux Mint 20|mint"
DISTROS[4]="alpine:latest|Alpine Linux (Latest)|alpine"
DISTROS[5]="archlinux:latest|Arch Linux (Latest)|arch"
DISTROS[6]="fedora:latest|Fedora (Latest)|fedora"
DISTROS[7]="centos:centos7|CentOS 7|centos7"
DISTROS[8]="almalinux:latest|AlmaLinux (CentOS successor)|almalinux"
DISTROS[9]="rockylinux:latest|Rocky Linux (CentOS successor)|rocky"
DISTROS[10]="opensuse/leap:latest|openSUSE Leap|opensuse-leap"
DISTROS[11]="opensuse/tumbleweed:latest|openSUSE Tumbleweed (Rolling)|opensuse-tumbleweed"
DISTROS[12]="kalilinux/kali-rolling:latest|Kali Linux (Rolling)|kali"
DISTROS[13]="parrotsec/parrot-core:latest|Parrot Security OS|parrot"
DISTROS[14]="clearlinux:latest|Clear Linux (Intel)|clearlinux"
DISTROS[15]="voidlinux/voidlinux:latest|Void Linux|void"
DISTROS[16]="gentoo/stage3:latest|Gentoo Linux|gentoo"
DISTROS[17]="vbatts/slackware:latest|Slackware Linux|slackware"

# Function to display menu
show_menu() {
    echo -e "${BOLD}${CYAN}Available Linux Distributions:${NC}"
    echo
    for i in $(seq 1 ${#DISTROS[@]}); do
        if [[ -n "${DISTROS[$i]}" ]]; then
            IFS='|' read -ra DISTRO_INFO <<< "${DISTROS[$i]}"
            printf "%2d) ${GREEN}%-25s${NC} (${DISTRO_INFO[0]})\n" "$i" "${DISTRO_INFO[1]}"
        fi
    done
    echo
    echo -e "${YELLOW}Note: Some distributions may require special handling or may not be available on all architectures.${NC}"
    echo -e "${YELLOW}macOS containers are not available as Apple doesn't permit virtualization of macOS on non-Apple hardware.${NC}"
    echo -e "${YELLOW}FreeBSD containers are limited - consider using a FreeBSD VM instead for full compatibility.${NC}"
    echo
}

# Function to show container management commands
show_container_management_commands() {
    local container_name="$1"
    local image="$2"
    
    echo -e "${BOLD}${CYAN}Container Management Commands:${NC}"
    echo
    echo -e "${BOLD}Re-entering Container:${NC}"
    echo -e "  Restart and attach:     ${GREEN}docker start -ai ${container_name}${NC}"
    echo -e "  Execute new shell:      ${GREEN}docker exec -it ${container_name} /bin/bash${NC}"
    echo -e "  Execute single command: ${GREEN}docker exec ${container_name} <command>${NC}"
    echo -e "    Example:              ${GREEN}docker exec ${container_name} ls -la /${NC}"
    echo
    echo -e "${BOLD}Container Information:${NC}"
    echo -e "  View container details: ${GREEN}docker inspect ${container_name}${NC}"
    echo -e "  View container logs:    ${GREEN}docker logs ${container_name}${NC}"
    echo -e "  View all containers:    ${GREEN}docker ps -a${NC}"
    echo -e "  View running containers: ${GREEN}docker ps${NC}"
    echo
    echo -e "${BOLD}Container Cleanup:${NC}"
    echo -e "  Remove this container:  ${GREEN}docker rm ${container_name}${NC}"
    echo -e "  Remove running container: ${GREEN}docker rm -f ${container_name}${NC}"
    echo -e "  Remove unused containers: ${GREEN}docker container prune${NC}"
    echo
    echo -e "${BOLD}Image Management:${NC}"
    echo -e "  Remove this image:      ${GREEN}docker rmi ${image}${NC}"
    echo -e "  Remove unused images:   ${GREEN}docker image prune${NC}"
    echo -e "  Remove all unused data: ${GREEN}docker system prune${NC}"
    echo -e "  Nuclear option (all):   ${GREEN}docker system prune -a${NC}"
    echo
}
get_container_name() {
    local distro_name="$1"
    echo "distro-${distro_name}"
}

# Function to check if container name exists
container_exists() {
    local container_name="$1"
    docker ps -a --format '{{.Names}}' | grep -wq "$container_name"
}

# Function to pull and run container
run_distro_container() {
    local image="$1"
    local distro_name="$2"
    local container_name
    
    container_name=$(get_container_name "$distro_name")
    
    echo -e "${CYAN}🔍 Checking if container '${container_name}' already exists...${NC}"
    if container_exists "$container_name"; then
        echo -e "${YELLOW}✅ Container '${container_name}' already exists. Connecting to existing container...${NC}"
        
        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -wq "$container_name"; then
            echo -e "${GREEN}Container is running. Executing: docker exec -it ${container_name} /bin/bash${NC}"
            docker exec -it "$container_name" /bin/bash
        else
            echo -e "${GREEN}Container is stopped. Executing: docker start -ai ${container_name}${NC}"
            docker start -ai "$container_name"
        fi
        
        echo
        echo -e "${GREEN}✅ Container session ended.${NC}"
        echo -e "${YELLOW}Container '${container_name}' is stopped but still exists.${NC}"
        show_container_management_commands "$container_name" "$image"
        return 0
    fi
    
    echo -e "${CYAN}📥 Pulling image: ${image}...${NC}"
    if ! docker pull "$image"; then
        echo -e "${RED}❌ Failed to pull image: ${image}${NC}"
        echo -e "${YELLOW}This image may not be available for your architecture or may have been moved/renamed.${NC}"
        return 1
    fi
    
    echo -e "${CYAN}🚀 Creating and starting new container: ${container_name}...${NC}"
    
    # Different run commands based on distro
    local docker_cmd
    case "$distro_name" in
        "alpine")
            docker_cmd="docker run -it --name ${container_name} ${image} /bin/sh"
            ;;
        "arch")
            docker_cmd="docker run -it --name ${container_name} ${image} /bin/bash"
            ;;
        "kali"|"parrot")
            docker_cmd="docker run -it --name ${container_name} --cap-add=NET_ADMIN ${image} /bin/bash"
            ;;
        "slackware")
            docker_cmd="docker run -it --name ${container_name} ${image} /bin/bash"
            ;;
        "opensuse-leap"|"opensuse-tumbleweed")
            docker_cmd="docker run -it --name ${container_name} ${image} /bin/bash"
            ;;
        *)
            docker_cmd="docker run -it --name ${container_name} ${image} /bin/bash"
            ;;
    esac
    
    echo -e "${GREEN}Executing: ${docker_cmd}${NC}"
    eval "$docker_cmd"
    
    echo
    echo -e "${GREEN}✅ Container session ended.${NC}"
    echo -e "${YELLOW}Container '${container_name}' is now stopped but still exists.${NC}"
    echo
    show_container_management_commands "$container_name" "$image"
}

# Function to handle special distributions
handle_special_distros() {
    echo -e "${YELLOW}⚠️  Some distributions require special notes:${NC}"
    echo
    echo -e "${BOLD}Mint:${NC} Limited official container support. Using community image."
    echo -e "${BOLD}MX Linux:${NC} No official container images available."
    echo -e "${BOLD}Manjaro:${NC} No official container images available (Arch-based)."
    echo -e "${BOLD}Pop!_OS:${NC} No official container images available (Ubuntu-based)."
    echo -e "${BOLD}Elementary OS:${NC} No official container images available (Ubuntu-based)."
    echo -e "${BOLD}Zorin OS:${NC} No official container images available (Ubuntu-based)."
    echo -e "${BOLD}FreeBSD:${NC} Limited Linux container support. Consider VM instead."
    echo -e "${BOLD}macOS:${NC} Not available due to Apple licensing restrictions."
    echo
    echo -e "${CYAN}For missing distributions, consider:${NC}"
    echo -e "  • Using their base distribution (e.g., Ubuntu for Pop!_OS/Zorin OS)"
    echo -e "  • Setting up a full VM for complete compatibility"
    echo -e "  • Building custom Docker images from their installation ISOs"
    echo
}

# Main script logic
main() {
    echo -e "${GREEN}Welcome to the Docker Linux Distribution Container Launcher!${NC}"
    echo -e "This script helps you quickly spin up different Linux distributions as containers for testing."
    echo
    
    while true; do
        show_menu
        
        read -p "Select a distribution (1-${#DISTROS[@]}) or 'q' to quit: " choice
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            echo -e "${GREEN}Thanks for using the Docker Distro Container Launcher!${NC}"
            exit 0
        fi
        
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#DISTROS[@]} ]]; then
            echo -e "${RED}❌ Invalid selection. Please enter a number between 1 and ${#DISTROS[@]}.${NC}"
            echo
            continue
        fi
        
        if [[ -z "${DISTROS[$choice]}" ]]; then
            echo -e "${RED}❌ Invalid selection.${NC}"
            echo
            continue
        fi
        
        IFS='|' read -ra DISTRO_INFO <<< "${DISTROS[$choice]}"
        image="${DISTRO_INFO[0]}"
        description="${DISTRO_INFO[1]}"
        distro_name="${DISTRO_INFO[2]}"
        
        echo
        echo -e "${BOLD}Selected: ${GREEN}${description}${NC}"
        echo -e "Image: ${CYAN}${image}${NC}"
        echo
        
        read -p "Continue with this selection? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo
            continue
        fi
        
        echo
        run_distro_container "$image" "$distro_name"
        
        echo
        read -p "Would you like to launch another container? (Y/n): " another
        if [[ "$another" =~ ^[Nn]$ ]]; then
            echo -e "${GREEN}Thanks for using the Docker Distro Container Launcher!${NC}"
            exit 0
        fi
        
        echo
    done
}

# Show special distro info if requested
if [[ "$1" == "--info" || "$1" == "-i" ]]; then
    handle_special_distros
    exit 0
fi

# Run main function
main
