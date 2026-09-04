
<div align="center"><h1><img src="https://raw.githubusercontent.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/a5af1123e55c63119c6b81be894602e2f032fe08/.github/assets/icon.png"> <img src="https://raw.githubusercontent.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/a5af1123e55c63119c6b81be894602e2f032fe08/.github/assets/icon1.png"><br>ReVanced & Morphe Builder</h1></div>

<p align="center"><b>Automatically builds and publishes APKs & Magisk/KernelSU Modules whenever new patches are released.</b></p>

<p align="center"><a href="https://sharath-5br2r.github.io/catalog"><img src="https://img.shields.io/badge/Download-21a378?style=flat&logo=data:image/svg+xml;base64,PHN2ZyBmaWxsPSIjZmZmZmZmIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48cGF0aCBkPSJNNSAyMGgxNHYtMkg1djJ6TTE5IDloLTRWM0g5djZINWw3IDcgNy03eiIvPjwvc3ZnPg==&logoColor=white"></a> <a href="#credits--acknowledgements"><img src="https://img.shields.io/badge/Donate%20to%20Upstream-ea4335?style=flat&logo=ko-fi&logoColor=white"></a></p>

<p align="center"><a href="https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder"><img src="https://img.shields.io/github/stars/sharath-5br2r-apps/revanced-morphe-xposed-builder?label=Stars&logo=github&style=social"></a> <a href="https://sharath-5br2r.github.io/catalog"><img src="https://img.shields.io/github/downloads/sharath-5br2r-apps/revanced-morphe-xposed-builder/total?logo=data:image/svg+xml;base64,PHN2ZyBmaWxsPSIjMDAwMDAwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0Ij48cGF0aCBkPSJNNSAyMGgxNHYtMkg1djJ6TTE5IDloLTRWM0g5djZINWw3IDcgNy03eiIvPjwvc3ZnPg==&label=Downloads&style=social"></a></p>

<p align="center"><a href="https://sharath-5br2r.github.io/catalog"><img src="https://visitor-badge.laobi.icu/badge?page_id=sharath-5br2r.github.io.my-patched-apks&left_text=Website%20Visitors&right_color=%231283c3&format=true&query_only=true"></a> <a href="https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder"><img src="https://visitor-badge.laobi.icu/badge?page_id=sharath-5br2r.my-patched-apks&left_text=GitHub%20Visitors&format=true"></a> </p>

---

<p align="center"><a href="https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/issues"><img src="https://img.shields.io/badge/Issues-2f2f2f?style=flat&logo=github&logoColor=white"></a> <a href="https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/pulls"><img src="https://img.shields.io/badge/Pull%20Requests-2f2f2f?style=flat&logo=github&logoColor=white"></a> <a href="https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/discussions"><img src="https://img.shields.io/badge/Discussions-2f2f2f?style=flat&logo=github&logoColor=white"></a> <a href="https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/actions"><img src="https://img.shields.io/badge/Actions-2f2f2f?style=flat&logo=github&logoColor=white"></a></p>

---

## 🤝 Support the Upstream Projects

Building, testing, and maintaining these patches and automated workflows relies on the dedication of upstream developers and open-source teams.

