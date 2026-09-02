import json
import sys

def main():
    flavor = sys.argv[1] if len(sys.argv) > 1 else "manual"
    json_path = f"aggregated_out/build.{flavor}.json"
    md_path = f"aggregated_out/build.{flavor}.md"

    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error loading {json_path}: {e}")
        return

    if not data:
        print(f"No entries found in {json_path}")
        return

    # Sort entries deterministically by app brand/name then architecture
    sorted_entries = sorted(data.items(), key=lambda x: (x[1].get("name", x[0]), x[1].get("arch", "")))

    app_lines = []
    seen_apps = set()
    cli_set = []
    patches_dict = {}

    for key, entry in sorted_entries:
        name = entry.get("name", key)
        arch = entry.get("arch", "")
        version = entry.get("version", "")
        cli_info = entry.get("cli", "")
        patches_info = entry.get("patches", "")
        changelog = entry.get("changelog", "")
        release_notes = entry.get("release_notes", "")

        app_line = f"{name} ({arch}): {version}  " if arch else f"{name}: {version}  "
        if app_line not in seen_apps:
            seen_apps.add(app_line)
            app_lines.append(app_line)

        if cli_info and cli_info not in cli_set:
            cli_set.append(cli_info)

        if patches_info:
            p_items = [p.strip() for p in patches_info.split() if p.strip()]
            c_items = [c.strip() for c in changelog.split() if c.strip()] if changelog else []
            for idx, p in enumerate(p_items):
                if p not in patches_dict:
                    c_url = c_items[idx] if idx < len(c_items) and c_items[idx] != "passthrough" else ""
                    patches_dict[p] = (c_url, release_notes)

    sections = []

    # 1. App builds block
    if app_lines:
        sections.append("\n".join(app_lines))

    # 2. Notes block
    notes = """**Notes:**  
• Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest) or [MicroG](https://github.com/ReVanced/GmsCore/releases/latest), required for Google APKs.  
• Use [Zygisk Detach](https://github.com/j-hc/zygisk-detach) to stop Play Store from updating Modules.  

[GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder) | [Website](https://sharath-5br2r-apps.github.io)"""
    sections.append(notes)

    # 3. CLI block
    cli_lines = [f"CLI: {c}  " for c in cli_set]
    if cli_lines:
        sections.append("\n".join(cli_lines))

    # 4. Patches & Changelog block
    patches_lines = []
    for p_info, (cl_url, rel_notes) in patches_dict.items():
        p_str = f"Patches: {p_info}  "
        if cl_url:
            p_str += f"\n[Changelog]({cl_url})"
            if rel_notes:
                tag = cl_url.rstrip("/").split("/")[-1]
                p_str += f"\n\n<details>\n<summary>{tag}</summary>\n\n{rel_notes}\n\n</details>"
        elif rel_notes:
            p_str += f"\n\n{rel_notes}"
        patches_lines.append(p_str)

    if patches_lines:
        sections.append("\n\n".join(patches_lines))

    output_str = "\n\n".join(sections) + "\n"
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(output_str)

    print(f"[+] Successfully generated {md_path} from {json_path}")

if __name__ == "__main__":
    main()
