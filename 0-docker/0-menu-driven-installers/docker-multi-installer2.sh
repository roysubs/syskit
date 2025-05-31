#!/bin/bash
# Author: Roy Wiseman 2025-03

# --- Color Definitions ---
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m' # Bright White
B_YELLOW='\033[1;33m'
B_GREEN='\033[1;32m'
B_RED='\033[1;31m'

# --- Symbols ---
ERROR_X="${B_RED}❌${NC}"

# --- Application Data Array ---
# Format: appname:host_port:category:description
# Note: 'host_port' is the desired host port for the main web UI.
# The install function for each app must know its internal container port.

declare -a apps_data=(
    # Media Suite: Servers, Players, Downloaders & Management
    "plex:32400:Media Suite:A popular media server for organizing and streaming your personal video, music, and photo collections."
    "jellyfin:8096:Media Suite:A Free Software Media System that puts you in control of managing and streaming your media."
    "emby:8097:Media Suite:A media server for organizing, playing, and streaming audio and video to a variety of devices."
    "sonarr:8989:Media Suite:A PVR for Usenet and BitTorrent users that monitors multiple RSS feeds for new episodes of your favorite shows."
    "radarr:7878:Media Suite:An independent fork of Sonarr reworked for automatically downloading movies via Usenet and BitTorrent."
    "lidarr:8686:Media Suite:Looks and smells like Sonarr but made for music."
    "readarr:8787:Media Suite:A fork of Sonarr/Radarr for books, magazines, and comics."
    "bazarr:6767:Media Suite:A companion application to Sonarr and Radarr for managing and downloading subtitles."
    "transmission:9091:Media Suite:A fast, easy, and free BitTorrent client with a web UI."
    "sabnzbd:8080:Media Suite:An Open Source Binary Newsreader written in Python."
    "jackett:9117:Media Suite:API Support for your favorite torrent trackers. It works as a proxy server."
    "tautulli:8181:Media Suite:A Python based monitoring and tracking tool for Plex Media Server."
    "calibre-web:8083:Media Suite:Web app for Browse, reading and downloading eBooks stored in a Calibre database."
    "kavita:5000:Media Suite:A blazingly fast, cross-platform, and open source self-hosted digital library for comics, manga, and books."
    "audiobookshelf:13378:Media Suite:Self-hosted audiobook and podcast server."
    # "volumio:8088:Media Suite:A free and Open Source music player (often on port 80, using 8088 to avoid common conflicts)." # Volumio is more complex for generic Docker

    # Photo & Video Management
    "photoprism:2342:Photo & Video Management:A privately hosted app for Browse, organizing, and sharing your personal photo collection."
    "immich:2283:Photo & Video Management:A self-hosted photo and video backup solution directly from your mobile phone." # Immich uses docker-compose, complex for single script

    # Network Services & Security
    "nginx-proxy-manager:81:Network Services & Security:Manage Nginx proxy hosts with a simple, powerful interface (admin UI on 81, proxy on 80, 443)."
    "traefik:8081:Network Services & Security:A modern HTTP reverse proxy and load balancer (dashboard on 8080, using 8081; proxy on 80, 443)."
    "authelia:9092:Network Services & Security:An open-source authentication and authorization server providing 2FA and SSO."
    "pi-hole:8082:Network Services & Security:A DNS sinkhole (admin UI on 80, using 8082; DNS on 53)."
    "adguard-home:3000:Network Services & Security:Network-wide software for blocking ads & tracking (admin UI; DNS on 53)."
    "technitium-dns:5380:Network Services & Security:A personal, ad blocking, and recursive DNS server (web UI; DNS on 53)."
    "guacamole:8084:Network Services & Security:A clientless remote desktop gateway."
    "wg-easy:51821:Network Services & Security:Simple web UI for WireGuard VPN (UI often on 80/custom, using 51821 for UI; VPN on 51820/udp)."
    "vaultwarden:8085:Network Services & Security:Unofficial Bitwarden compatible server."

    # System, Container & Database Management
    "portainer:9443:System & Container Management:Lightweight management UI for Docker (can also use 9000 for HTTP)."
    "dozzle:8086:System & Container Management:Real-time Docker container log viewer."
    "webmin:10000:System & Container Management:Web-based interface for system administration."
    "phpmyadmin:8087:System & Container Management:Web interface for MySQL/MariaDB administration."
    "adminer:8089:System & Container Management:Full-featured database management tool in a single PHP file."
    "postgresql:5432:System & Container Management:Powerful, open source object-relational database system (DB port)."
    "mariadb:3306:System & Container Management:Community-developed fork of MySQL (DB port)."
    "redis:6379:System & Container Management:In-memory data structure store (service port)."
    "influxdb:8886:System & Container Management:Time series database (changed from 8086 to avoid dozzle conflict)."

    # Productivity, Utilities & Communication
    "nextcloud:8090:Productivity & Utilities:File hosting, calendar, contacts, and more (AIO image recommended for simplicity)."
    "freshrss:8091:Productivity & Utilities:Free, self-hostable RSS feed aggregator."
    "wallabag:8092:Productivity & Utilities:Self-hostable application for saving web pages."
    "privatebin:8093:Productivity & Utilities:Minimalist, open source online pastebin."
    "baikal:8094:Productivity & Utilities:Lightweight CalDAV + CardDAV server."
    "wekan:8095:Productivity & Utilities:Open-source Trello-like kanban board."
    "mealie:9090:Productivity & Utilities:Self-hosted recipe manager and meal planner."
    "stirling-pdf:8098:Productivity & Utilities:Self-hosted web-based PDF manipulation tool."
    "rocket-chat:3001:Productivity & Utilities:Free, open-source communication platform."
    "filebrowser:8099:Productivity & Utilities:Web-based file manager."

    # Home Automation, Monitoring & Backups
    "home-assistant:8123:Home Automation & Monitoring:Open source home automation platform."
    "netdata:19999:Home Automation & Monitoring:Real-time performance monitoring."
    "prometheus:9095:Home Automation & Monitoring:Systems monitoring and alerting toolkit."
    "grafana:3002:Home Automation & Monitoring:Monitoring and observability platform."
    "alertmanager:9093:Home Automation & Monitoring:Handles alerts from Prometheus."
    "healthchecks:8000:Home Automation & Monitoring:Cron job monitoring service."
    "uptime-kuma:3003:Home Automation & Monitoring:Fancy self-hosted monitoring tool."
    "changedetectionio:5001:Home Automation & Monitoring:Monitor websites for changes."
    "duplicati:8200:Home Automation & Monitoring:Backup client for cloud storage."
    "graylog:9001:Home Automation & Monitoring:Centralized log management (web UI port, adjusted from 9000)." # Inputs separate

    # Development & Code Management
    "gitea:3004:Development & Code Management:Painless self-hosted Git service."
    "huginn:3005:Development & Code Management:System for building agents that perform automated tasks."

    # Document Management & Wikis
    "dokuwiki:8100:Document Management & Wikis:Simple to use Open Source wiki software."
    "bookstack:6875:Document Management & Wikis:Platform for organising and storing information."
    "paperless-ngx:8001:Document Management & Wikis:Document management system."
)

