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

    cli_list = []
    patches_list = []

    # Sort build.json entries deterministically by app name then entry key
    sorted_entries = sorted(data.items(), key=lambda x: (x[1].get("name", x[0]), x[0]))

    apps_lines = []
    for key, entry in sorted_entries:
        name = entry.get("name", key)
        arch = entry.get("arch", "")
        version = entry.get("version", "")
        cli_info = entry.get("cli", "")
        patches_info = entry.get("patches", "")
        changelog = entry.get("changelog", "")

        if cli_info and cli_info not in cli_list:
            cli_list.append(cli_info)
        if patches_info and patches_info not in patches_list:
            patches_list.append(patches_info)

        lines = [f"{name} ({arch}): {version}"]
        if changelog:
            lines.append(f"[Changelog]({changelog})")

        apps_lines.append("\n".join(lines))

    md_content = []

    # 1. Apps section
    if apps_lines:
        md_content.append("\n".join(apps_lines))

    # 2. CLI section (single unique instances)
    if cli_list:
        md_content.append("CLI:\n" + "\n".join(cli_list))

    # 3. Patches section (single unique instances)
    if patches_list:
        md_content.append("Patches:\n" + "\n".join(patches_list))

    output_str = "\n\n".join(md_content) + "\n"
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(output_str)

    print(f"[+] Successfully generated {md_path} from {json_path}")

if __name__ == "__main__":
    main()
