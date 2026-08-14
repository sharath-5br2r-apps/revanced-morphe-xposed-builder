# Configuration Guide & Complete Options Reference

Easily configure and build patched Android applications and Magisk/KernelSU modules locally or in GitHub Actions.

Adding a new app is as simple as adding an entry to a `.toml` file in `configs/patches/`:

```toml
[youtube-morphe-exp]
apkmirror-dlurl = "https://www.apkmirror.com/apk/google-inc/youtube"
```

> [!WARNING]
> When a patch name contains a single quote, double it inside the string (e.g. `'Hide ''Get Music Premium'''`).

---

## 🛠️ Command Line Arguments & Usage

The primary entry point for building is `build.sh`. It accepts the following positional flags and arguments:

```bash
./build.sh [config_file] [exclusive_apps] [--config-update] [clean]
```

### CLI Parameters

| Parameter | Type | Description | Example |
| :--- | :--- | :--- | :--- |
| `clean` | Flag | Cleans temporary build directories (`temp/`, `build/`, `build.md`). | `./build.sh clean` |
| `--config-update` | Flag | Runs configuration update script (`config_update`) without triggering APK builds. | `./build.sh --config-update` |
| `[config_file]` | Path | Path to JSON or TOML configuration file. Default: auto-resolved `configs/config.toml` or updated JSON. | `./build.sh configs/config.stable.updated.json` |
| `[exclusive_apps]` | String | Space-separated list of exact TOML section keys (table headers) to build exclusively. | `./build.sh configs/config.stable.updated.json "youtube-morphe-exp youtube-music-morphe-anddea"` |

---

## 🔑 Environment Variables & Keystore Setup

The script reads signing credentials and GitHub API authentication from environment variables or a local `.env` file.

### Environment Variables

| Variable | Required | Description |
| :--- | :--- | :--- |
| `PERSONAL_ACCESS_TOKEN` | Optional | GitHub Personal Access Token for release queries and GitHub API rate limits. |
| `GH_TOKEN` / `GITHUB_TOKEN` | Optional | Fallback GitHub API tokens. |
| `KEYSTORE_BASE64` | Optional | Base64-encoded **`.bks`** (BouncyCastle format) keystore file for signing APKs and modules. |
| `KEYSTORE_PASSWORD` | Optional | Keystore password. |
| `KEYSTORE_ALIAS` | Optional | Keystore key alias. |
| `KEYSTORE_KEY_PASSWORD` | Optional | Key entry password. Defaults to `KEYSTORE_PASSWORD` if not specified. |
| `TRAWL_URL` | Optional | URL of running Trawl Cloudflare solver service (e.g. `http://localhost:8191`). Skips if omitted. |
| `CFB_URL` | Optional | URL of running CloudflareBypassForScraping solver service (e.g. `http://localhost:8000`). Skips if omitted. |

### 🔐 Optional Keystore Setup (`.env`)

You can create a `.env` file in the root directory to customize your APK signing keys:

```bash
# Generate base64 string from a BKS keystore: base64 -w 0 my-release-key.bks
KEYSTORE_BASE64="<your_base64_encoded_bks_keystore_data>"
KEYSTORE_PASSWORD="mysecretpassword"
KEYSTORE_ALIAS="mykeyalias"
KEYSTORE_KEY_PASSWORD="mykeypassword"
```

> [!IMPORTANT]
> **Keystore Format Requirement**: The signing engine uses BouncyCastle provider with `--ks-type BKS`. `KEYSTORE_BASE64` **only accepts `.bks`** keystores. Standard `.jks` or `.p12` keystores will fail signing unless converted to `.bks`.
>
> **Automatic Debug Fallback**: If no `.env` or keystore environment variables are supplied, `utils.sh` automatically falls back to `.env.default` and signs built APKs using the bundled debug keystore (`ks.keystore`).

---

## 💻 Local Building Setup (Termux / Linux / macOS)

### 1. Prerequisites

Ensure the following tools are installed on your system:

- **Bash** (`bash` 4.4+)
- **OpenJDK 21** (`java`)
- **jq** (`jq`)
- **Python 3** (`python3`)
- **cURL** (`curl`)

On **Termux (Android)**:
```bash
pkg update && pkg install openjdk-21 jq python curl bash
```

On **Ubuntu / Debian**:
```bash
sudo apt update && sudo apt install openjdk-21-jre-headless jq python3 curl bash
```

### 2. Generating TOML Configurations for Local Builds

Local building reads modular TOML configuration files from `configs/patches/`. You can compile these TOML files into combined manual configuration files using the generator script:

```bash
# Generate both config.manual.generated.toml and config.manual.stable.generated.toml (with patches-version = "latest")
./scripts/generate_manual_config.sh
```