# --- Helper Functions ---
get_user_paths_and_tz() {
    local app_name_sanitized="$1"
    local needs_data_path="$2" # "yes" or "no"
    local needs_media_path="$3" # "yes" or "no"

    default_config_path="/opt/${app_name_sanitized}/config"
    default_data_path="/srv/${app_name_sanitized}/data" # Generic data
    default_media_path="/srv/media/${app_name_sanitized}" # For media apps

    read -e -p "$(echo -e ${CYAN}"Enter path for ${app_name_sanitized} config [${default_config_path}]: "${NC})" app_config_path
    app_config_path=${app_config_path:-$default_config_path}

    if [[ "$needs_data_path" == "yes" ]]; then
        read -e -p "$(echo -e ${CYAN}"Enter path for ${app_name_sanitized} data [${default_data_path}]: "${NC})" app_data_path
        app_data_path=${app_data_path:-$default_data_path}
    fi
    if [[ "$needs_media_path" == "yes" ]]; then
        read -e -p "$(echo -e ${CYAN}"Enter path for ${app_name_sanitized} media files [${default_media_path}]: "${NC})" app_media_path
        app_media_path=${app_media_path:-$default_media_path}
    fi

    default_tz=$(cat /etc/timezone 2>/dev/null || echo "America/New_York")
    read -p "$(echo -e ${CYAN}"Enter your TimeZone [${default_tz}]: "${NC})" app_tz
    app_tz=${app_tz:-$default_tz}

    # Export them so the calling function can use them by name (Bash specific)
    # Or pass them back in an array / global vars if preferred. For simplicity here:
    _APP_CONFIG_PATH="$app_config_path"
    _APP_DATA_PATH="$app_data_path"
    _APP_MEDIA_PATH="$app_media_path"
    _APP_TZ="$app_tz"
}

