# Configuration Reference

This document covers all configuration options for the patched APK builder: TOML app config keys, GitHub Actions **Secrets**, and GitHub Actions **Variables**.

---

## GitHub Actions Secrets & Variables

These are set under **Settings → Secrets and variables → Actions** in your repository.

### 🔐 Secrets

Secrets are **encrypted** and used for sensitive values. Set under the **Secrets** tab.

| Secret | Required | Description |
|--------|----------|-------------|
| `KEYSTORE_BASE64` | ✅ Yes | Base64-encoded `.keystore` file used to sign APKs. If unset, a keystore is auto-generated (not suitable for production). |
| `KEYSTORE_PASSWORD` | ✅ Yes | Password for the keystore store. |
| `PERSONAL_ACCESS_TOKEN` | ⚠️ Optional | GitHub Personal Access Token (PAT) with `repo` scope. Needed to push releases to other repos (e.g. `APKS_REPO`). Falls back to `GITHUB_TOKEN` (limited scope). |
| `APKS_REPO_TOKEN` | ⚠️ Optional | Dedicated PAT for `APKS_REPO`. Takes priority over `PERSONAL_ACCESS_TOKEN`. |

### ⚙️ Variables

Variables are **plain text** (not encrypted). Set under the **Variables** tab.

| Variable | Required | Description |
|----------|----------|-------------|
| `KEYSTORE_ALIAS` | ✅ Yes | Alias/entry name inside the keystore. |
| `APKS_REPO` | ⚠️ Optional | Target repository to upload built APKs (format: `owner/repo`). If unset, releases are uploaded to the current repository. |

### 🚀 Workflow Dispatch Inputs

#### Manual CI Workflow (`manual-ci.yml`)
- `config_file`: Select the generated or custom TOML/JSON config to use.
- `manual_config_file`: Optional custom config file path override.
- `exclusive_apps`: Regex or space-separated list of app table names to build.
- `remove_apks`: Regex pattern of cached APKs to purge before building.
- `patches_version`: Optional override for `patches-version` (`latest`, `auto`, `absolutelatest`, or semver tag).

#### CI / Update Versions Workflow (`ci.yml`)
- `skip_build`: Boolean option (`true`/`false`) to skip APK/module builds and only run version tracking.
- `disable_config_update`: Boolean option (`true`/`false`) to skip updating config JSONs while still tracking version changes.


#### Batch Dispatch All Configs (`batch-dispatch.yml`)
- `patches_version`: Select `patches-version` override (`latest`, `auto`, or `absolutelatest`). Dispatches app versions update first, then triggers `manual-ci.yml` for all TOML config files sequentially.

> **Note:** `GITHUB_TOKEN` is automatically provided by GitHub Actions and does not need to be set manually. It has limited scope (e.g. cannot push to other repositories).

> **Tip:** To generate `KEYSTORE_BASE64`, run:
> ```bash
> base64 -w 0 your.keystore
> ```

---

## TOML App Config Keys

These are set in your `.toml` config files under `configs/patches/` or `.github/configs/patches/`.

### App Identity

| Key | Required | Description |
|-----|----------|-------------|
| `enabled` | ✅ Yes | Set to `true` to include this app in the build. |
| `app-name` | ✅ Yes | Short app identifier (e.g. `youtube`, `gboard`). |
| `rv-brand` | ✅ Yes | Brand suffix for the output APK name (e.g. `revanced`, `morphe-hoodles`). |
| `pkg-name` | ⚠️ Optional | Android package name (e.g. `com.google.android.youtube`). If omitted, scraped automatically from the download source. |

### Build Options

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `build-mode` | ⚠️ Optional | `apk` | Build output type: `apk`, `module`, or `both`. |
| `arch` | ⚠️ Optional | `auto` | Target architecture: `arm64-v8a`, `arm-v7a`, `x86`, `x86_64`, `all`, `multi`, or `auto`. |
| `dpi` | ⚠️ Optional | `nodpi anydpi auto` | Space-separated list of accepted DPI variants. `auto` matches whatever is available. |
| `version` | ⚠️ Optional | `auto` | APK version to download. Use `auto` (patch-compatible), `latest`, `beta`, `absolutelatest`, or an exact version string (e.g. `17.8.7.939743344`). |
| `version-code` | ⚠️ Optional | `auto` | Target Android versionCode. `auto` automatically resolves supported versionCode from patch metadata. Can also be an explicit versionCode or mapped per-arch (`arm64-v8a: ... \| arm-v7a: ...`). |
| `prefer-dl-mode` | ⚠️ Optional | `apk` | Prefer downloading `apk` or `bundle` (APKM split) from APKMirror. |
| `patcher-args` | ⚠️ Optional | — | Extra arguments passed directly to the patcher CLI (e.g. `-f --continue-on-error`). |
| `enable-module-update` | ⚠️ Optional | `false` | Enable module update checks (global key, not per-app). |

### Patches

