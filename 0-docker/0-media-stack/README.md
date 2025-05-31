# Media Stack Setup

This project sets up a self-hosted media download and management automation suite, protected by VPN:

- Wireguard (very lightweight, much lower CPU footprint than gluetun with OpenVPN)
- qBittorrent (actually qbittorrent-nox but image name is binhex/qbittorentvpn)
- Sonarr
- Radarr
- Prowlarr
- (Filebrowser)

## Setup

1. Run `./setup-media-stack.sh`
2. Enter the download folder and no-osl.conf files
3. The services will be available locally at:
   - qBittorrent: http://localhost:8080
   - Sonarr: http://localhost:8989
   - Radarr: http://localhost:7878
   - Prowlarr: http://localhost:9117
   - (Filebrowser: http://localhost:8081)

## Teardown

To stop and optionally delete everything:

```bash
./stop-and-remove-media-stack.sh
```
