import os
import glob
import math

# Keys that live in the TOML root section and must be transferred into every
# app table when we lose the root section during aggregation.
_INHERIT_KEYS = ("patches-source", "patch-brand")


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


def get_file_defaults(filepath):
    """Read patches-source and patch-brand from the root section (before the first [table]).

    Returns a dict {key: raw_line} for the keys found so we can inject the
    original line verbatim into each table block.
    """
    found = {}
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith('['):
                break  # hit first table — root section done
            if stripped and not stripped.startswith('#') and '=' in stripped:
                key = stripped.split('=', 1)[0].strip()
                if key in _INHERIT_KEYS:
                    found[key] = line  # preserve original formatting
    return found


def inject_defaults_into_table(table_content, defaults):
    """Inject missing root-level keys right after the [header] line.

    If the table already explicitly sets a key (e.g. its own patches-source)
    it is left untouched — app-level values always win.
    """
    if not defaults:
        return table_content

    lines = table_content.splitlines(keepends=True)
    # Keys the table already defines (skip the [header] line at index 0)
    existing_keys = set()
    for l in lines[1:]:
        if '=' in l and not l.strip().startswith('#'):
            existing_keys.add(l.split('=', 1)[0].strip())

    to_inject = [raw for key, raw in defaults.items() if key not in existing_keys]
    if not to_inject:
        return table_content

    # Insert the missing lines immediately after the [header]
    return lines[0] + ''.join(to_inject) + ''.join(lines[1:])


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
        file_defaults = get_file_defaults(fpath)
        tables = get_tables_with_headers(fpath)
        for header, content in tables:
            # Bake patches-source and patch-brand from the root into each table so
            # the merged batch TOML is self-contained (no root to inherit from).
            content = inject_defaults_into_table(content, file_defaults)
            # extract table key e.g. [youtube-revanced] and app-name
            key_line = ""
            app_name = ""
            for l in content.splitlines():
                if l.strip().startswith('['):
                    key_line = l.strip().strip('[]"')
                elif l.strip().startswith('app-name'):
                    app_name = l.split('=')[1].strip().strip("\"' ")

            sort_app = app_name if app_name else (key_line if key_line else patchset_name)
            sort_key = key_line if key_line else patchset_name
            all_tables.append((sort_app, sort_key, header, content))

    # Group tables by individual variant table key instead of grouping by app-name
    from collections import defaultdict
    app_groups = defaultdict(list)
    for sort_app, sort_key, header, content in all_tables:
        app_groups[sort_key].append((sort_key, header, content))

    sorted_app_keys = sorted(app_groups.keys(), key=lambda a: (len(app_groups[a]), a), reverse=True)
    NUM_OUTPUT_FILES = 16

    parts_apps = [[] for _ in range(NUM_OUTPUT_FILES)]
    parts_items = [[] for _ in range(NUM_OUTPUT_FILES)]
    parts_build_count = [0] * NUM_OUTPUT_FILES

    # Greedily assign each individual table variant to the batch part with the lowest current build count
    for app in sorted_app_keys:
        items = app_groups[app]
        min_idx = min(range(NUM_OUTPUT_FILES), key=lambda i: (parts_build_count[i], len(parts_apps[i])))
        parts_apps[min_idx].append(app)
        parts_items[min_idx].extend(items)
        parts_build_count[min_idx] += len(items)

    for part_idx in range(1, NUM_OUTPUT_FILES + 1):
        chunk_apps = parts_apps[part_idx - 1]
        chunk_items = parts_items[part_idx - 1]

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

if __name__ == "__main__":
    main()
