 #!/usr/bin/env sh
 yq eval-all '. as $item ireduce ({}; . * $item )' configs/patches/* > .github/configs/config.manual.generated.toml