Or compile JSON configs from patch sources using `./build.sh --config-update`.

### 3. Running Local Builds

```bash
# 1. Clean previous build artifacts
./build.sh clean

# 2. Generate merged local TOML configurations
./scripts/generate_manual_config.sh

# 3. Build using the generated stable manual TOML config
./build.sh configs/config.manual.stable.generated.toml

# 4. Or build a specific app exclusively using its TOML section key
./build.sh configs/config.manual.stable.generated.toml "youtube-morphe-exp"
```

---

## ⚙️ Complete Options Reference (`config.toml`)

Below is the complete reference of all supported global and app-level configuration keys:

```toml
# ==============================================================================
# Global Base Configurations (Top-level)
# ==============================================================================

compression-level = 9                # Magisk/KernelSU module zip compression level (1-9). default: 9
remove-rv-integrations-checks = true # Remove integration checks from ReVanced integrations. default: true
enable-module-update = true          # Enable Magisk/KernelSU module auto-update prop in module.prop. default: true
dpi = "nodpi anydpi 120-640dpi"      # Default DPI packages searched in order. default: "nodpi anydpi"

patches-source = "MorpheApp/morphe-patches" # Patch bundle repository. default: "MorpheApp/morphe-patches"
patches-source-host = "github"              # Host type: "github", "gitlab", "https://{repo-host}|gitlab", or "none". default: "github"
patches-version = "latest"                  # Version option: 'latest', 'dev', 'absolutelatest', or version string (e.g. 'v1.2.3'). default: "latest"

cli-source = "MorpheApp/morphe-desktop"     # CLI engine repository. default: "MorpheApp/morphe-desktop"
cli-source-host = "github"                 # Host type: "github", "gitlab", "https://{repo-host}|gitlab", or "none". default: "github"
cli-version = "latest"                     # CLI version option. default: "latest"

rv-brand = "ReVanced"                       # Rebrand prefix from 'ReVanced'. default: patches-source owner

# ==============================================================================
# App-Level Configurations (Per-Section Table)
# ==============================================================================

> [!NOTE]
> **TOML Section Keys vs. Display Names**: The build system, CLI arguments (`exclusive_apps`), and CI tracking files always identify apps by their **exact TOML section key / table header** (such as `[youtube-morphe-exp]` or `[youtube-music-morphe-anddea]`). The `app-name` setting is purely an optional display override for generated release output names.

[youtube-morphe-exp]
app-name = "YouTube"                                       # Custom display name override for release outputs. default: table section key ('youtube-morphe-exp')
pkg-name = "com.google.android.youtube"                    # Explicit package name override to avoid network checks during caching.
enabled = true                                             # Whether to build this app table. default: true
build-mode = "both"                                        # 'both', 'apk', or 'module'. default: apk

# App Version Resolution:
# 'auto' gets the highest version supported by all included patches.
# 'exp' gets the latest experimental version from patches.json (falls back to 'latest' if none found).
# 'latest' gets the latest stable version without checking patch constraints.
# 'beta' gets the latest beta/alpha release.
version = "auto"                                           # 'auto', 'exp', 'latest', 'beta', or explicit version (e.g. '20.08.35'). default: auto

# Optional CLI arguments passed directly to patcher CLI (supports multiline strings)
patcher-args = """\
  -OdarkThemeBackgroundColor=#FF0F0F0F \
  -Oanother-option=value \
  """

# Patch Selection
excluded-patches = """\
  'Some Patch' \
  'Some Other Patch' \
  """                                                      # Whitespace-separated list of patches to exclude. Use '|' to separate per patch bundle.

included-patches = "'Some Patch'"                          # Whitespace-separated list of non-default patches to include. default: "". Use '|' to separate per patch bundle.
include-stock = "merged"                                   # Stock APK inclusion mode: 'merged', 'split', or 'disable'. default: merged
exclusive-patches = false                                  # Exclude all patches by default unless specified. Accepts true, false, or patch source string. default: false

# Download URLs (Specify at least one)
apkmirror-dlurl = "https://www.apkmirror.com/apk/google-inc/youtube"
prefer-dl-mode = "bundle"                                  # 'bundle' or 'apk'. default: apk. If 'bundle', attempts bundle download first, then falls back to apk.
apkmirror-example-url = "https://www.apkmirror.com/apk/google-inc/youtube/youtube-20-08-35-release/" # Example URL used to resolve app & package name.

uptodown-dlurl = "https://youtube.en.uptodown.com/android"
apkpure-dlurl = "https://apkpure.com/youtube/com.google.android.youtube"
apkcombo-dlurl = "https://apkcombo.com/youtube/com.google.android.youtube"
github-dlurl = "https://github.com/nvbangg/apks/releases/tag/com.google.android.youtube"
direct-dlurl = "https://website/com.google.android.youtube-20.40.45-all.apk"
local-dlurl = "/home/user/Downloads/com.google.android.youtube-20.40.45-all.apk" # Local file path relative to builder directory or absolute path.

# Variant & Hardware Selection
module-prop-name = "youtube-module"                        # Custom module prop name for Magisk/KSU. default: `${table_name}-jhc`
dpi = "360-480dpi"                                         # Used to select APK variant from APKMirror ('auto' matches whatever is available). default: nodpi anydpi
arch = "arm64-v8a"                                         # Options: 'auto', 'arm64-v8a', 'arm-v7a', 'all', 'both', 'both64', 'both32', 'multi'. default: auto

# Security & Patching Overrides
check-sig = false                                          # Whether to verify signature of downloaded APK. default: false
custom-microg-patches = "'Package Rename'"                 # Custom non-root patches to apply (disables internal microg scanning). Setting to "'None'" disables microg scanning completely. default: none
```

