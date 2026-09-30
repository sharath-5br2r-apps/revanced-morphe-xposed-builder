#!/bin/bash
set -euo pipefail

echo "[!] Warning: This will delete ALL releases in the repository!"
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[-] Operation cancelled."
    exit 0
fi

echo "[+] Fetching list of all releases..."
mapfile -t RELEASES < <(gh release list --limit 1000 --json tagName --jq '.[].tagName')

if [ ${#RELEASES[@]} -eq 0 ]; then
    echo "[+] No releases found."
    exit 0
fi

echo "[+] Found ${#RELEASES[@]} releases to delete."

for tag in "${RELEASES[@]}"; do
    echo "[+] Deleting release: $tag..."
    gh release delete "$tag" --yes || true
done

echo "[+] All releases deleted successfully!"
