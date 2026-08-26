import os
import glob
import math

def get_tables_with_headers(filepath):
    tables = []
    current_lines = []
    header_comment = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith('['):
                if current_lines:
                    tables.append((''.join(header_comment), ''.join(current_lines)))
                    current_lines = []
                    header_comment = []
                current_lines.append(line)
            else:
                if not current_lines and (line.startswith('#') or not line.strip()):
                    header_comment.append(line)
                else:
                    current_lines.append(line)
        if current_lines:
            tables.append((''.join(header_comment), ''.join(current_lines)))
    return tables

def main():
    base = "configs/patches"
    merged_dir = os.path.join(base, "merged")
    
    # Remove old merged files
    for old_f in glob.glob(os.path.join(merged_dir, "*.toml")):
        try:
            os.remove(old_f)
        except OSError:
            pass
    os.makedirs(merged_dir, exist_ok=True)

    toml_files = sorted(glob.glob(os.path.join(base, "*.toml")))

    # Collect all (table_key, header, table_content) blocks across all patchsets
    all_tables = []
    for fpath in toml_files:
        fname = os.path.basename(fpath)
        patchset_name = fname.replace(".toml", "")
        tables = get_tables_with_headers(fpath)
        for header, content in tables:
            # extract table key e.g. [youtube-revanced]
            key_line = ""
            for l in content.splitlines():
                if l.strip().startswith('['):
                    key_line = l.strip().strip('[]"')
                    break
            sort_key = key_line if key_line else patchset_name
            all_tables.append((sort_key, header, content))

    # Standardize output by sorting deterministically by table key
    all_tables.sort(key=lambda x: x[0])

    total_apps = len(all_tables)
    NUM_OUTPUT_FILES = 15
    apps_per_file = math.ceil(total_apps / NUM_OUTPUT_FILES)

    for idx in range(NUM_OUTPUT_FILES):
        start_idx = idx * apps_per_file
        end_idx = min(start_idx + apps_per_file, total_apps)
        chunk_items = all_tables[start_idx:end_idx]
        
        if not chunk_items:
            continue

        chunk_name = f"batch-part{idx + 1}.toml"
        out_file = os.path.join(merged_dir, chunk_name)

        content = [f"# --- Batch TOML Part {idx + 1}/{NUM_OUTPUT_FILES} ({len(chunk_items)} apps) ---\n"]
        for patchset_name, header, tbl_content in chunk_items:
            if header:
                content.append(header)
            content.append(tbl_content)

        with open(out_file, "w", encoding="utf-8") as out_fp:
            out_fp.write("\n\n".join(content) + "\n")

        print(f"[+] Created '{chunk_name}' with {len(chunk_items)} apps")

if __name__ == "__main__":
    main()
