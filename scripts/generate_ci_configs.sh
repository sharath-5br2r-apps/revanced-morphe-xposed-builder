#!/bin/bash
set -euo pipefail

# Generate combined manual config from all patch files
yq eval-all '. as $item ireduce ({}; . + $item )' configs/patches/*.toml > configs/config.manual.generated.toml
