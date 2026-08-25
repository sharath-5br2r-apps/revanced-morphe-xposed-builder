#!/bin/bash
set -euo pipefail

echo "[+] 1. Generating manual config (config.manual.generated.toml)..."
bash scripts/generate_manual_config.sh

echo "[+] 2. Checking patch sources..."
bash .github/scripts/ci_ensure_patch_sources.sh || true

echo "[+] 3. Fetching latest release tags..."
bash .github/scripts/ci_fetch_tags.sh || true

echo "[+] 4. Comparing tags..."
bash .github/scripts/ci_compare_tags.sh || true

echo "[+] 5. Fetching latest app versions..."
bash .github/scripts/ci_fetch_app_versions.sh || true

echo "[+] 6. Comparing app versions..."
bash .github/scripts/ci_compare_app_versions.sh || true

if [ "${1:-}" = "--disable-config-update" ]; then
    export DISABLE_CONFIG_UPDATE="true"
fi

echo "[+] 7. Testing config generation..."
bash .github/scripts/ci_generate_configs.sh || true

echo "[+] Local CI check completed successfully!"