| Key | Required | Description |
|-----|----------|-------------|
| `patches-source` | ✅ Yes | Space-separated list of patch source repos in `'owner/repo'` format. |
| `patches-source-host` | ⚠️ Optional | Host for patch sources (default: `github`). Supports `github`, `gitlab`, `https://git.example.com|gitlab`, or `https://forge.example.com|forgejo`. |
| `patches-version` | ⚠️ Optional | Patch version to use: `latest`, `absolutelatest`, `auto`, or a semver tag. |
| `included-patches` | ⚠️ Optional | Patches to explicitly enable. Separate multi-source patches with `\|`. Names must be quoted. |
| `excluded-patches` | ⚠️ Optional | Patches to explicitly disable. Separate multi-source patches with `\|`. Names must be quoted. |
| `exclusive-patches` | ⚠️ Optional | Restrict a patch source to only be enabled for this app (prevents cross-source conflicts). |
| `custom-microg-patches` | ⚠️ Optional | Custom MicroG patch bundle path or source. |

### CLI (Patcher)

| Key | Required | Description |
|-----|----------|-------------|
| `cli-source` | ✅ Yes | GitHub repo for the patcher CLI (e.g. `ReVanced/revanced-cli`, `MorpheApp/morphe-desktop`). |
| `cli-source-host` | ⚠️ Optional | Host for the CLI source (default: `github`). Supports GitHub, custom GitLab, and Forgejo instances using `https://host|gitlab` or `https://host|forgejo`. |

### Download Sources

At least one `*-dlurl` key is required.

| Key | Description |
|-----|-------------|
| `apkmirror-dlurl` | APKMirror app listing URL (e.g. `https://www.apkmirror.com/apk/google-inc/gboard/`). |
| `apkmirror-example-dlurl` | A specific APKMirror release URL used as a template to construct version-specific URLs. Also accepted as `apkmirror-example-url`. |
| `apkmirror-release-filter` | Regex to filter APKMirror variants. Prefix with `!` to exclude. Supports alternation (e.g. `!(lite|beta)` to exclude lite and beta). |
| `uptodown-dlurl` | Uptodown app page URL. |
| `apkpure-dlurl` | APKPure app page URL. |
| `apkcombo-dlurl` | APKCombo app page URL. |
| `cache_repo_dlurl` | GitHub release tag URL used for downloading cached prebuilt stock APKs (e.g. `https://github.com/owner/apks/releases/tag/com.example.app`). |
| `github-dlurl` | GitHub release repo URL to download developer releases (supports `beta` pre-releases and tag URLs). |
| `gitlab-dlurl` | GitLab release repo URL to download developer releases. |
| `forgejo-dlurl` | Forgejo / Gitea release repo URL to download developer releases. |
| `archive-dlurl` | Internet Archive URL to download APK from. |
| `direct-dlurl` | Direct APK download URL (bypasses scraping). |

### Download Source Filters & Regex Options

| Key | Description |
|-----|-------------|
| `github-dlurl-regex` / `github-regex` | Regex or per-arch mapping (`arm64-v8a: ... \| arm-v7a: ...`) to filter release asset filenames for `github-dlurl`. |
| `github-release-regex` | Regex to filter release tags for `github-dlurl`. |
| `github-release-name-regex` | Regex to filter release names/titles for `github-dlurl`. |
| `gitlab-dlurl-regex` / `gitlab-regex` | Regex or per-arch mapping to filter release asset filenames for `gitlab-dlurl`. |
| `gitlab-release-regex` | Regex to filter release tags for `gitlab-dlurl`. |
| `gitlab-release-name-regex` | Regex to filter release names/titles for `gitlab-dlurl`. |
| `forgejo-dlurl-regex` / `forgejo-regex` | Regex or per-arch mapping to filter release asset filenames for `forgejo-dlurl`. |
| `forgejo-release-regex` | Regex to filter release tags for `forgejo-dlurl`. |
| `forgejo-release-name-regex` | Regex to filter release names/titles for `forgejo-dlurl`. |

### Other

| Key | Description |
|-----|-------------|
| `check-sig` | Set to `true` to verify APK signature before patching (default: `false`). |

---

## Quick Setup Checklist

### Minimum Required Secrets & Variables

```
Secrets:
  KEYSTORE_BASE64         ← base64 of your .keystore file
  KEYSTORE_PASSWORD       ← keystore store password

Variables:
  KEYSTORE_ALIAS          ← keystore key alias
```

### Optional (Recommended)

```
Secrets:
  PERSONAL_ACCESS_TOKEN   ← for pushing to APKS_REPO

Variables:
  APKS_REPO               ← e.g. your-username/your-apks-repo
```

### Minimal TOML Entry

```toml
[myapp-revanced]
enabled = true
app-name = "youtube"
rv-brand = "revanced"
cli-source = "ReVanced/revanced-cli"
patches-source = "'ReVanced/revanced-patches'"
apkmirror-dlurl = "https://www.apkmirror.com/apk/google-inc/youtube/"
```
