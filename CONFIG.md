# Configuration Guide

This builder compiles patched Android apps (APKs) and Magisk / KernelSU modules using declarative TOML configuration files.

Adding an app is as simple as defining a table with a download URL:

```toml
[YouTube]
apkmirror-dlurl = "https://www.apkmirror.com/apk/google-inc/youtube"
```

> [!WARNING]
> **Single Quotes in Patch Names:** If a patch name contains a single quote, escape it by doubling the quote inside the string (e.g. `'Hide ''Get Music Premium'''`).

---

## Table of Contents

1. [Configuration Architecture](#configuration-architecture)
2. [Complete Reference Example](#complete-reference-example)
3. [Naming, Branding & Filename Resolution](#naming-branding--filename-resolution)
4. [Host Specification & Custom Instances](#host-specification--custom-instances)
5. [Patch Engines & CLI Modes](#patch-engines--cli-modes)
6. [Patch Bundles & Selection](#patch-bundles--selection)
7. [Version Resolution & Architectures](#version-resolution--architectures)
8. [Download Sources (`dlurl`)](#download-sources-dlurl)
9. [Magisk / KernelSU Modules](#magisk--kernelsu-modules)
10. [Local Execution (`build.sh`)](#local-execution-buildsh)
11. [CI Workflow & Automation](#ci-workflow--automation)
12. [Website Catalog & Metrics Synchronization](#website-catalog--metrics-synchronization)

---

## Configuration Architecture

Configurations are organized in `.github/configs/patches/*.toml` (e.g. `morphe.toml`, `anddea.toml`, `piko.toml`).

- **Single-File Co-existence:** All variants and builds for a patch source or brand can reside in one `.toml` file.
- **File-Level Defaults:** Any key defined before the first `[...]` table header acts as a default for all apps in that file. Apps automatically inherit these values unless explicitly overridden.
- **Dynamic Pool Routing:**
  - **Stable Only (Default):** Apps with `patches-version = "stable"` (or omitting `patches-version` in standard `*.toml` files) are compiled into the **stable** build pool.
  - **Beta Only:** Apps with `patches-version = "beta"` (or `dev` / `absolutelatest`, or inside `*.beta.toml` / `*.dev.toml` files) are routed exclusively to the **beta** pool.
  - **Both Pools:** Setting `patches-version = "both"` (or `"all"`) compiles the app into **both** stable and beta pools.
  - **Pinned Versions:** An explicit version tag (e.g. `v1.41.0`) routes to stable, unless the tag contains pre-release tokens (`beta`, `dev`, `alpha`, `rc`, `pre`) or the file default is beta.
- **Disabling an App:** Set `enabled = false` to disable an app across all build pools.

---

## Complete Reference Example

Below is a complete TOML example showing available keys and default values:

```toml
# ==============================================================================
# FILE-LEVEL DEFAULTS (Inherited by all app tables in this file)
# ==============================================================================
patches-source = "MorpheApp/morphe-patches"  # Patch repository (default: "MorpheApp/morphe-patches")
patches-source-host = "github"               # Host: "github", "gitlab", "forgejo", "gitea", "codeberg", or "host_url|host_type"
patches-version = "stable"                   # "stable", "beta", "both", "latest", or explicit tag (e.g. "v1.10.0")

cli-source = "MorpheApp/morphe-desktop"      # CLI engine repository (default: "MorpheApp/morphe-desktop")
cli-source-host = "github"                   # Host for CLI (default: "github")
cli-version = "stable"                       # "stable", "beta", "latest", or explicit version

brand = "Morphe"                             # Brand display name (e.g. "Morphe", "ReVanced Advanced", "Piko")
variant = ""                                 # Optional feature/theme variant (e.g. "Nord", "Mocha", "MaterialYou")
sub-variant = ""                             # Optional packaging variant (e.g. "clone", "alt")

arch = "both"                                # "both", "auto", "all", "arm64-v8a", "arm-v7a", "x86_64", "x86"
dpi = "nodpi anydpi auto"                    # Preferred screen DPI order for APKMirror
build-mode = "apk"                           # "apk", "module", or "both"
include-stock = "merged"                     # "merged", "split", or "disable"

author = "sharath-5br2r"                     # Module maintainer name
author-page = "github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder" # Author link printed in module
compression-level = 9                        # Magisk module ZIP compression level (0-9)
enable-module-update = true                  # Generate update JSON files and commit to update branch
remove-rv-integrations-checks = false        # Strip integration checks from ReVanced integrations

# ==============================================================================
# APP DEFINITION
# ==============================================================================
[YouTube]
enabled = true                               # Set to false to disable building this app
app-name = "YouTube"                         # Human-readable display name (defaults to table name)
brand = "Morphe"                             # Per-app brand override
variant = "Nord"                             # Feature/theme variant override
sub-variant = "clone"                        # Packaging variant override (e.g. "clone")
pkg-name = "com.google.android.youtube"      # Upstream stock package ID
patched-pkg-name = "app.rvx.android.youtube" # Resulting package ID override (auto-detected via aapt2 if omitted)
patch-folder = "youtube"                     # Explicit patch folder in patch bundle (skips heuristics; supports "*" wildcard)

# --- Versioning ---
version = "auto"                             # "auto" (highest supported by patches), "exp", "latest", "beta", or "20.40.45"
version-code = "auto"                        # "auto", numeric string, or per-arch: "arm64-v8a: 473623755 | arm-v7a: 473623748"
version-filter = ""                          # Regex filter for APK versions on APKMirror

# --- Patch Control ---
exclusive-patches = false                    # If true, disables all patches by default and only applies included-patches
included-patches = "'Some Patch'"            # Whitespace-separated list of extra patches to include
excluded-patches = """\
  'Hide Shorts' \
  'Custom Branding' \
"""                                          # Whitespace-separated list of patches to exclude
patcher-args = """\
  -OdarkThemeBackgroundColor=#FF0F0F0F \
  -OanotherOption=true \
"""                                          # Additional arguments passed to the CLI

# --- Upstream APK Source (Choose one) ---
apkmirror-dlurl = "https://www.apkmirror.com/apk/google-inc/youtube"
# uptodown-dlurl = "https://youtube.en.uptodown.com/android"
# apkpure-dlurl = "https://apkpure.com/youtube/com.google.android.youtube"
# apkcombo-dlurl = "https://apkcombo.com/youtube/com.google.android.youtube"
# archive-dlurl = "https://archive.org/download/..."
# github-dlurl = "https://github.com/owner/repo"
# gitlab-dlurl = "https://gitlab.com/owner/repo"
# forgejo-dlurl = "https://codeberg.org/owner/repo"
# direct-dlurl = "https://example.com/app-v1.0.apk"
# local-dlurl = "/path/to/stock.apk"

# --- Module Settings ---
module-prop-name = "youtube-morphe"          # Magisk module identifier (default: "<app>-<author>")
```

---

## Naming, Branding & Filename Resolution

The builder enforces declarative naming conventions across artifact files, release notes, and the website catalog:

| Key | Description | Example |
|---|---|---|
| `app-name` | Human-readable app name | `"YouTube"`, `"Instagram"`, `"Prime Video"` |
| `brand` | Canonical patch brand / identity | `"Morphe"`, `"ReVanced Advanced"`, `"Piko"`, `"Adobo"` |
| `engine-brand` | Low-level engine override | `"morphe"`, `"npatch"`, `"apksigner"` |
| `patch-brand` | Canonical patch identity when using alternative engines | `"ReVanced"`, `"Piko"` |
| `variant` | Visual or feature distinction | `"Nord"`, `"Mocha"`, `"MaterialYou"` |
| `sub-variant` | Packaging / installation variation | `"clone"`, `"alt"` |
| `pkg-name` | Stock upstream package name | `"com.google.android.youtube"` |
| `patched-pkg-name` | Installed package name if changed by clone patches | `"app.rvx.android.youtube"` |

### Output Filename Convention

The engine automatically constructs clean kebab-cased filenames:

```
${app_slug}-${brand_slug}${variant:+-$variant}${sub_variant:+-$sub_variant}-v${version}-${arch}.apk
```

**Examples:**
- `app-name = "YouTube"`, `brand = "ReVanced Advanced"`, `variant = "Nord"`  
  ➔ `youtube-revanced-advanced-nord-v20.51.39-arm64-v8a.apk`
- `app-name = "Instagram"`, `brand = "Piko"`, `sub-variant = "clone"`  
  ➔ `instagram-piko-clone-v439.0.0.37.89-arm64-v8a.apk`
- `app-name = "TikTok"`, `brand = "Morphe"`, `sub-variant = "alt"`  
  ➔ `tiktok-morphe-alt-v37.5.4-arm64-v8a.apk`

---

## Host Specification & Custom Instances

Both `patches-source-host` and `cli-source-host` support public forges as well as self-hosted git instances.

### Supported Syntaxes

1. **Standard Named Host:**
   ```toml
   patches-source-host = "github"   # https://github.com (default)
   patches-source-host = "gitlab"   # https://gitlab.com
   patches-source-host = "forgejo"  # (Requires custom domain or codeberg)
   patches-source-host = "codeberg" # https://codeberg.org
   patches-source-host = "none"     # Passthrough / local
   ```

2. **Custom Instance Syntax (`host_url|host_type`):**
   ```toml
   # Custom self-hosted Forgejo/Gitea instance
   patches-source-host = "https://git.example.com|forgejo"

   # Custom self-hosted GitLab instance
   patches-source-host = "https://gitlab.internal.company.com|gitlab"
   ```

3. **Direct Domain (Defaults to Forgejo):**
   ```toml
   patches-source-host = "codeberg.org"
   ```

---

## Patch Engines & CLI Modes

The builder supports multiple patch engines and CLI wrappers:

### 1. Morphe Desktop (Default)
```toml
cli-source = "MorpheApp/morphe-desktop"
cli-version = "stable"
```
Supports both `.mpp` patch bundles and classic `.jar` / `.rvp` formats with automated dependency resolution.

### 2. ReVanced CLI
```toml
cli-source = "ReVanced/revanced-cli"
cli-version = "latest"
patches-source = "ReVanced/revanced-patches"
```
Uses ReVanced CLI v4 / v5 argument structures, automatically handling `--patches`, `-b`, and custom aapt2 binaries on Android/Termux.

### 3. Xposed Modules (NPatch / LSPatch)
Inject Xposed modules directly into stock APKs without ReVanced patches:
```toml
[Discord]
cli-source = "7723mod/NPatch"
cli-version = "latest"
patches-source = "revenge-mod/revenge-xposed"
patches-version = "latest"
version = "auto"
github-dlurl = "https://github.com/discord/releases/..."
patcher-args = "-l 2"
```

### 4. Instafel Patcher (Instagram Alpha)
Natively compiles Instagram Alpha using the Instafel Patcher core:
```toml
[instagram-instafel]
cli-source = "instafel/p-rel"
patches-source = "instafel/pc-rel"
included-patches = "'unlock_developer_options' 'remove_ads' 'instafel'"
```

### 5. APKSigner (Sign-Only Mode)
Bypasses patching and signs the stock APK using the configured keystore:
```toml
[Stock-App]
cli-source = "apksigner"
apkmirror-dlurl = "https://www.apkmirror.com/apk/..."
```

### 6. Passthrough Mode
Copies the downloaded stock APK directly without modification:
```toml
[Pure-Stock]
cli-source = "none"
patches-source-host = "none"
apkmirror-dlurl = "https://www.apkmirror.com/apk/..."
```

---

## Patch Bundles & Selection

### Multi-Bundle Merging
Pass multiple patch bundles by supplying a quoted, space-separated list:

```toml
patches-source = "'MorpheApp/morphe-patches' 'other/patches'"
patches-source-host = "'github' 'gitlab'"
patches-version = "'latest' 'v1.2.3'"
```

### Bundle-Specific Patch Selection (`|` Delimiter)
When multiple patch bundles are loaded, use the pipe `|` delimiter to target bundles independently:

```toml
# Exclude Patch A in bundle 1, and Patch B in bundle 2:
excluded-patches = "'Patch A' | 'Patch B'"

# Skip bundle 1, include Patch X in bundle 2:
included-patches = "'' | 'Patch X'"
```
> [!NOTE]
> If no `|` delimiter is present, the patch list applies globally to all loaded bundles.

### Exclusive Patches Mode
- `exclusive-patches = true`: Excludes all patches by default; only `included-patches` will be applied.
- `exclusive-patches = "'jkennethcarino/adobo'"`: Makes only the specified bundle exclusive while retaining defaults for other bundles.

### Explicit Patch Folder (`patch-folder`)
Bypasses heuristic matching for repos containing patches for multiple applications:
```toml
patch-folder = "youtube"          # Strictly match patches inside the "youtube" folder
patch-folder = "ad backup geo"    # Match multiple folders
patch-folder = "*"                # Wildcard: maps every patch folder in the bundle
```

---

## Version Resolution & Architectures

### Target Versions (`version`)
- `"auto"`: Resolves the latest version supported by all selected patches (recommended).
- `"exp"`: Resolves the latest experimental version from patch metadata; falls back to `"latest"`.
- `"latest"`: Resolves the newest stable upstream version without checking patch compatibility.
- `"beta"`: Resolves the newest beta or alpha release.
- `"19.43.41"`: Pins to an exact application version.

### Target Version Code (`version-code`)
- `"auto"`: Auto-resolves the supported versionCode from patch metadata (e.g. Morphe Desktop).
- `"473623755"`: Explicit versionCode for APKMirror variant matching.
- Architecture-specific mapping:
  ```toml
  version-code = "arm64-v8a: 473623755 | arm-v7a: 473623748"
  ```

### Architecture (`arch`)
- `"both"`: Builds both `arm64-v8a` and `arm-v7a` (default).
- `"auto"`: Detects available architectures from upstream downloads.
- `"all"`: Universal architecture.
- Explicit: `"arm64-v8a"`, `"arm-v7a"`, `"x86_64"`, `"x86"`, or space-separated list (e.g. `"arm64-v8a x86_64"`).

---

## Download Sources (`dlurl`)

Every app must specify exactly one download source:

### 1. APKMirror (`apkmirror-dlurl`)
```toml
apkmirror-dlurl = "https://www.apkmirror.com/apk/google-inc/youtube"
apkmirror-example-url = "https://www.apkmirror.com/apk/google-inc/youtube/youtube-20-40-45-release/"
apkmirror-release-filter = "release" # Regex to filter release titles
version-filter = "^20\\."            # Regex to filter version numbers
prefer-dl-mode = "apk"               # "apk" or "bundle"
dpi = "320dpi nodpi auto"            # Screen DPI selection order
```

### 2. Uptodown (`uptodown-dlurl`)
```toml
uptodown-dlurl = "https://spotify.en.uptodown.com/android"
```

### 3. APKPure (`apkpure-dlurl`)
```toml
apkpure-dlurl = "https://apkpure.com/spotify-music-and-podcasts/com.spotify.music"
```

### 4. APKCombo (`apkcombo-dlurl`)
```toml
apkcombo-dlurl = "https://apkcombo.com/spotify/com.spotify.music"
```

### 5. GitHub Releases (`github-dlurl`)
```toml
github-dlurl = "https://github.com/owner/repo"
# Filter release tag or name:
github-release-regex = "^v[0-9]"
github-release-name-regex = "Stable"
# Match APK asset by architecture:
github-regex = "arm64-v8a: 'MyApp-v{version}-arm64\\.apk' | arm-v7a: 'MyApp-v{version}-arm\\.apk'"
# Exclude unwanted assets:
github-dlurl-exclude-filter = "debug|unaligned"
```

### 6. GitLab Releases (`gitlab-dlurl`)
```toml
gitlab-dlurl = "https://gitlab.com/owner/repo"
gitlab-release-regex = "^v[0-9]"
gitlab-regex = "MyApp-v{version}\\.apk"
```

### 7. Forgejo / Gitea / Codeberg (`forgejo-dlurl`)
```toml
forgejo-dlurl = "https://codeberg.org/owner/repo"
forgejo-release-regex = "^v[0-9]"
forgejo-regex = "MyApp-v{version}\\.apk"
```

### 8. Direct Download (`direct-dlurl`)
```toml
direct-dlurl = "https://example.com/downloads/com.example.app-1.0.0-all.apk"
```

### 9. Cache Repository (`cache_repo-dlurl`)
Fetches cached stock APKs from your dedicated assets repository (`$APKS_REPO`):
```toml
cache_repo-dlurl = "https://github.com/my-org/apks-cache/releases/tag/com.google.android.youtube"
```

### 10. Local File (`local-dlurl`)
Path to a local `.apk`, `.apks`, or `.xapk` file on disk:
```toml
local-dlurl = "/path/to/stock/com.google.android.youtube-20.40.45.apk"
```

---

## Magisk / KernelSU Modules

The builder can package apps into Magisk / KernelSU root modules:

```toml
build-mode = "both"         # "apk", "module", or "both" (default: "apk")
include-stock = "merged"    # "merged" (includes stock APK inside module), "split", or "disable"
module-prop-name = "my-mod" # Custom module ID (default: "<app>-<author>")
compression-level = 9       # ZIP compression level (0-9)
enable-module-update = true # Generate -update.json and commit to update branch
```

---

## Local Execution (`build.sh`)

You can run builds directly on Linux or Android (Termux):

### Syntax
```bash
./build.sh [--clean] [--config=path] [--allowed-apps="regex"] [--output=path] [filters...]
```

### Options & Arguments
- `--config=path`: Path to a `.toml` or compiled `.json` configuration.
- `--allowed-apps="regex"`: Only build apps matching the regex. Prefix with `!` to exclude (e.g. `!YouTube`).
- `--output=path`: Custom directory for finished artifacts (default: `build/`).
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
| `OVERRIDE_PATCHES_VERSION`| Forces a specific patches version for all apps |
| `NEXT_VER_CODE` | Explicit release version code (e.g. `2026.09.15-1`) |
| `TRAWL_URL` / `CFB_URL` | FlareSolverr / Cloudflare bypass scraper endpoints |
| `HTMLQ` / `YQ` / `AAPT2` | Custom binary paths |

---

## CI Workflow & Automation

GitHub Actions automates compilation, testing, and distribution:

1. **Config Compilation:** `.github/scripts/compile_patch_configs.py` parses `.github/configs/patches/*.toml` and generates `config.stable.json` and `config.beta.json`.
2. **Patch Change Inspection (`ci_check_app_patches.py`):**
   - Automatically detects new releases across GitHub, GitLab, and Forgejo/Gitea.
   - Computes granular checksums of patch bytecode per application.
   - Queues only the apps impacted by patch updates, preventing unnecessary rebuilds.
3. **App Version Tracking (`configs/app_versions.json`):**
   - Continuously scrapes APKMirror, Uptodown, and GitHub for new stock APK releases.
   - When a new version is detected, queues the app for build.
   - Adding `"_check_only_listed": true` limits checking to existing entries.

---

## Website Catalog & Metrics Synchronization

The builder maintains a public catalog (`data.json` and `data.json.gz`) consumed by web catalogs and Obtainium:

- **Target Website Repository:** Configured via the `WEBSITE_REPO` variable/environment (e.g. `your-username/your-username.github.io`) using `WEBSITE_REPO_TOKEN` (falling back to `PERSONAL_ACCESS_TOKEN`, then `GH_TOKEN` / `GITHUB_TOKEN`).
- **APKs Cache Repository (`$APKS_REPO`):** Dedicated assets repository configured via `APKS_REPO` using `APKS_REPO_TOKEN` (falling back to `PERSONAL_ACCESS_TOKEN`, then `GH_TOKEN` / `GITHUB_TOKEN`).
- **Per-Build Updates (`update_website_catalog.py`):** Pushes newly compiled build metadata, download URLs, applied patch lists, and SHA-256 checksums to the website repository.
- **Maintenance & Pruning (`sync_website_catalog.py`):**
  - Synchronizes real-time download counts from GitHub Releases.
  - Prunes deleted builds and empty app entries.
  - Reconciles `latestStable` and `latestBeta` variant pointers.
  - Protected by a circuit breaker requiring valid release data before modifying the catalog.
