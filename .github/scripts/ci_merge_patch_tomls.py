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
    
    # Filter out top-level global options blocks that don't contain a table header
    valid_tables = []
    for h, c in tables:
        if any(l.strip().startswith('[') for l in c.splitlines()):
            valid_tables.append((h, c))
    return valid_tables

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
            # extract table key e.g. [youtube-revanced] and app-name
            key_line = ""
            app_name = ""
            for l in content.splitlines():
                if l.strip().startswith('['):
                    key_line = l.strip().strip('[]"')
                elif l.strip().startswith('app-name'):
                    app_name = l.split('=')[1].strip().strip('\"\'')
            
            sort_app = app_name if app_name else (key_line if key_line else patchset_name)
            sort_key = key_line if key_line else patchset_name
            all_tables.append((sort_app, sort_key, header, content))

    # Group tables by distinct app-name
    from collections import defaultdict
    app_groups = defaultdict(list)
    for sort_app, sort_key, header, content in all_tables:
        app_groups[sort_app].append((sort_key, header, content))

    distinct_apps = sorted(app_groups.keys())
    total_distinct = len(distinct_apps)
    NUM_OUTPUT_FILES = 15
    apps_per_part = math.ceil(total_distinct / NUM_OUTPUT_FILES)

    part_idx = 1
    for i in range(0, total_distinct, apps_per_part):
        chunk_apps = distinct_apps[i:i + apps_per_part]
        chunk_items = []
        for app in chunk_apps:
            chunk_items.extend(app_groups[app])

        if not chunk_items:
            continue

        chunk_name = f"batch-part{part_idx}.toml"
        out_file = os.path.join(merged_dir, chunk_name)

        content = [f"# --- Batch TOML Part {part_idx} ({len(chunk_apps)} distinct apps, {len(chunk_items)} builds) ---\n"]
        for sort_key, header, tbl_content in chunk_items:
            if header:
                content.append(header)
            content.append(tbl_content)

        with open(out_file, "w", encoding="utf-8") as out_fp:
            out_fp.write("\n\n".join(content) + "\n")

        print(f"[+] Created '{chunk_name}' with {len(chunk_apps)} distinct apps ({len(chunk_items)} builds)")
        part_idx += 1

if __name__ == "__main__":
    main()
