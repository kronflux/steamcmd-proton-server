# CLAUDE.md

Conventions for working on this repo with an AI assistant (or without one).

## What this project is

A universal Docker image for Steam dedicated servers: Windows servers run via GE-Proton, native
Linux servers run directly. Every game is a **self-contained module** under `scripts/games/<name>/`
(`preset.conf` + optional `setup.sh` hooks); the core scripts are game-agnostic. Modules can be
added or patched at runtime from `/data/games/<name>/` without rebuilding the image.

## Commits

- Scoped Conventional Commits: `feat(<game>):`, `fix(wine):`, `refactor(core):`, `docs:`, `test:`, `chore:`.
- One concern per commit; split mixed files per-hunk if needed.
- Author-only attribution — no AI co-author trailers or generated-by footers.

## Adding or changing a game

Follow `docs/ADDING_GAMES.md`. Non-negotiables:

- **Verify facts against reality** (SteamDB, official wikis, working setups) — never guess
  executable names, app IDs, config filenames, or ports.
- Develop against a running deployment via the `/data/games/<name>/` overlay before baking.
- One scoped commit per game; include the example compose, Unraid XML, `.env.example` block,
  README table row, and a golden baseline.

## Testing

Local suites (no Docker needed) — all must pass before any commit that touches `scripts/`:

```bash
bash tests/compare-golden.sh      # per-game config/args behavior vs committed baselines
bash tests/loader-matrix.sh      # module resolution (overlay, legacy, reserved names)
bash tests/operability-matrix.sh # diagnostics, hooks, provisioning, crash capture
bash -n <changed scripts>
```

Golden baselines are the refactor safety net: behavior changes require a deliberate re-capture
(`bash tests/capture-golden.sh <game>`) explained in the commit message — never silently.

## Things that bite

- Never export `STEAM_PLATFORM` — `steamcmd.sh` reads that name to locate its own binary.
  Native-Linux games use `USE_LINUX_DEPOT=true` instead.
- Line endings are enforced LF via `.gitattributes`; Windows-side git tools must not flip
  shell scripts to CRLF (it breaks the container).
- `/root` inside the container is ephemeral (wiped on recreate); anything persistent must live
  under `/data` — wire it with `persist_file`/`persist_dir`.
- The Steam Guard login cache (`/data/.steamcmd/`) lets authenticated downloads survive restarts;
  cached-session logins must stay username-only (passing the password forces re-auth and burns
  Guard codes).

## Deployment reality

The maintainer deploys on Unraid (plain Docker, not compose): "Force Update" recreates the
container; the image publishes to Docker Hub via GitHub Actions on push to `main`. Runtime
validation happens on that box — keep local verification static/script-level and batch image
builds (one CI build per validated change-set, not per commit).