execute_docker_command() {
    local cmd_type="$1" # "pull" or "run"
    local image_name="$2" # For pull
    local full_command="$3" # For run

    if [[ "$cmd_type" == "pull" ]]; then
        echo -e "${WHITE}# ${GREEN}docker pull $image_name${NC}"
        if docker pull "$image_name"; then
            echo -e "${GREEN}Image $image_name pulled successfully.${NC}"
            return 0
        else
            echo -e "${RED}Failed to pull image $image_name.${NC}"
            return 1
        fi
    elif [[ "$cmd_type" == "run" ]]; then
        echo -e "${WHITE}# ${B_GREEN}${full_command}${NC}" # Display the command
        if eval "$full_command"; then # Execute the command
            return 0
        else
            return 1
        fi
    fi
}


check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo -e "${ERROR_X} Docker could not be found. Please install Docker to continue."
        exit 1
    fi
    if ! docker info &> /dev/null; then
        echo -e "${ERROR_X} Docker daemon is not running. Please start Docker to continue."
        exit 1
    fi
    echo -e "${GREEN}Docker is installed and running.${NC}"
}

is_port_available() {
    local port_to_check="$1"
    if ss -tulnp | grep -q ":${port_to_check}\b"; then
        return 1 # Port is in use
    else
        return 0 # Port is available
    fi
}

# --- Installation Functions (Many are now filled!) ---

