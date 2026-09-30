import os
import json
import sys
from datetime import datetime

def parse_iso8601(ts_str):
    """Safely parses ISO 8601 timestamps for date comparison."""
    if not ts_str:
        return datetime.min
    try:
        # Handles standard ISO formats including trailing 'Z'
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except ValueError:
        return datetime.min

def main():
    merged_meta = {}
    merged_files = {}
    latest_meta_date = datetime.min
    base_schema = 1
    base_kind = "build"

    found_files = 0

    # Search for all build.json files in subdirectories
    for root, _, files in os.walk("."):
        for f in files:
            if f == "build.json" and root != ".":
                filepath = os.path.join(root, f)
                try:
                    with open(filepath, "r", encoding="utf-8") as jf:
                        data = json.load(jf)

                    if not isinstance(data, dict):
                        continue

                    found_files += 1

                    # Retain schema and kind
                    base_schema = data.get("schema", base_schema)
                    base_kind = data.get("kind", base_kind)

                    # Determine if this document has the latest meta / publishedAt
                    meta = data.get("meta", {})
                    current_pub = meta.get("publishedAt")
                    pub_dt = parse_iso8601(current_pub)

                    if pub_dt >= latest_meta_date:
                        latest_meta_date = pub_dt
                        merged_meta = meta

                    # Merge the "files" dictionary
                    files_data = data.get("files", {})
                    if isinstance(files_data, dict):
                        for file_key, file_val in files_data.items():
                            if not isinstance(file_val, dict):
                                continue

                            # If duplicate file artifact exists, keep the one with the newer date
                            if file_key in merged_files:
                                existing_dt = parse_iso8601(merged_files[file_key].get("publishedAt"))
                                incoming_dt = parse_iso8601(file_val.get("publishedAt"))
                                if incoming_dt >= existing_dt:
                                    merged_files[file_key] = file_val
                            else:
                                merged_files[file_key] = file_val

                except Exception as e:
                    print(f"[-] Error processing {filepath}: {e}", file=sys.stderr)

    if found_files == 0:
        print("[-] No build.json files found in subdirectories.", file=sys.stderr)
        return

    result = {
        "schema": base_schema,
        "kind": base_kind,
        "meta": merged_meta,
        "files": merged_files
    }

    out_file = "build.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"[+] Merged {len(merged_files)} artifacts from {found_files} files into {out_file} (Build: {merged_meta.get('build')})")

if __name__ == "__main__":
    main()
