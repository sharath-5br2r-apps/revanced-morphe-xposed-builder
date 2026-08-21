#!/bin/bash
set -euo pipefail

# Generate combined manual config from all patch files
yq eval-all '. as $item ireduce ({}; . * $item )' configs/patches/*.toml > configs/config.manual.generated.toml

# Generate dev manual config (setting patches-version = "dev")
yq eval-all '(. as $item ireduce ({}; . * $item )) | ."patches-version" = "dev"' configs/patches/*.toml > configs/config.manual.dev.generated.toml

# Generate stable manual config (excluding *.dev.toml and setting patches-version = "latest")
STABLE_FILES=$(find configs/patches -name "*.toml" ! -name "*.dev.toml" | sort)
# shellcheck disable=SC2086
yq eval-all '(. as $item ireduce ({}; . * $item )) | ."patches-version" = "latest"' $STABLE_FILES > configs/config.manual.stable.generated.toml
