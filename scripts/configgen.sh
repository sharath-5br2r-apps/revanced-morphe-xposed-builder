yq -o=toml eval-all '. as $item ireduce ({}; . * $item)' configs/patches/*  configs/header.dev.toml > configs/config.dev.toml
yq -o=toml eval-all '. as $item ireduce ({}; . * $item)'  configs/patches/* configs/header.stable.toml > configs/config.stable.toml
