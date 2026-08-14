# Configuration Guide & CLI Reference

Easily configure and build patched Android applications and Magisk/KernelSU modules locally or in GitHub Actions.

Adding a new app is as simple as adding a entry to a `.toml` file in `configs/patches/`:

```toml
[Some-App]
apkmirror-dlurl = "https://www.apkmirror.com/apk/inc/app"
# or uptodown-dlurl = "https://spotify.en.uptodown.com/android"
```

> [!WARNING]
> When a patch name contains a single quote, double it inside the string (e.g. `'Hide ''Get Music Premium'''`).

---

## 🛠️ Command Line Flags & Usage

The main build entry point is `build.sh`. It accepts the following arguments:

```bash
./build.sh [config_file] [exclusive_apps] [--config-update] [clean]
```

### CLI Parameters

| Parameter | Type | Description | Example |
| :--- | :--- | :--- | :--- |
| `clean` | Flag | Cleans temporary build directories (`temp/`, `build/`, `build.md`). | `./build.sh clean` |
| `--config-update` | Flag | Generates updated JSON/TOML configurations without triggering APK builds. | `./build.sh --config-update` |
| `[config_file]` | Path | Path to configuration file (`.json` or `.toml`). Default: auto-resolved `configs/config.toml`. | `./build.sh configs/config.stable.updated.json` |
| `[exclusive_apps]` | String | Space-separated list of app table names to build exclusively. | `./build.sh configs/config.stable.updated.json "YouTube YouTube-Music"` |

---

## 🔑 Environment Variables & Keystore Setup

The script reads signing credentials and GitHub API authentication from environment variables or a local `.env` file.

### Environment Variables

| Variable | Required | Description |
| :--- | :--- | :--- |
| `PERSONAL_ACCESS_TOKEN` | Optional | GitHub Personal Access Token for release queries and GitHub API rate limits. |
| `GITHUB_TOKEN` | Optional | Default fallback GitHub Token. |
| `KEYSTORE_BASE64` | Optional | Base64-encoded **`.bks`** (BouncyCastle format) keystore file for signing APKs/modules. |
| `KEYSTORE_PASSWORD` | Optional | Keystore password. |
| `KEYSTORE_ALIAS` | Optional | Keystore alias name. |
| `KEYSTORE_KEY_PASSWORD` | Optional | Key entry password. Defaults to `KEYSTORE_PASSWORD` if not set. |

> [!IMPORTANT]
> **Keystore Format Requirement**: The signing engine uses BouncyCastle provider with `--ks-type BKS`. `KEYSTORE_BASE64` **only accepts `.bks`** keystores. Standard `.jks` or `.p12` keystores will fail signing unless converted to `.bks`.

### 🔐 Optional Keystore Setup (`.env`)

You can create a `.env` file in the root directory to customize your APK signing keys:

```bash
# Generate base64 string from a BKS keystore: base64 -w 0 my-release-key.bks
KEYSTORE_BASE64="<your_base64_encoded_bks_keystore_data>"
KEYSTORE_PASSWORD="mysecretpassword"
KEYSTORE_ALIAS="mykeyalias"
KEYSTORE_KEY_PASSWORD="mykeypassword"
```

> [!NOTE]
> **Automatic Fallback**: If no `.env` or keystore environment variables are supplied, `utils.sh` automatically falls back to `.env.default` and signs APKs using the bundled debug keystore (`ks.keystore`).

---

## 💻 Local Build Setup (Termux / Linux / macOS)

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

### 2. Running Local Builds

```bash
# 1. Clean previous build artifacts
./build.sh clean

# 2. Update configurations from patch sources
./build.sh --config-update

# 3. Build all enabled apps in stable configuration
./build.sh configs/config.stable.updated.json

# 4. Or build a specific app exclusively (e.g. YouTube)
./build.sh configs/config.stable.updated.json "YouTube"
```

---

## ⚙️ Configuration Reference (`config.toml`)

Below is a complete reference of configuration options with their defaults:

