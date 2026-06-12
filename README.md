# Universal SteamCMD Proton Dedicated Server

> A universal Docker container for running Windows-based Steam dedicated servers on Linux using Proton.

[![Build Status](https://github.com/kronflux/steamcmd-proton-server/workflows/Build%20and%20Push%20Docker%20Image/badge.svg)](https://github.com/kronflux/steamcmd-proton-server/actions)
[![Docker Hub](https://img.shields.io/docker/v/kronflux/steamcmd-proton-server?label=dockerhub)](https://hub.docker.com/r/kronflux/steamcmd-proton-server)

## Features

- **Universal Support** - Works with any Windows-based Steam dedicated server (and native Linux servers)
- **Proton-Powered** - Uses GE-Proton for maximum compatibility (pin a version with `PROTON_VERSION`)
- **Three Operation Modes** - SteamCMD download, URL download, or direct file mounting
- **Game Modules** - Each supported game is a self-contained module (SotF, Valheim, DayZ, Subnautica via Nitrox, Star Rupture, Vein, SCUM)
- **Runtime Extensible** - Add or patch games via `/data/games/` overlays and run `/data/hooks/` scripts — no image rebuild
- **Built-in Diagnostics** - `doctor.sh` one-command diagnosis plus automatic crash capture with actionable hints
- **Automated Backups** - Built-in backup system with configurable retention
- **Health Monitoring** - Container health checks with per-game probes
- **Log Rotation** - Automatic log management to prevent disk filling
- **RCON Support** - Integrated RCON CLI for server management

## Supported Games

This container supports any Windows-based Steam dedicated server, including:

| Game | Steam App ID |
|------|--------------|
| Sons of the Forest | 2465200 |
| Valheim | 896660 |
| DayZ | 223350 |
| Subnautica (via Nitrox) | 264710 |
| Star Rupture | 3809400 |
| Vein | 2131400 |
| SCUM | 3792580 |
| Palworld | 2394010 (generic) |
| And more... | see below |

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
Uses pre-existing game files (mounted at the game directory, `/data/server`):

```yaml
environment:
  - GAME_MODE=direct
volumes:
  - ./existing-game-files:/data/server
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
  - GAME_EXECUTABLE=DayZServer_x64.exe
  - GAME_PORT=2302

ports:
  - "2302:2302/udp"
  - "2303:2303/udp"
  - "2304:2304/udp"
  - "2305:2305/udp"
```

### Star Rupture

```yaml
environment:
  - GAME_CONFIG=starrupture
  - SERVER_NAME=Star Rupture Server
  - GAME_PORT=7777
  - QUERY_PORT=27015

ports:
  - "7777:7777/tcp"
  - "7777:7777/udp"
  - "27015:27015/udp"
```

### Vein

Vein ships a **native Linux** dedicated server (free, anonymous login) — the module runs it
directly as a non-root user, no Proton. Server settings live in `/data/config/Game.ini` after
first run.

```yaml
environment:
  - GAME_CONFIG=vein
  - SERVER_NAME=Vein Server
  - MAX_PLAYERS=16
  - GAME_PORT=7777
  - QUERY_PORT=27015

ports:
  - "7777:7777/udp"
  - "27015:27015/udp"
```

### SCUM

SCUM uses three consecutive ports — players connect on the game port + 2. The Windows runtime
libraries it needs are provisioned into the Wine prefix automatically on first start
(`WINETRICKS_VERBS`, preset default). Settings live in `/data/config/ServerSettings.ini`.

```yaml
environment:
  - GAME_CONFIG=scum
  - MAX_PLAYERS=64
  - GAME_PORT=7777
  - QUERY_PORT=7779

ports:
  - "7777:7777/udp"
  - "7778:7778/udp"
  - "7779:7779/tcp"
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

## Extending Without Rebuilding

Everything game-specific is a **module** that can also live on your data volume — so you can add
a new game or patch a shipped one on a running deployment, with no image rebuild:

```
/data/games/<name>/preset.conf   # overrides (or adds) the game's environment defaults
/data/games/<name>/setup.sh      # overrides (or adds) the game's hook functions
```

Resolution is per-file (your overlay wins over the baked module), and the startup log announces
`(USER OVERRIDE)` when an overlay is active. See `docs/ADDING_GAMES.md` for the full module
anatomy, hook contract, and development loop.

User lifecycle hooks run at fixed points (great for mod installs and tweaks):

```
/data/hooks/post-install.sh      # after download + config generation
/data/hooks/pre-start.sh         # immediately before launch
```

Runtime knobs (env vars, no rebuild):

| Variable | Effect |
|---|---|
| `WINETRICKS_VERBS` | Windows runtime libs provisioned into the Wine prefix (re-runs when the list changes) |
| `WINETRICKS_FORCE=true` | Re-provision unconditionally on next start |
| `PROTON_VERSION=GE-Proton10-34` | Pin (and auto-download) an exact GE-Proton release |
| `CRASH_CAPTURE_SECONDS` | Fast-exit crash capture threshold (default 60; 0 disables) |
| `WINEDEBUG=err+all,fixme-all` | Surface Wine loader errors when a Windows server crashes silently |

You can also extend the failure-hint table the diagnostics use: drop `regex<TAB>hint` lines into
`/data/diagnostics.d/*.conf`.

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
  - STEAM_GUARD_CODE=12345           # First login only (see below)
  - STEAM_CACHE_KEY=set-a-private-value
```

**How the Steam Guard cache works:**

1. On first run, provide `STEAM_GUARD_CODE` (a TOTP code from the Steam mobile app, or a one-time backup code).
2. SteamCMD writes a sentry file marking this container as a trusted machine.
3. That sentry file plus the cached login token are tar'd and encrypted with `STEAM_CACHE_KEY` (AES-256-CBC + PBKDF2) and stored at `/data/.steamcmd/cache.tar.enc`.
4. On subsequent runs the cache is decrypted and restored before SteamCMD logs in — no Guard code needed. You can clear `STEAM_GUARD_CODE` from your env after the first successful run.
5. Change `STEAM_CACHE_KEY` to a private value; leaving it as `changeme` works but defeats the purpose. Changing it later invalidates the cache and requires one fresh Guard code to re-prime.

**Note:** Use a separate Steam account for servers. Steam Guard mobile-authenticator backup codes are one-time-use, so you only get a handful of fresh logins before you need to generate new ones — the cache exists specifically to avoid burning through them.

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
├── server/          # Game installation (downloaded by SteamCMD)
├── config/          # Generated configuration files (symlinked into the game tree)
├── saves/           # Game save data (symlinked into the game tree)
├── logs/            # Server logs with rotation
├── backups/         # Automated backups
├── games/           # Optional: your module overlays (see Extending Without Rebuilding)
├── hooks/           # Optional: post-install.sh / pre-start.sh
└── diagnostics.d/   # Optional: extra failure-hint rules
```

## Finding Your Game's Configuration

1. **Steam App ID**: Visit [SteamDB](https://steamdb.info/apps/) and search for your game

2. **Executable Name**: Check game documentation, or after the download completes:
   ```bash
   docker exec game-server bash -c "find /data/server -name '*.exe' | grep -i server"
   ```

3. **Required Ports**: Check game documentation or SteamDB

## Troubleshooting

**Start with the built-in doctor** — it checks the module, environment, files, Proton/Wine state,
ports, logs (with known-failure hints), and resources in one shot:

```bash
docker exec game-server /scripts/doctor.sh
```

When a server dies shortly after launch, the container automatically prints the log tail and any
matched failure hints to the console — check `docker logs` first.

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
1. On first start, set `STEAM_USER`, `STEAM_PASSWORD`, and `STEAM_GUARD_CODE` (TOTP from the mobile app or a one-time backup code).
2. After the first successful login, the Guard session is cached under `/data/.steamcmd/`, encrypted with `STEAM_CACHE_KEY`.
3. Clear `STEAM_GUARD_CODE` from your env afterward — restarts will use the cached session and won't prompt for a new code.

If you see `ERROR (Invalid Password)` in the logs, double-check `STEAM_PASSWORD` is actually set in your env — an empty password produces this exact error. If you see `ERROR (Account Logon Denied)` or a Steam Guard prompt, the cache was wiped (e.g. you changed `STEAM_CACHE_KEY`) and you need a fresh `STEAM_GUARD_CODE` for one run.

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

The core is **game-agnostic**; every game is a self-contained module:

```
scripts/
├── entrypoint.sh          # Main orchestrator
├── 00_firstrun.sh         # First-time setup
├── 01_steam.sh            # SteamCMD + GE-Proton init (PROTON_VERSION pinning)
├── 02_server.sh           # Game download/update (steam | download | direct)
├── 03_config.sh           # Config generation (dispatches to the module)
├── start.sh               # Launch (Proton pipeline, or the module's game_start)
├── healthcheck.sh         # Health monitoring (module probe or generic)
├── doctor.sh              # One-command diagnosis
├── backup.sh              # Backup automation
├── functions.sh           # Shared utilities (loader, persist helpers, diagnostics)
├── diagnostics.d/         # Failure-signature hint table
└── games/<name>/          # ONE MODULE PER GAME
    ├── preset.conf        #   environment defaults
    └── setup.sh           #   optional hooks: game_configure, game_args,
                           #   game_start, game_healthcheck, game_verify_install
```

Modules resolve per-file, first match wins: `/data/games/<name>/` (user overlay) →
`/scripts/games/<name>/` (baked). Adding a game touches no core script — see
`docs/ADDING_GAMES.md`.

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

For new games, follow `docs/ADDING_GAMES.md` — start from `scripts/games/_template/` and include:
- Steam App ID, executable name, and required ports (verified against a real source)
- Example compose file, Unraid template, `.env.example` block, and a golden baseline

## License

MIT License - see LICENSE file for details

## Credits

- **GE-Proton**: [GloriousEggroll](https://github.com/GloriousEggroll/proton-ge-custom)
- **Proton**: Valve Software
- **SteamCMD**: Valve Corporation

## Support

- **Issues**: [GitHub Issues](https://github.com/kronflux/steamcmd-proton-server/issues)
- **Docker Hub**: [kronflux/steamcmd-proton-server](https://hub.docker.com/r/kronflux/steamcmd-proton-server)