install_plex() {
    local app_name="$1"
    local host_port="$2"
    local container_port="32400"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "plex" "yes" "yes" # config, data (transcode), media
    local plex_config_path="$_APP_CONFIG_PATH"
    local plex_transcode_path="$_APP_DATA_PATH" # Using generic data path for transcode
    local plex_media_path="$_APP_MEDIA_PATH"
    local plex_tz="$_APP_TZ"

    echo -e "${CYAN}You may need a PLEX_CLAIM token. Get one from https://www.plex.tv/claim/${NC}"
    read -p "$(echo -e ${CYAN}"Enter your PLEX_CLAIM token (optional, press Enter to skip): "${NC})" plex_claim

    mkdir -p "$plex_config_path" "$plex_transcode_path" "$plex_media_path"

    local image_name="plexinc/pms-docker"
    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name \"$app_name\" \
        -p \"$host_port:$container_port/tcp\" \
        -p \"3005:3005/tcp\" \
        -p \"8324:8324/tcp\" \
        -p \"32469:32469/tcp\" \
        -p \"1900:1900/udp\" \
        -p \"32410:32410/udp\" \
        -p \"32412:32412/udp\" \
        -p \"32413:32413/udp\" \
        -p \"32414:32414/udp\" \
        -e TZ=\"$plex_tz\" \
        -e PUID=\"$(id -u)\" \
        -e PGID=\"$(id -g)\" \
        -e VERSION=\"docker\" "
    if [[ -n "$plex_claim" ]]; then
        docker_cmd+=" -e PLEX_CLAIM=\"$plex_claim\" "
    fi
    docker_cmd+=" -v \"$plex_config_path:/config\" \
        -v \"$plex_transcode_path:/transcode\" \
        -v \"$plex_media_path:/data\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_jellyfin() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8096"
    local image_name="lscr.io/linuxserver/jellyfin:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "jellyfin" "yes" "yes" # config, cache (as data), media
    local app_config_path="$_APP_CONFIG_PATH"
    local app_cache_path="$_APP_DATA_PATH" # Using generic data for cache
    local app_media_path="$_APP_MEDIA_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_cache_path" "$app_media_path"

    execute_docker_command "pull" "$image_name" || return 1
    
    local docker_cmd="docker run -d \
        --name \"$app_name\" \
        -e PUID=\"$(id -u)\" \
        -e PGID=\"$(id -g)\" \
        -e TZ=\"$app_tz\" \
        -p \"$host_port:$container_port\" \
        -v \"$app_config_path:/config\" \
        -v \"$app_cache_path:/cache\" \
        -v \"$app_media_path:/media\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_sonarr() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8989"
    local image_name="lscr.io/linuxserver/sonarr:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "sonarr" "yes" "yes" # config, downloads (as data), tv shows (as media)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH"
    local app_tv_path="$_APP_MEDIA_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_tv_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_tv_path:/tv\" \
        -v \"$app_downloads_path:/downloads\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_radarr() {
    local app_name="$1"
    local host_port="$2"
    local container_port="7878"
    local image_name="lscr.io/linuxserver/radarr:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "radarr" "yes" "yes" # config, downloads (as data), movies (as media)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH"
    local app_movies_path="$_APP_MEDIA_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_movies_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_movies_path:/movies\" \
        -v \"$app_downloads_path:/downloads\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}


install_lidarr() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8686"
    local image_name="lscr.io/linuxserver/lidarr:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "lidarr" "yes" "yes" # config, downloads (data), music (media)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH"
    local app_music_path="$_APP_MEDIA_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_music_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_music_path:/music\" \
        -v \"$app_downloads_path:/downloads\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_readarr() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8787"
    local image_name="lscr.io/linuxserver/readarr:develop" # Often 'develop' is more up-to-date for Readarr

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "readarr" "yes" "yes" # config, downloads (data), books (media)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH"
    local app_books_path="$_APP_MEDIA_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_books_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_books_path:/books\" \
        -v \"$app_downloads_path:/downloads\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_bazarr() {
    local app_name="$1"
    local host_port="$2"
    local container_port="6767"
    local image_name="lscr.io/linuxserver/bazarr:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "bazarr" "no" "yes" # config, media (movies & tv for scanning)
    local app_config_path="$_APP_CONFIG_PATH"
    # Bazarr needs access to Sonarr/Radarr's media folders for context
    read -e -p "$(echo -e ${CYAN}"Enter path to your Movies folder (same as Radarr's /movies): "${NC})" app_movies_path
    read -e -p "$(echo -e ${CYAN}"Enter path to your TV Shows folder (same as Sonarr's /tv): "${NC})" app_tv_path
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path"
    [[ -n "$app_movies_path" ]] && mkdir -p "$app_movies_path"
    [[ -n "$app_tv_path" ]] && mkdir -p "$app_tv_path"


    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_movies_path:/movies\" \
        -v \"$app_tv_path:/tv\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}


install_transmission() {
    local app_name="$1"
    local host_port="$2"
    local container_port="9091" # Web UI
    local container_peer_port="51413" # Peer port
    local image_name="lscr.io/linuxserver/transmission:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "transmission" "yes" "no" # config, downloads (data)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH"
    local app_watch_path="$app_config_path/watch" # Often a watch dir is useful
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_watch_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -p $container_peer_port:$container_peer_port \
        -p $container_peer_port:$container_peer_port/udp \
        -v \"$app_config_path:/config\" \
        -v \"$app_downloads_path:/downloads\" \
        -v \"$app_watch_path:/watch\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_sabnzbd() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8080"
    local image_name="lscr.io/linuxserver/sabnzbd:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "sabnzbd" "yes" "no" # config, downloads (data)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH" # For completed downloads
    local app_incomplete_path="$app_downloads_path/incomplete" # For incomplete
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_incomplete_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_downloads_path:/downloads\" \
        -v \"$app_incomplete_path:/incomplete-downloads\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_jackett() {
    local app_name="$1"
    local host_port="$2"
    local container_port="9117"
    local image_name="lscr.io/linuxserver/jackett:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "jackett" "yes" "no" # config, downloads (data for blackhole)
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH" # For .torrent files if using blackhole
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_downloads_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_downloads_path:/downloads\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_tautulli() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8181"
    local image_name="lscr.io/linuxserver/tautulli:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "tautulli" "no" "no" # config only
    local app_config_path="$_APP_CONFIG_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_calibre_web() {
    local app_name="calibre-web" # Hardcode for function name consistency
    local host_port="$2"
    local container_port="8083"
    local image_name="lscr.io/linuxserver/calibre-web:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "calibre-web" "no" "no" # config
    local app_config_path="$_APP_CONFIG_PATH"
    read -e -p "$(echo -e ${CYAN}"Enter path to your Calibre library database (metadata.db file location): "${NC})" calibre_db_path
    local app_tz="$_APP_TZ"

    if [[ -z "$calibre_db_path" ]]; then
        echo -e "${RED}Calibre library path is required. Aborting.${NC}"
        return 1
    fi
    mkdir -p "$app_config_path" "$calibre_db_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name=$app_name \
        -e PUID=$(id -u) \
        -e PGID=$(id -g) \
        -e TZ=\"$app_tz\" \
        -e DOCKER_MODS=linuxserver/calibre-web:calibre # To install Calibre itself if needed for conversion
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$calibre_db_path:/books\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_portainer() {
    local app_name="$1"
    local host_port="$2" # e.g. 9443 for HTTPS or 9000 for HTTP
    local container_port

    if [[ "$host_port" == "9443" ]]; then
        container_port="9443"
    elif [[ "$host_port" == "9000" ]]; then
        container_port="9000" # If you use an HTTP entry in array
    else
        echo -e "${YELLOW}Portainer host port in array is $host_port. Assuming it's for HTTPS (9443 internal).${NC}"
        container_port="9443"
    fi
    local image_name="portainer/portainer-ce:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "portainer" "yes" "no" # portainer_data as data
    local portainer_data_path="$_APP_DATA_PATH"
    mkdir -p "$portainer_data_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        -p $host_port:$container_port \
        --name \"$app_name\" \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v \"$portainer_data_path:/data\" \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_nginx_proxy_manager() {
    local app_name="nginx-proxy-manager"
    local host_port="$2" # Admin UI port, e.g. 81
    local container_admin_port="81"
    local container_http_port="80"
    local container_https_port="443"
    local image_name="jc21/nginx-proxy-manager:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "npm" "yes" "no" # config (as data), letsencrypt
    local app_data_path="$_APP_CONFIG_PATH" # Using config as general app data path
    local app_letsencrypt_path="$_APP_DATA_PATH" # Using data as letsencrypt path

    mkdir -p "$app_data_path" "$app_letsencrypt_path"

    execute_docker_command "pull" "$image_name" || return 1

    # Prompt for host HTTP/HTTPS ports if they want to change from default 80/443
    local host_http_port="80"
    local host_https_port="443"
    read -e -p "$(echo -e ${CYAN}"Enter HOST port for HTTP proxy [${host_http_port}]: "${NC})" temp_http_port
    host_http_port=${temp_http_port:-$host_http_port}
    read -e -p "$(echo -e ${CYAN}"Enter HOST port for HTTPS proxy [${host_https_port}]: "${NC})" temp_https_port
    host_https_port=${temp_https_port:-$host_https_port}


    local docker_cmd="docker run -d \
        --name $app_name \
        -p $host_http_port:$container_http_port \
        -p $host_https_port:$container_https_port \
        -p $host_port:$container_admin_port \
        -v \"$app_data_path:/data\" \
        -v \"$app_letsencrypt_path:/etc/letsencrypt\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_pi_hole() {
    local app_name="pi-hole"
    local host_port="$2" # Web UI port from array
    local container_web_port="80" # Pi-hole internal web port
    local image_name="pihole/pihole:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "pihole" "no" "no" # etc-pihole, etc-dnsmasq.d
    local path_etc_pihole="$_APP_CONFIG_PATH/etc-pihole"
    local path_etc_dnsmasq="$_APP_CONFIG_PATH/etc-dnsmasq.d"
    local app_tz="$_APP_TZ"

    read -p "$(echo -e ${CYAN}"Enter a secure password for the Pi-hole web interface: "${NC})" pihole_password
    if [[ -z "$pihole_password" ]]; then
        echo -e "${RED}Pi-hole password cannot be empty. Aborting.${NC}"
        return 1
    fi
    read -e -p "$(echo -e ${CYAN}"Enter host IP for Pi-hole (SERVERIP, typically your Docker host's LAN IP): "${NC})" server_ip
     if [[ -z "$server_ip" ]]; then
        echo -e "${RED}Pi-hole Server IP is required. Aborting.${NC}"
        return 1
    fi

    mkdir -p "$path_etc_pihole" "$path_etc_dnsmasq"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name $app_name \
        -p 53:53/tcp -p 53:53/udp \
        -p $host_port:$container_web_port \
        -e TZ=\"$app_tz\" \
        -e WEBPASSWORD=\"$pihole_password\" \
        -e SERVERIP=\"$server_ip\" \
        -v \"$path_etc_pihole:/etc/pihole\" \
        -v \"$path_etc_dnsmasq:/etc/dnsmasq.d\" \
        --dns=127.0.0.1 --dns=1.1.1.1 \
        --restart=unless-stopped \
        --cap-add=NET_ADMIN \
        $image_name"
    # --hostname pi.hole might be useful too

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully. Web UI password: $pihole_password ${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_adguard_home() {
    local app_name="adguard-home"
    local host_port="$2" # Web UI port from array (e.g., 3000)
    local container_web_port="3000" # AdGuard internal web port
    local image_name="adguard/adguardhome:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "adguardhome" "yes" "no" # workdir, confdir
    local ag_work_dir="$_APP_CONFIG_PATH/work" # Using config for base
    local ag_conf_dir="$_APP_CONFIG_PATH/conf"

    mkdir -p "$ag_work_dir" "$ag_conf_dir"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name $app_name \
        -p 53:53/tcp -p 53:53/udp \
        -p 67:67/udp -p 68:68/tcp -p 68:68/udp \
        -p $host_port:$container_web_port/tcp \
        -p 853:853/tcp \
        -p 784:784/udp \
        -p 853:853/udp \
        -p 8853:8853/udp \
        -p 5443:5443/tcp -p 5443:5443/udp \
        -v \"$ag_work_dir:/opt/adguardhome/work\" \
        -v \"$ag_conf_dir:/opt/adguardhome/conf\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully. Navigate to host_ip:$host_port for setup.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_vaultwarden() {
    local app_name="vaultwarden"
    local host_port="$2"
    local container_port="80" # Vaultwarden internal port
    local image_name="vaultwarden/server:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "vaultwarden" "yes" "no" # data
    local vw_data_path="$_APP_DATA_PATH"

    mkdir -p "$vw_data_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name $app_name \
        -v \"$vw_data_path:/data\" \
        -p $host_port:$container_port \
        --restart unless-stopped \
        $image_name"
    # For WebSocket notifications, map port 3012 as well: -p 3012:3012
    # And set -e WEBSOCKET_ENABLED=true

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_home_assistant() {
    local app_name="home-assistant"
    local host_port="$2" # 8123
    local container_port="8123"
    local image_name="ghcr.io/home-assistant/home-assistant:stable"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "homeassistant" "no" "no" # config
    local ha_config_path="$_APP_CONFIG_PATH"
    local app_tz="$_APP_TZ" # HA uses this TZ

    mkdir -p "$ha_config_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name $app_name \
        -v \"$ha_config_path:/config\" \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        --restart unless-stopped \
        --privileged \
        $image_name"
        # --network=host can be used for easier device discovery but has security implications
        # For Z-Wave/Zigbee, you'd add device mappings: -v /dev/ttyUSB0:/dev/ttyUSB0

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}


install_nextcloud() {
    local app_name="nextcloud"
    local host_port="$2"
    # Using Nextcloud AIO for simpler setup if user doesn't want to manage separate DB/Redis
    # This is a more complex setup that AIO handles.
    # For a basic Nextcloud with SQLite (not recommended for prod):
    local container_port="80"
    local image_name="nextcloud:latest" # Official image, uses Apache

    echo -e "${PURPLE}Preparing to install $app_name (basic, with SQLite)...${NC}"
    echo -e "${YELLOW}For a more robust setup, consider Nextcloud AIO or setting up a separate database.${NC}"
    get_user_paths_and_tz "nextcloud" "yes" "no" # main data as /var/www/html
    local nc_data_path="$_APP_DATA_PATH" # This will be /var/www/html in container

    mkdir -p "$nc_data_path"

    execute_docker_command "pull" "$image_name" || return 1

    local docker_cmd="docker run -d \
        --name $app_name \
        -p $host_port:$container_port \
        -v \"$nc_data_path:/var/www/html\" \
        --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully (using SQLite).${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}


# ... (Many more install functions would follow this pattern) ...
# Example: Duplicati, Gitea, Bookstack, Paperless-ngx etc.


# --- Placeholder for other install functions ---
install_generic_placeholder() {
    local app_name="$1"
    local host_port="$2"
    # Try to guess a linuxserver image or a common official one
    local app_name_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed 's/-//g')
    local suggested_image="lscr.io/linuxserver/$app_name_lower:latest" # Guess
    # If not found, could try hub.docker.com/_/$app_name_lower or similar

    echo -e "${B_YELLOW}INSTALLING $app_name (PLACEHOLDER)${NC}"
    echo -e "This is a placeholder function for ${WHITE}$app_name${NC}."
    echo -e "Please edit the script to add the correct Docker pull and run commands."
    echo -e "Required host port: ${WHITE}$host_port${NC} (maps to container port, e.g., 80 or specific app port)"
    echo -e "Suggested image (best guess, verify!): ${CYAN}$suggested_image${NC}"
    echo ""

    get_user_paths_and_tz "$app_name_lower" "yes" "no" # config, data
    local app_config_path="$_APP_CONFIG_PATH"
    local app_data_path="$_APP_DATA_PATH"
    local app_tz="$_APP_TZ"

    mkdir -p "$app_config_path" "$app_data_path"

    echo -e "${WHITE}Example Docker command structure (NEEDS TO BE COMPLETED FOR $app_name):${NC}"
    local example_container_port="80" # Generic, needs to be specific
    echo -e "${WHITE}# ${GREEN}docker pull $suggested_image${NC}"
    local placeholder_cmd="docker run -d \\\\
        --name \"$app_name\" \\\\
        -p \"$host_port:$example_container_port\" \\\\ # Ensure $example_container_port is correct for this app
        -e PUID=\$(id -u) -e PGID=\$(id -g) \\\\
        -e TZ=\"$app_tz\" \\\\
        -v \"$app_config_path:/config\" \\\\ # Standard /config, but verify for the image
        -v \"$app_data_path:/data\" \\\\   # Standard /data, if needed
        --restart unless-stopped \\\\
        $suggested_image"
    echo -e "${WHITE}# ${GREEN}${placeholder_cmd}${NC}"
    echo -e "${B_YELLOW}END PLACEHOLDER FOR $app_name${NC}"
    echo ""
    return 1 # Indicate that this was a placeholder and didn't actually install
}


create_install_functions() {
    local app_name
    for app_entry in "${apps_data[@]}"; do
        app_name=$(echo "$app_entry" | cut -d: -f1)
        local func_name="install_$(echo "$app_name" | tr '-' '_' | tr '[:upper:]' '[:lower:]')" # ensure lowercase and underscores

        if ! type "$func_name" &>/dev/null; then
            eval "
            ${func_name}() {
                install_generic_placeholder \"\$1\" \"\$2\"
            }
            "
        fi
    done
}

# --- Main Script Logic ---

check_docker_installed
create_install_functions

echo -e "${B_GREEN}Welcome to the Docker Container Installer!${NC}"
echo -e "You can choose which Docker containers to create based on predefined categories."
echo ""

declare -A category_counts
declare -a sorted_categories

for app_entry in "${apps_data[@]}"; do
    category=$(echo "$app_entry" | cut -d: -f3)
    category_counts["$category"]=$(( ${category_counts["$category"]} + 1 ))
done

IFS=$'\n' sorted_categories=($(sort <<<"${!category_counts[*]}"))
unset IFS

echo -e "${WHITE}Available application categories:${NC}"
for category_name in "${sorted_categories[@]}"; do
    count=${category_counts["$category_name"]}
    echo -e "- ${B_YELLOW}$category_name${NC} ($count app(s))"
done
echo ""
read -p "$(echo -e ${CYAN}"Press any key to continue... "${NC})" -n 1 -s
echo -e "\n"


for category_name in "${sorted_categories[@]}"; do
    echo -e "${B_YELLOW}Category: $category_name${NC}"
    echo -e "${WHITE}Host port number is in brackets beside App Name${NC}"
    
    declare -a apps_in_category
    for app_entry in "${apps_data[@]}"; do
        current_category=$(echo "$app_entry" | cut -d: -f3)
        if [[ "$current_category" == "$category_name" ]]; then
            app_name=$(echo "$app_entry" | cut -d: -f1)
            host_port=$(echo "$app_entry" | cut -d: -f2)
            description=$(echo "$app_entry" | cut -d: -f4)
            echo -e "- ${WHITE}$app_name${NC} ($host_port): $description"
            apps_in_category+=("$app_entry")
        fi
    done
    echo ""

    read -p "$(echo -e ${CYAN}"Do you want to process applications in the '$category_name' category? [y/N]: "${NC})" process_category_choice
    process_category_choice_lower=$(echo "$process_category_choice" | tr '[:upper:]' '[:lower:]')

    if [[ "$process_category_choice_lower" != "y" ]]; then
        echo -e "${YELLOW}Skipping category '$category_name'.${NC}"
        echo -e "\n"
        continue
    fi
    echo ""

    for app_entry_to_install in "${apps_in_category[@]}"; do
        app_name=$(echo "$app_entry_to_install" | cut -d: -f1)
        host_port=$(echo "$app_entry_to_install" | cut -d: -f2)
        
        echo -e "${CYAN}Processing App: ${WHITE}$app_name${NC} (Attempting Host Port: ${WHITE}$host_port${NC})"

        if is_port_available "$host_port"; then
            echo -e "${GREEN}Host port $host_port appears to be available.${NC}"
            read -p "$(echo -e ${CYAN}"Do you want to install $app_name? [y/N]: "${NC})" install_choice
            install_choice_lower=$(echo "$install_choice" | tr '[:upper:]' '[:lower:]')

            if [[ "$install_choice_lower" == "y" ]]; then
                func_to_call="install_$(echo "$app_name" | tr '-' '_' | tr '[:upper:]' '[:lower:]')"
                if type "$func_to_call" &>/dev/null; then
                    "$func_to_call" "$app_name" "$host_port"
                else
                    echo -e "${ERROR_X} Installation function ${RED}$func_to_call${NC} not found for $app_name."
                fi
            else
                echo -e "${YELLOW}Skipping installation of $app_name.${NC}"
            fi
        else
            echo -e "${ERROR_X} Host port ${RED}$host_port${NC} is NOT available. Skipping $app_name."
        fi
        echo "" 
    done
    echo -e "${B_GREEN}Finished processing category '$category_name'.${NC}"
    echo -e "\n"
done

echo -e "${B_GREEN}All categories processed. Script finished.${NC}"