```toml
compression-level = 9                # Magisk/KSU module zip compression level (1-9). default: 9
remove-rv-integrations-checks = true # Remove integration checks from ReVanced integrations. default: true
dpi = "nodpi anydpi 120-640dpi"      # DPI variants searched in order. default: "nodpi anydpi"

patches-source = "revanced/revanced-patches" # Bundle repository. default: "MorpheApp/morphe-patches"
# Supported Hosts: "github" and "gitlab". For custom gitlab instances, use "https://{repo-host}|gitlab". "none" disables fetching patches. Default: "github"

patches-source-host = "github"

# Version Options: 'latest' downloads latest stable release, 'dev' downloads latest dev release, 'absolutelatest' downloads whichever is latest (stable or dev). Or specify a version number (e.g. 'v1.2.3'). Default: "latest"

cli-source = "ReVanced/revanced-cli"             # CLI repository. default: "MorpheApp/morphe-desktop"
cli-source-host = "github"
rv-brand = "ReVanced Extended"                   # Rebrand prefix from 'ReVanced'. default: patches-source owner

patches-version = "v2.160.0"
cli-version = "v5.0.0"

[Some-App]
app-name = "SomeApp"                                       # Custom release name override. default: table name ('Some-App')
pkg-name = "com.some.app"                                 # Explicit package name override.
enabled = true                                             # Whether to build the app. default: true
build-mode = "both"                                        # 'both', 'apk' or 'module'. default: apk

# 'auto' gets the latest possible version supported by all included patches
# 'exp' gets the latest experimental version from patches.json.
# 'latest' gets the latest stable version without checking patch constraints.
# 'beta' gets the latest beta/alpha release.
version = "auto"                                           # 'auto', 'exp', 'latest', 'beta' or specific version (e.g. '17.40.41'). default: auto

# Optional CLI arguments (supports multiline strings)
patcher-args = """\
  -OdarkThemeBackgroundColor=#FF0F0F0F \
  -Oanother-option=value \
  """

excluded-patches = """\
  'Some Patch' \
  'Some Other Patch' \
  """                                                      # Whitespace-separated list of patches to exclude. Use '|' to separate per source bundle.

included-patches = "'Some Patch'"                          # Whitespace-separated list of non-default patches to include. default: "". Use '|' to separate per source bundle.
include-stock = "merged"                                   # 'merged', 'split' or 'disable'. default: merged
exclusive-patches = false                                  # Exclude all patches by default. Accepts true, false, or patch source string. default: false

apkmirror-dlurl = "https://www.apkmirror.com/apk/inc/app"
prefer-dl-mode = "bundle"                                  # 'bundle' or 'apk'. default: apk. If 'bundle', attempts bundle first, then falls back to apk.
apkmirror-example-url = "https://www.apkmirror.com/apk/inc/app/app-1-2-3-release/" # Example URL used to resolve app & package name.

uptodown-dlurl = "https://spotify.en.uptodown.com/android"
apkpure-dlurl = "https://apkpure.com/some-app/com.some.app"
apkcombo-dlurl = "https://apkcombo.com/some-app/com.some.app"
github-dlurl = "https://github.com/nvbangg/apks/releases/tag/com.some.app"
direct-dlurl = "https://website/com.google.android.youtube-20.40.45-all.apk"
local-dlurl = "/home/user/Downloads/com.google.android.youtube-20.40.45-all.apk"

module-prop-name = "some-app-module"                       # Module prop name.
dpi = "360-480dpi"                                         # Used to select APK variant from APKMirror. default: nodpi anydpi
arch = "arm64-v8a"                                         # 'auto', 'arm64-v8a', 'arm-v7a', 'all', 'both', 'both64', 'both32', 'multi'. default: auto

check-sig = false                                          # Whether to verify signature of downloaded APK. default: false
custom-microg-patches = "'Package Rename'"                 # Custom non-root patches to apply (disables internal microg scanning). default: none
```

---

## 🔀 Multiple Patch Sources

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
[Discord]
cli-source = "7723mod/NPatch"                            # Use NPatch as CLI
cli-version = "latest"
patches-source = "revenge-mod/revenge-xposed"            # Xposed module as patches bundle
patches-version = "latest"
version = "auto"
arch = "auto"
github-dlurl = "https://github.com/discord/releases/..."
```

---

## 🔑 Plain APK Signing

Sign APKs using `apksigner` without patching:

```toml
[plain-apk-signing]
cli-source = "apksigner"
cli-source-host = "none"
patches-source = "none"
patches-source-host = "none"
```

---

## 📁 Modular Configuration Directory

All configurations are organized inside `configs/patches/`:

- `config.toml`: Global base configurations and default values.
- `*.stable.toml`: Configurations merged into `stable` builds.
- `*.dev.toml`: Configurations merged into `dev` (pre-release) builds.

Configurations in `configs/patches/` without `stable` or `dev` in their filename are automatically included in **both** builds.
