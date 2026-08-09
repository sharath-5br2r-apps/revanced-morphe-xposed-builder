#!/usr/bin/env sh
yq eval-all '. as $item ireduce ({}; . * $item )' configs/patches/* >configs/config.manual.generated.toml

