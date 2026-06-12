# Adding a Game

Every game this container supports is a **self-contained module**: one directory holding an
environment preset and (optionally) a handful of hook functions. The core scripts contain no
game-specific logic — they discover everything from the module.

```
scripts/games/<name>/
├── preset.conf   # required: environment defaults (sourced first)
└── setup.sh      # optional: hook functions (sourced after the preset)
```

Start by copying the commented skeleton at `scripts/games/_template/`.

## Module resolution (and the no-rebuild overlay)

`load_game_module` resolves each file independently, first match wins:

1. `/data/games/<name>/` — **user overlay**: add a brand-new game or hot-patch a shipped one
   on a running deployment, no image rebuild
2. `/scripts/games/<name>/` — baked module (this repo)
3. `/scripts/presets/<name>.conf` — legacy preset location (compat only)

Overlay use is announced in the logs: `Module 'scum': preset.conf from /data/games/scum/ (USER OVERRIDE)`.
Directory names starting with `_` are reserved and ignored (that's why `_template` never loads).
A syntax error in an overlay file aborts the start loudly with the parser message — fix or remove it.

## preset.conf reference

Required keys (set unconditionally):

| Key | Meaning |
|---|---|
| `STEAM_APP_ID` | SteamDB app ID the container downloads (dedicated server app, or game files for mod-served games like Nitrox) |
| `GAME_EXECUTABLE` | Path relative to `GAME_DIR`. A Windows `.exe` runs via Proton; native servers also define `game_start` |
| `GAME_MODE` | `steam` (SteamCMD download), `download` (URL), or `direct` (pre-mounted files) |
| `GAME_CONFIG` | Must equal the module directory name |

Optional keys (only when the game needs them):

| Key | Meaning |
|---|---|
| `NEEDS_DISPLAY=true` | Start Xvfb (Unity/UE servers that require an X display) |
| `USE_LINUX_DEPOT=true` | Native-Linux server: skip the Windows depot force. **Never set `STEAM_PLATFORM`** — steamcmd.sh reads that name internally and breaks |
| `STEAM_INSTALL_SUBDIR=<dir>` | SteamCMD installs into `GAME_DIR/<dir>` (e.g. Nitrox keeps Subnautica in its own subdirectory) |
| `PROTON_APP_ID` | Only when the Proton prefix app ID differs from the download app ID (e.g. SotF) |
| `WINETRICKS_VERBS="…"` | Windows runtime libs provisioned into the Wine prefix on first start (e.g. SCUM needs `vcrun2017 d3dcompiler_47 crypt32`). Re-runs automatically when the list changes; `WINETRICKS_FORCE=true` re-runs unconditionally |

Defaults use the `${VAR:-default}` pattern so user-provided env always wins:

```bash
export SERVER_NAME="${SERVER_NAME:-My Server}"
```

## setup.sh hook contract

All hooks are optional. They run with the preset env and all `functions.sh` helpers available.

| Hook | Called from | Purpose | Default when undefined |
|---|---|---|---|
| `game_configure()` | `03_config.sh` | Generate/migrate config + save wiring | generic config generator |
| `game_args()` | `start.sh` | `echo` the launch-args string (framework appends `GAME_ARGS`) | empty |
| `game_start()` | `start.sh`, before any Proton setup | **Full launch override** for native-Linux servers — owns the process, log tail, exit code | Proton pipeline |
| `game_healthcheck()` | `healthcheck.sh` | Liveness probe (warn-only) | generic process check |
| `game_verify_install()` | `02_server.sh` after download | Return 0 if the downloaded files look right | `GAME_EXECUTABLE` existence check |

Reference implementations: `scripts/games/scum/` (Proton + winetricks), `scripts/games/vein/`
(native, refuses root — non-root `game_start`), `scripts/games/subnautica-nitrox/` (mod-served:
authenticated game-file download + separately installed server binary),
`scripts/games/sons-of-the-forest/` (jq config surgery + mod loader + `-modded` variant).

## Persistence helpers

Keep real files in `/data` and symlink them into the game tree — idempotent across restarts,
survives container recreation:

```bash
persist_file "${GAME_DIR}/serverDZ.cfg"        "${DATA_DIR}/config/serverDZ.cfg"
persist_dir  "${GAME_DIR}/SCUM/Saved/SaveFiles" "${DATA_DIR}/saves"
```

`persist_file` migrates a pre-existing real game-side file into `/data` (only when the data side
is empty — `/data` is canonical), then replaces it with a symlink. Call it **before** any
generate-if-absent block so user files are never overwritten:

```bash
game_configure() {
    local config_dir="${DATA_DIR}/config"
    mkdir -p "${config_dir}"
    persist_file "${GAME_DIR}/server.cfg" "${config_dir}/server.cfg"
    if [[ ! -f "${config_dir}/server.cfg" ]]; then
        printf 'name=%s\n' "${SERVER_NAME}" > "${config_dir}/server.cfg"
    fi
}
```

## The no-rebuild development loop

Develop a module against a **running deployment** — no image builds:

1. On the Docker host: `mkdir -p <appdata>/games/mygame` and create `preset.conf` (+ `setup.sh`).
2. Set the container's `GAME_CONFIG=mygame` and restart it.
3. Watch the logs — the `(USER OVERRIDE)` lines confirm your module loaded; a fast crash
   automatically prints the log tail and matched failure hints.
4. Diagnose anytime: `docker exec <container> /scripts/doctor.sh` *(container-only command)*.
5. Iterate on the files and restart until the server is healthy.
6. Promote: copy the module into `scripts/games/<name>/` in this repo and follow the checklist below.

## Decision guide

- **Proton or native?** If the server ships a Linux binary, prefer native: `USE_LINUX_DEPOT=true`,
  `GAME_EXECUTABLE` pointing at the launcher, and a `game_start` hook. Windows-only servers run
  via Proton automatically.
- **Server refuses to run as root** (`Refusing to run with the root privileges`): copy the vein
  pattern — `game_start` creates a non-root user (PUID/PGID) and launches via `su`.
- **Crashes instantly with no output under Proton:** usually a missing Windows runtime. The crash
  capture prints matched hints; set `WINEDEBUG=err+all,fixme-all` to surface the missing DLL, then
  add the matching verb to `WINETRICKS_VERBS`.
- **No dedicated server on Steam** (mod-served games): download the game files with an
  authenticated login (`STEAM_USER`/`STEAM_PASSWORD`/one-time `STEAM_GUARD_CODE`, cached
  thereafter), install the community server in `game_configure`, launch it in `game_start` —
  see `subnautica-nitrox`.
- **Verify facts against reality.** Executable names, app IDs, config filenames, and ports must
  come from a real source (SteamDB, official wiki, a working setup) — never from guesswork.

## Verification

From the repo root:

```bash
bash tests/capture-golden.sh <name>     # snapshot your module's config behavior as a baseline
bash tests/compare-golden.sh            # all games still behavior-identical
bash tests/loader-matrix.sh             # module resolution intact
bash tests/operability-matrix.sh        # diagnostics/hooks/provisioning intact
bash -n scripts/games/<name>/setup.sh   # syntax
```

To include your game in the golden suite, add it to `ALL_GAMES` (and `PROTON_GAMES` /
`SEEDED_GAMES` as appropriate) in `tests/lib-golden.sh`, then capture.

## Completion checklist

- [ ] `scripts/games/<name>/preset.conf` (+ `setup.sh` if hooks are needed)
- [ ] `examples/<name>/docker-compose.yml`
- [ ] `unraid/<name>.xml` (model on an existing template)
- [ ] `.env.example` block documenting the game's variables
- [ ] README supported-games table row (+ preset section if the game needs explanation)
- [ ] Golden baseline captured and committed (`tests/golden/<name>/`)
- [ ] All four test suites green
- [ ] One scoped commit: `feat(<name>): add <Game> dedicated server`
