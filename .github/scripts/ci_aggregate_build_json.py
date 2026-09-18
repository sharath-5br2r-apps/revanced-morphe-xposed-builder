import os
import json
import sys

def main():
    merged = {}
    artifact_dirs = [d for d in os.listdir(".") if os.path.isdir(d) and d.startswith("build-artifact-")]
    
    # Also check if build.json files are directly downloaded in current directory or subdirectories
    for root, _, files in os.walk("."):
        for f in files:
            if f == "build.json" and root != ".":
                filepath = os.path.join(root, f)
                try:
                    with open(filepath, "r", encoding="utf-8") as jf:
                        data = json.load(jf)
                        if isinstance(data, dict):
                            for k, v in data.items():
                                if not isinstance(v, dict) or not isinstance(merged.get(k), dict):
                                    merged[k] = v
                                    continue
                                # The current build.json format stores one target
                                # per key and its outputs in assets[]. Merge asset
                                # lists by filename so parallel build artifacts do
                                # not overwrite each other.
                                old = merged[k]
                                assets = {a.get("name"): a for a in old.get("assets", [])
                                          if isinstance(a, dict) and a.get("name")}
                                assets.update({a.get("name"): a for a in v.get("assets", [])
                                               if isinstance(a, dict) and a.get("name")})
                                merged[k] = {**old, **v}
                                if assets:
                                    merged[k]["assets"] = list(assets.values())
                except Exception as e:
                    print(f"[-] Error reading {filepath}: {e}", file=sys.stderr)

    out_file = "build.json"
    print(f"[+] Merged {len(merged)} app entries into {out_file}")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)

if __name__ == "__main__":
    main()