- **❤️ [Donate to Upstream Developers](#credits--acknowledgements)** if you can (ReVanced, Morphe, and independent patch maintainers).
- **⭐ Star this repository** (This is a huge help!)
- **📢 Share the project** with others who might find it useful.

Thank you to everyone in the open-source community who helps keep these projects alive!

---

> [!NOTE]
>
> 🌐 **[Visit Download Website](https://sharath-5br2r.github.io/catalog)**
>
> For the best experience, please download from the website. It features:
>
> - 📱 **The complete list of every supported app.**
> - 📦 Clear separation between **Stable**, **Beta** and **Variant** builds.
> - 🏷️ Beautifully organized version numbers and download tracking.
> - 🔄 Step-by-step instructions on how to set up automatic updates using **Obtainium** and easy **Add to Obtainium** button.
>
> **🤖 Fully Automated Builds**
>
> All APKs and modules in this repository are 100% automated. If you need help, please direct your feedback to the right place:
>
> - 🧩 **Patch Issues:** If a specific feature/mod is broken (e.g., ads are showing), please open an issue in the **respective patch developer's repository**.
> - 🛠️ **Builder Issues:** If an app fails to build, or the download links are broken, **[open an Issue here on GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/issues/new/choose)**.
> - 💬 **General Help & Requests:** Need help installing, or want to request a new app? **[Open an Issue here on GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/issues/new/choose)** or **[open a discussion here on GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder/discussions/new?category=general)**.

---

## 🛠️ Local Building & Command Line Usage

You can build APKs and Magisk/KSU modules locally on Android (Termux), Linux, or macOS.

### Prerequisites
- **Bash** (`bash` 4.4+)
- **OpenJDK 21** (`java`)
- **jq** (`jq`)
- **Python 3** (`python3`)
- **cURL** (`curl`)

### Command Line Flags & Usage
```bash
./build.sh [--clean] [--config-update] [--config=path/to/config] [--allowed-apps="<regex>"] [--output=path/to/output/dir]
```

- **Clean build artifacts**: `./build.sh --clean`
- **Update configurations**: `./build.sh --config-update`
- **Build with config file**: `./build.sh --config=configs/config.stable.updated.json`
- **Filter apps by regex**: `./build.sh --config=configs/config.stable.updated.json --allowed-apps="YouTube.*"`
- **Custom output directory**: `./build.sh --config=configs/config.stable.updated.json --output=dist/`
- *(Positional syntax `./build.sh [config_file] [app_regex...]` remains backwards-compatible).*

### Optional Keystore Setup (`.env`)
Create a `.env` file in the project root to sign APKs with a custom keystore:

```bash
KEYSTORE_BASE64="<base64_encoded_keystore>"
KEYSTORE_PASSWORD="mysecretpassword"
KEYSTORE_ALIAS="mykeyalias"
KEYSTORE_KEY_PASSWORD="mykeypassword"
```

*If no `.env` or keystore environment variables are supplied, `utils.sh` automatically falls back to `.env.default` and uses the bundled debug keystore (`ks.keystore`). For complete configuration options, see [CONFIG.md](CONFIG.md).*

---

## 💖 Credits & Acknowledgements

This automated builder would not be possible without the incredible work and dedication of the open-source Android community. A massive thank you to:

- **Upstream Repositories & Tools:**
  - **[nullcpy/rvb](https://github.com/nullcpy/rvb)** for the foundational builder workflow.
  - **[peternmuller](https://github.com/peternmuller)**, **[nvbangg](https://github.com/nvbangg/revanced-morphe-builder)**, and **[j-hc](https://github.com/j-hc)** for build scripts, CI/CD pipelines, and automation logic.
  - **[ReVanced](https://github.com/revanced)** ([Donate to ReVanced](https://revanced.app/donate)) & **[MorpheApp](https://github.com/MorpheApp)** for patcher engines and core tools.
- **Upstream Patch Developers:**
  - **[Anddea](https://github.com/anddea)** (ReVanced Patches)
  - **[crimera](https://github.com/crimera)** (Piko)
  - **[jasonwu1994](https://github.com/jasonwu1994)** (Gboard Patches)
  - **[arandomhooman](https://github.com/arandomhooman)** (Hooman's Morphe Patches)
  - **[rushiranpise](https://github.com/rushiranpise)** (Rushiranpise Morphe Patches)
  - **[hoo-dles](https://github.com/hoo-dles)** (Hoo-dles Morphe Patches)
  - **[binarymend](https://github.com/binarymend)** (Binarymend Morphe Patches)
  - **[BholeyKaBhakt](https://github.com/BholeyKaBhakt)** (ReVanced Patches Xtra)
  - **[icysymmetra](https://github.com/icysymmetra)** (TikTok Patches)
  - **[revenge-mod](https://github.com/revenge-mod)** (Revenge Xposed)
  - **[Paresh-Maheshwari](https://gitlab.com/Paresh-Maheshwari)** (Paresh Patches)
  - **[inotia00](https://gitlab.com/inotia00)** (X-Shim)
  - **[browzomje](https://github.com/browzomje)** (Browzomje Patches)

_If you enjoy using these builds, please consider starring their upstream repositories and supporting the original patch developers!_
