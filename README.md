# Universal SteamCMD Proton Dedicated Server

> A universal Docker container for running Windows-based Steam dedicated servers on Linux using Proton.

[![Build Status](https://github.com/kronflux/steamcmd-proton-server/workflows/Build%20and%20Push%20Docker%20Image/badge.svg)](https://github.com/kronflux/steamcmd-proton-server/actions)
[![Docker Hub](https://img.shields.io/docker/v/kronflux/steamcmd-proton-server?label=dockerhub)](https://hub.docker.com/r/kronflux/steamcmd-proton-server)

## Features

- **Universal Support** - Works with any Windows-based Steam dedicated server
- **Proton-Powered** - Uses GE-Proton for maximum compatibility
- **Three Operation Modes** - SteamCMD download, URL download, or direct file mounting
- **Game Presets** - Pre-configured support for popular games (SotF, Valheim, DayZ, Subnautica)
- **Automated Backups** - Built-in backup system with configurable retention
- **Health Monitoring** - Container health checks for process monitoring
- **Log Rotation** - Automatic log management to prevent disk filling
- **RCON Support** - Integrated RCON CLI for server management

## Supported Games

This container supports any Windows-based Steam dedicated server, including:

| Game | Steam App ID |
|------|-------------|--------|
| Sons of the Forest | 2465200 |
| Valheim | 896660 |
| DayZ | 223350 |
| Subnautica | 447530 |
| Palworld | 2394010 |
| And more... | | See below |

## Quick Start

### Using Docker Run

```bash
docker run -d \
  --name game-server \
  --restart unless-stopped \
  -e STEAM_APP_ID=2465200 \
  -e PROTON_APP_ID=1326470 \
  -e GAME_EXECUTABLE=SonsOfTheForestDS.exe \
  -e SERVER_NAME="My Server" \
  -e GAME_PORT=8766 \
  -p 8766:8766/udp \
  -p 27016:27016/udp \
  -v ./data:/data \
  kronflux/steamcmd-proton-server:latest
```

### Using Docker Compose (Recommended)

1. Create a `docker-compose.yml` file:

```yaml
services:
  game-server:
    image: kronflux/steamcmd-proton-server:latest
    container_name: game-server
    restart: unless-stopped

    environment:
      - STEAM_APP_ID=1326470
      - GAME_EXECUTABLE=SonsOfTheForestDS.exe
      - SERVER_NAME=My Server
      - GAME_PORT=7777
      - QUERY_PORT=7778

    ports:
      - "7777:7777/udp"
      - "7778:7778/udp"

    volumes:
      - ./data:/data
```

2. Start the server:

```bash
docker-compose up -d
```

## Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `STEAM_APP_ID` | Steam App ID of the Windows server | `2465200` |
| `GAME_EXECUTABLE` | Name of the server executable | `SonsOfTheForestDS.exe` |

### Optional Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PROTON_APP_ID` | Game App ID for Proton prefix (if different from server) | `1326470` |

### Common Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_NAME` | Server display name | `Dedicated Server` |
| `SERVER_PASSWORD` | Server password (empty = public) | |
| `GAME_PORT` | Primary game port | `7777` |
| `QUERY_PORT` | Query port for server browser | `7778` |
| `MAX_PLAYERS` | Maximum player count | `10` |
| `GAME_CONFIG` | Game preset selector | `generic` |
| `GAME_MODE` | Operation mode | `steam` |

### Operation Modes

#### Steam Mode (Default)
Automatically downloads and updates the game via SteamCMD:

```yaml
environment:
  - GAME_MODE=steam
  - STEAM_APP_ID=2465200
```

#### Download Mode
Downloads game from a URL:

```yaml
environment:
  - GAME_MODE=download
  - GAME_DOWNLOAD_URL=https://example.com/game-files.tar.gz
```

#### Direct Mode
Uses pre-existing game files (must be mounted to `/game`):

```yaml
environment:
  - GAME_MODE=direct
volumes:
  - ./existing-game-files:/game
```

## Game Presets

### Sons of the Forest

```yaml
environment:
  - GAME_CONFIG=sons-of-the-forest
  - STEAM_APP_ID=2465200               # Dedicated Server App ID
  - PROTON_APP_ID=1326470              # Game App ID (for Proton prefix)
  - GAME_EXECUTABLE=SonsOfTheForestDS.exe
  - SERVER_NAME=SotF Server
  - GAME_PORT=8766
  - QUERY_PORT=27016
  - MAX_PLAYERS=8

ports:
  - "8766:8766/udp"
  - "27016:27016/udp"
  - "9700:9700/udp"
```

### Valheim

```yaml
environment:
  - GAME_CONFIG=valheim
  - STEAM_APP_ID=896660
  - GAME_EXECUTABLE=valheim_server.exe
  - SERVER_NAME=Valheim Server
  - WORLD_NAME=MyWorld
  - GAME_PORT=2456

ports:
  - "2456:2456/udp"
  - "2457:2457/udp"
  - "2458:2458/udp"
```

### DayZ

```yaml
environment:
  - GAME_CONFIG=dayz
  - STEAM_APP_ID=223350
  - GAME_EXECUTABLE=DayZServer.exe
  - GAME_PORT=2302

ports:
  - "2302:2302/udp"
  - "2303:2303/udp"
  - "2304:2304/udp"
  - "2305:2305/udp"
```

### Subnautica

```yaml
environment:
  - GAME_CONFIG=subnautica
  - STEAM_APP_ID=447530
  - GAME_EXECUTABLE=SubnauticaServer.exe
  - GAME_PORT=7777

ports:
  - "7777:7777/udp"
  - "7778:7778/udp"
```

## Modded Servers

The container supports modded game servers with automatic mod installation.

### Sons of the Forest with RedLoader

[RedLoader](https://github.com/ToniMacaroni/RedLoader) is a mod loader for Sons of the Forest.

```bash
cd examples/sons-of-the-forest-modded
docker-compose up -d
```

RedLoader will be installed automatically on first run. To add mods:

1. Wait for initial setup to complete
2. Stop the container: `docker-compose down`
3. Download mods from [Thunderstore](https://thunderstore.io/c/sons_of_the_forest/)
4. Extract mods to `./mods/ModName/`
5. Restart: `docker-compose up -d`

**Key Settings:**
```yaml
environment:
  - INSTALL_REDLOADER=true           # Enable RedLoader
  - REDLOADER_VERSION=latest         # Or specify version

volumes:
  - ./mods:/game/Mods                # Mount for easy mod management
```

### Subnautica with Nitrox

[Nitrox](https://github.com/SubnauticaNitrox/Nitrox) is a multiplayer mod for Subnautica.

```bash
cd examples/subnautica-nitrox
docker-compose up -d
```

Nitrox will be installed automatically on first run. The server uses the native Linux Nitrox component for better performance.

**Key Settings:**
```yaml
environment:
  - GAME_CONFIG=subnautica-nitrox
  - NITROX_SAVE_NAME=MyServer        # Save slot name
  - NITROX_PORT=11000                # Server port
  - SERVER_PASSWORD=55555            # Server password
  - ADMIN_PASSWORD=Chickenpotpie101  # Admin password
  - GAME_MODE=SURVIVAL               # SURVIVAL|FREEDOM|CREATIVE

ports:
  - "11000:11000/udp"                # Nitrox port
```

**Configuration:** After first run, edit `./nitrox-data/saves/MyServer/server.cfg` to customize settings.

**Note:** Nitrox uses a native Linux server component, not Proton. The Subnautica game files are still downloaded for asset loading.

## UnRAID Deployment

1. Add the container in UnRAID Docker settings:
   - Template: `kronflux/steamcmd-proton-server`
   - Repository: `kronflux/steamcmd-proton-server:latest`

2. Configure the container:

| Setting | Value |
|---------|-------|
| Name | `sons-of-the-forest` |
| Game Config | `sons-of-the-forest` |
| Steam App ID | `1326470` |
| Server Name | Your server name |
| Game Port | `7777` |

3. Map ports:
   - `7777:7777/udp`
   - `7778:7778/udp`
   - `8766:8766/udp`
   - `27016:27016/udp`

4. Map paths:
   - `/mnt/user/appdata/sotf-data` → `/data`

5. Start the container

## Advanced Features

### Automated Backups

Backups run daily at 3 AM and are retained for 7 days by default.

```yaml
environment:
  - BACKUP_RETENTION=7      # Days to keep
```

Manual backup:
```bash
docker exec game-server /scripts/backup.sh
```

### RCON Support

For games that support RCON:

```yaml
environment:
  - RCON_ENABLED=true
  - RCON_PORT=27015
  - RCON_PASSWORD=your_password
```

Connect via RCON CLI:
```bash
docker exec -it game-server rcon-cli --host 127.0.0.1 --port 27015 --pass your_password "help"
```

### Steam Authentication

For games requiring account ownership:

```yaml
environment:
  - STEAM_USER=your_username
  - STEAM_PASSWORD=your_password
  - STEAM_GUARD_CODE=12345
```

**Note:** Use a separate Steam account for servers. Steam Guard codes are required on first login.

### Custom Game Arguments

```yaml
environment:
  - GAME_ARGS=-batchmode -nographics -logFile
```

### Beta Branches

```yaml
environment:
  - STEAM_BETA=beta
  - STEAM_BETA_PASSWORD=beta_password
```

## Volume Structure

```
/data
├── config/          # Generated configuration files
├── logs/            # Server logs with rotation
├── savefiles/       # Game save data
└── backups/         # Automated backups

/game                # Game installation (Steam Mode)
```

## Finding Your Game's Configuration

1. **Steam App ID**: Visit [SteamDB](https://steamdb.info/apps/) and search for your game

2. **Executable Name**: Check game documentation or run:
   ```bash
   docker run --rm -v ./game:/game kronflux/steamcmd-proton-server:latest \
     bash -c "find /game -name '*.exe' | grep -i server"
   ```

3. **Required Ports**: Check game documentation or SteamDB

## Troubleshooting

### Container Exits Immediately

Check the logs:
```bash
docker logs game-server
```

Common issues:
- Invalid `STEAM_APP_ID`
- Incorrect `GAME_EXECUTABLE` name
- Missing required ports

### Server Not Visible in Browser

1. Check port mappings - ensure UDP protocol
2. Verify firewall settings
3. Check server logs for errors
4. Ensure `QUERY_PORT` is set correctly

### Performance Issues

Consider using host networking:
```yaml
network_mode: host
```

Or increase resource limits:
```yaml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 8G
```

### Steam Guard Code Required

If using a non-anonymous Steam account with 2FA:
1. Start container with credentials
2. Container will wait for Steam Guard code
3. Set `STEAM_GUARD_CODE` and restart

### Corrupted Game Files

Force validation:
```yaml
environment:
  - STEAM_VALIDATE=true
```

## Development

### Building Locally

```bash
git clone https://github.com/kronflux/steamcmd-proton-server.git
cd steamcmd-proton-server
docker build -f docker/Dockerfile -t steamcmd-proton-server:test .
```

### Running Tests

```bash
# Test Proton detection
docker run --rm steamcmd-proton-server:test \
  bash -c "source /scripts/functions.sh && detect_proton"

# Test SteamCMD
docker run --rm steamcmd-proton-server:test \
  bash -c "/steamcmd/steamcmd.sh +version +quit"

# Test Wine prefix
docker run --rm -v /tmp/test:/data steamcmd-proton-server:test \
  bash -c "source /scripts/functions.sh && init_wine_prefix /data/wine"
```

## Architecture

This container uses a modular script architecture:

```
entrypoint.sh          # Main orchestrator
├── 00_firstrun.sh     # First-time setup
├── 01_steam.sh        # SteamCMD init
├── 02_server.sh       # Game server download/update
├── 03_config.sh       # Config generation
├── start.sh           # Server startup
├── healthcheck.sh     # Health monitoring
├── backup.sh          # Backup automation
└── functions.sh       # Shared utilities
```

### Key Components

- **Base Image**: Debian 13 (Trixie) Slim
- **Proton**: GE-Proton (auto-detects latest)
- **SteamCMD**: Official Valve SteamCMD
- **Wine**: Wine 64/32 for compatibility layer
- **Xvfb**: For games requiring display

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

For game preset additions, please include:
- Steam App ID
- Executable name
- Required ports
- Any special configuration needs

## License

MIT License - see LICENSE file for details

## Credits

- **GE-Proton**: [GloriousEggroll](https://github.com/GloriousEggroll/proton-ge-custom)
- **Proton**: Valve Software
- **SteamCMD**: Valve Corporation

## Support

- **Issues**: [GitHub Issues](https://github.com/kronflux/steamcmd-proton-server/issues)
- **Docker Hub**: [kronflux/steamcmd-proton-server](https://hub.docker.com/r/kronflux/steamcmd-proton-server)
