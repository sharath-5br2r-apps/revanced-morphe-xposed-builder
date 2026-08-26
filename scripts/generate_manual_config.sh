#!/bin/bash
set -euo pipefail

# Generate normalized merged patch TOML configs if needed
python3 .github/scripts/ci_merge_patch_tomls.py 2>/dev/null || true

# Generate combined manual config from all patch files
yq eval-all '. as $item ireduce ({}; . + $item )' configs/patches/*.toml > configs/config.manual.generated.toml
