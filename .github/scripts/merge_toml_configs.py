import sys
import glob
import os
import tomllib
import json

def main():
    if len(sys.argv) < 3:
        sys.exit(1)

    exclude_suffix = sys.argv[1]
    out_file = sys.argv[2]
    
    configs = [f for f in sorted(glob.glob('configs/patches/*.toml')) if not f.endswith(exclude_suffix)]
    merged = {}
    for f in configs:
        with open(f, 'rb') as fp:
            data = tomllib.load(fp)
            for k, v in data.items():
                if isinstance(v, dict):
                    merged[k] = v

    with open(out_file, 'w', encoding='utf-8') as out:
        json.dump(merged, out, indent=2)

if __name__ == '__main__':
    main()
