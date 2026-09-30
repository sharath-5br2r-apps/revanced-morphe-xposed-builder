# Local Execution (`build.sh`)

You can run builds directly on Linux or Android (Termux).

> [!TIP]
> **Getting Configs and Fetching App Versions First:**
> Run `scripts/fetch_local_data.sh` to materialize `configs/` and `state/` from your local `data` branch.
> If you are building locally without pinned app versions, run `scripts/fetch_versions.sh` before running `build.sh`. This queries configured sources (APKMirror, Uptodown, GitHub, etc.) to discover and cache the latest target app versions in `state/app_versions.json`.
>
> ```bash
> # Materialize configs and state from local data branch
> ./scripts/fetch_local_data.sh
>
> # Fetch versions for all apps (or filter with --allowed-apps)
> ./scripts/fetch_versions.sh [--allowed-apps="regex"]
> ```

### Syntax
```bash
./scripts/build.sh [--clean] [--config=path] [--allowed-apps="regex"] [--output=path] [filters...]
```

### Options & Arguments
- `--config=path`: Path to a `.toml` or compiled `.json` configuration.
- `--allowed-apps="regex"`: Only build apps matching the regex. Prefix with `!` to exclude (e.g. `!YouTube`).
- `--output=path`: Custom directory for finished artifacts (default: `build/`).
- `--patches-version=stable|beta|both`: Override the patch channel for this
  build without setting an environment variable.
- `--clean`: Purge temporary directories (`temp/`, `build/`, `build.md`) and exit.
- `[filters...]`: Positional arguments to include or exclude specific app tables:
  ```bash
  # Build only YouTube and Twitter
  ./build.sh configs/patches/morphe.toml YouTube Twitter

  # Build all apps except YouTube
  ./build.sh configs/patches/morphe.toml !YouTube
  ```

### Environment Variables
| Variable | Description |
|---|---|
| `KEYSTORE_BASE64` | Base64-encoded Java Keystore (`.keystore` / `.jks`) |
| `KEYSTORE_PASSWORD` | Password for the keystore |
| `KEYSTORE_ALIAS` | Key alias in the keystore |
| `KEYSTORE_KEY_PASSWORD` | Key password (defaults to `KEYSTORE_PASSWORD` if unset) |
| `NEXT_VER_CODE` | Explicit release version code (e.g. `2026.09.15-1`) |
| `TRAWL_URL` / `CFB_URL` | FlareSolverr / Cloudflare bypass scraper endpoints |
| `HTMLQ` / `YQ` / `AAPT2` | Custom binary paths |
