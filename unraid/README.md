# UnRAID Templates

This directory contains UnRAID Docker container templates for steamcmd-proton-server.

## Installation

### Method 1: UnRAID Community Applications (Recommended)

1. In UnRAID, go to **Apps** → **Settings**
2. Add a new template repository:
   - Name: `steamcmd-proton-server`
   - URL: `https://raw.githubusercontent.com/kronflux/steamcmd-proton-server/main/unraid/templates.xml`

### Method 2: Manual Installation

1. Copy the XML file(s) from this directory to your UnRAID server:
   ```
   /boot/config/plugins/dockerMan/templates/user/
   ```

2. In UnRAID, go to **Apps** → **Docker** and click **Add Container** → **Select Template**

## Available Templates

| Template | Description |
|----------|-------------|
| `sons-of-the-forest.xml` | Sons of the Forest Dedicated Server |

## Configuration

### First-Time Setup

1. **Set up data path** (recommended):
   - Data Path: `/mnt/user/appdata/steamcmd-proton-server/sotf`

2. **Configure server settings**:
   - Server Name: Your server name
   - Server Password: Optional (leave empty for public)
   - Max Players: 8 (default)

3. **Port mappings** (automatically configured):
   - 8766/udp - Game Port
   - 27016/udp - Query Port
   - 9700/udp - BlobSync Port

### Advanced Settings

- **Steam App ID**: 2465200 (Dedicated Server) - Do not change unless you know what you're doing
- **Proton App ID**: 1326470 (Game Client) - For Proton compatibility layer
- **Validate Files**: Set to `true` if experiencing corruption issues
- **Backup Retention**: Days to keep automated backups (default: 7)
- **Install RedLoader**: Set to `true` to enable mod support

## Troubleshooting

### First Run

- First run downloads ~15GB of game files (takes 5-15 minutes depending on connection)
- Server appears in server browser 2-3 minutes after startup
- Check logs: **Docker** tab → **Console** button

### Server Not Visible

1. Check port mappings are correct
2. Verify firewall allows ports 8766, 27016, 9700
3. Wait 2-3 minutes for server to fully start
4. Check server logs for errors

### Mods Support

Enable **Install RedLoader** in advanced settings to add mod support. After first run:

1. Stop the container
2. Add mods to `/mnt/user/appdata/steamcmd-proton-server/sotf/game/Mods/`
3. Restart container

Download mods from: https://thunderstore.io/c/sons_of_the_forest/

### Updates

The container automatically checks for updates on every restart. To force validation:

1. Stop the container
2. Set **Validate Files** to `true`
3. Start container
4. Set **Validate Files** back to `false` after update completes
