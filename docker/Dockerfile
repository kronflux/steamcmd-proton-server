# Universal SteamCMD Proton Dedicated Server
# Base: Debian 13 (Trixie) Slim - Latest stable Debian with minimal footprint
FROM debian:trixie-slim

LABEL maintainer="Richard M <richard@rmoser.ca>"
LABEL description="Universal Docker container for Windows-based Steam dedicated servers using Proton"
LABEL version="1.0.0"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Add 32-bit architecture for Steam/Proton
RUN dpkg --add-architecture i386

# Install minimal dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    ca-certificates \
    curl \
    wget \
    jq \
    python3 \
    procps \
    file \
    cron \
    # Xvfb for Unity games requiring display
    xvfb \
    xauth \
    x11-apps \
    x11-utils \
    # Wine for wineboot initialization
    wine64 \
    wine32 \
    winbind \
    # 32-bit libraries for Steam/Proton
    lib32gcc-s1 \
    lib32stdc++6 \
    libgl1:i386 \
    libgl1-mesa-dri:i386 \
    # X11 libraries for Proton (64-bit)
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxi6 \
    libxrandr2 \
    libxss1 \
    libxtst6 \
    libfreetype6 \
    libxxf86vm1 \
    libgl1-mesa-dri \
    libgl1 \
    # Vulkan software renderer (lavapipe) - required for DXVK in GPU-less containers
    mesa-vulkan-drivers \
    libvulkan1 \
    # Additional dependencies for game servers
    libasound2 \
    libglib2.0-0 \
    libgtk-3-0 \
    dbus \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Generate locale
RUN sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Create necessary directories
RUN mkdir -p /steamcmd /data /scripts /scripts/presets /root/.steam \
    && chmod +x /scripts

# Null ALSA config - suppresses "Unknown PCM default" errors (no audio hardware in container)
RUN printf 'pcm.!default { type null }\nctl.!default { type null }\n' > /etc/asound.conf

# Ensure stable machine-id for Wine/Proton (required for consistent behaviour)
RUN rm -f /etc/machine-id /var/lib/dbus/machine-id \
    && dbus-uuidgen --ensure=/etc/machine-id \
    && mkdir -p /var/lib/dbus \
    && dbus-uuidgen --ensure

# Install SteamCMD
RUN curl -sL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C /steamcmd \
    && chmod +x /steamcmd/steamcmd.sh

# Download and install GE-Proton (latest version will be detected at runtime)
RUN mkdir -p /root/.steam/steam/compatibilitytools.d \
    && curl -sL "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest" \
    | grep "browser_download_url.*tar.gz" \
    | cut -d '"' -f 4 \
    | head -n 1 \
    | xargs curl -sL \
    | tar -xz -C /root/.steam/steam/compatibilitytools.d

# lsteamclient.so loads the native Steam library via dlopen("~/.steam/sdk64/steamclient.so").
# SteamCMD's standalone copy works without a running Steam daemon.
RUN mkdir -p /root/.steam/sdk64 \
    && ln -sf /steamcmd/linux64/steamclient.so /root/.steam/sdk64/steamclient.so

# Install RCON CLI tool for server management
RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "x86_64" ]; then \
        RCON_URL=$(curl -s https://api.github.com/repos/gorcon/rcon-cli/releases/latest \
            | grep -o 'https://.*amd64_linux\.tar\.gz' \
            | grep -v darwin \
            | head -n 1) \
        && curl -sL "$RCON_URL" | tar -xz -C /usr/local/bin --strip-components=1 \
        && chmod +x /usr/local/bin/rcon; \
    fi

# Install .NET 9 Runtime (required for Nitrox mod)
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 9.0 --runtime aspnetcore --install-dir /usr/share/dotnet \
    && rm /tmp/dotnet-install.sh \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet

# Install unzip for mod archives (RedLoader, Nitrox)
RUN apt-get update && apt-get install -y --no-install-recommends unzip rsync \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy scripts and presets
COPY scripts/*.sh /scripts/
COPY scripts/presets/*.conf /scripts/presets/

# Set script permissions and create cron job for automated backups
RUN chmod +x /scripts/*.sh \
    && echo "0 3 * * * /scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/backup \
    && chmod 0644 /etc/cron.d/backup \
    && crontab -u root /etc/cron.d/backup \
    && touch /var/log/backup.log

# Environment variables
ENV STEAM_RUNTIME=0 \
    PROTON_NO_FSYNC=1 \
    PROTON_NO_ESYNC=1 \
    STEAM_COMPAT_DATA_PATH="" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="/root/.steam/steam" \
    GAME_DIR="/data/server" \
    DATA_DIR="/data" \
    BACKUP_DIR="/data/backups" \
    LOG_MAX_SIZE="100M" \
    LOG_RETENTION=5 \
    BACKUP_RETENTION=7 \
    STEAM_UPDATE=true \
    STEAM_VALIDATE=false \
    VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/lvp_icd.json"

# Volume declarations
VOLUME ["/data"]

# Working directory
WORKDIR /data

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD /scripts/healthcheck.sh || exit 1

STOPSIGNAL SIGTERM

# Main entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