---

## 🔀 Multiple Patch Sources & Per-Bundle Filtering

Pass multiple patch bundles by specifying `patches-source` as a quoted list:

```toml
# Single-line format
patches-source = "'MorpheApp/morphe-patches' 'other/patches'"

# Multiline format
patches-source = """\
  'MorpheApp/morphe-patches' \
  'other/patches' \
  """

patches-source-host = "'github' 'gitlab'"
patches-version = "'latest' 'v1.2.3'"
```

> [!TIP]
> **Per-bundle patch selection**: Separate patch lists with `|` to control each bundle independently:
> ```toml
> patches-source = "'MorpheApp/morphe-patches' 'other/patches'"
> excluded-patches = "'Patch A' | 'Patch B'"    # Patch A from bundle 1, Patch B from bundle 2
> included-patches = "'' | 'Patch X'"           # nothing from bundle 1, Patch X from bundle 2
> ```

---

## 🧩 Xposed Modules (NPatch / LSPatch)

Inject Xposed modules natively using `7723mod/NPatch` or `LSPatch` directly from your config:

```toml
[discord-npatch-revenge]
cli-source = "7723mod/NPatch"                            # Use NPatch as CLI engine
cli-version = "latest"
patches-source = "revenge-mod/revenge-xposed"            # Xposed module as patches bundle
patches-version = "latest"
version = "auto"                                         # 'auto' safely falls back to 'latest'
arch = "auto"
github-dlurl = "https://github.com/discord/releases/..."
```

---

## 📸 Instafel Patcher Engine (Instagram Alpha)

Build Instagram Alpha natively using the Instafel Patcher engine (`instafel/p-rel`) and Patcher Core (`instafel/pc-rel`):

```toml
[instagram-instafel]
cli-source = "instafel/p-rel"                            # Use Instafel Patcher CLI
cli-version = "latest"
patches-source = "instafel/pc-rel"                       # Provide Instafel Patcher Core
patches-version = "latest"
included-patches = "'unlock_developer_options' 'remove_snooze_warning' 'remove_ads' 'instafel'"
```

---

## 🔑 Plain APK Signing

Sign APKs using `apksigner` without applying patches:

```toml
[plain-apk-signing]
cli-source = "apksigner"
cli-source-host = "none"
patches-source = "none"
patches-source-host = "none"
```

---

## 📁 Modular Configuration Directory Structure

All configurations are organized inside `configs/patches/`:

- `config.toml`: Global base configurations and default values.
- `*.stable.toml`: Configurations merged into `stable` builds.
- `*.dev.toml`: Configurations merged into `dev` (pre-release) builds.

Configurations in `configs/patches/` without `stable` or `dev` in their filename are automatically included in **both** builds.

---

## 🔄 Automatic App Version Checking

The CI workflow automatically detects when a new version of an app is released on APKMirror, Uptodown, or Archive.org.

### How it Works
1. **Version Fetching**: During the CI run, it reads all enabled apps from the `configs/patches/*.toml` configurations and queries the URLs (`apkmirror-dlurl`, `uptodown-dlurl`, etc.).
2. **Comparison**: It checks the newly fetched versions against the currently stored versions in `configs/app_versions.json`.
3. **Triggering**: If a new version is detected, the app section key is added to a temporary active list, and the CI is triggered to build it.

### Tracking File (`configs/app_versions.json`)
App versions are permanently tracked and committed to `configs/app_versions.json`.

**Selective Checking:** To restrict CI version checking to specific apps (saving network resources), add `"_check_only_listed": true` to the top level of `app_versions.json`. When enabled, the script will only check for updates for keys already listed in the file.
