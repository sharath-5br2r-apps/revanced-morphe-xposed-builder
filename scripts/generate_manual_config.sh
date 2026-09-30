#!/bin/bash
set -euo pipefail

# Generate normalized merged patch TOML configs and combined manual config
python3 .github/scripts/ci_merge_patch_tomls.py
