import sys
import glob
import os
import json
import subprocess

def load_toml(fpath):
    try:
        import tomllib
        with open(fpath, 'rb') as fp:
            return tomllib.load(fp)
    except Exception:
        out = subprocess.check_output(['yq', '-o=json', fpath]).decode()
        return json.loads(out)

def main():
    if len(sys.argv) < 3:
        sys.exit(1)

    exclude_suffix = sys.argv[1]
    out_file = sys.argv[2]
    
    configs = [f for f in sorted(glob.glob('configs/patches/*.toml')) if not f.endswith(exclude_suffix)]
    merged = {}
    for f in configs:
        data = load_toml(f)
        for k, v in data.items():
            if isinstance(v, dict):
                merged[k] = v

    with open(out_file, 'w', encoding='utf-8') as out:
        json.dump(merged, out, indent=2)

if __name__ == '__main__':
    main()
