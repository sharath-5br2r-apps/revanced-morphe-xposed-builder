import os
import sys

def merge_tomls(source_files, output_file):
    merged_lines = []
    for sf in source_files:
        if os.path.exists(sf):
            with open(sf, "r", encoding="utf-8") as f:
                content = f.read()
                merged_lines.append(f"# --- Merged from {sf} ---\n" + content.strip())
        else:
            print(f"[-] Warning: {sf} does not exist", file=sys.stderr)
            
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("\n\n".join(merged_lines) + "\n")
    print(f"[+] Merged {len(source_files)} TOML files into {output_file}")

def main():
    base = "configs/patches"
    merged_dir = os.path.join(base, "merged")
    
    groups = {
        "youtube.toml": [
            os.path.join(base, "anddea.toml"),
            os.path.join(base, "morphe.toml")
        ],
        "hoodles-hooman.toml": [
            os.path.join(base, "hoodles.toml"),
            os.path.join(base, "hooman.toml")
        ],
        "nulls-sign-revenge.toml": [
            os.path.join(base, "nulls.toml"),
            os.path.join(base, "sign.toml"),
            os.path.join(base, "revenge.toml")
        ],
        "other-configs.toml": [
            os.path.join(base, "bholeykabhakt.toml"),
            os.path.join(base, "binarymend.toml"),
            os.path.join(base, "brave.toml"),
            os.path.join(base, "byehi98.toml"),
            os.path.join(base, "chess.toml"),
            os.path.join(base, "gboard.toml"),
            os.path.join(base, "github.toml"),
            os.path.join(base, "kondratjev.toml"),
            os.path.join(base, "paresh.toml"),
            os.path.join(base, "piko.toml"),
            os.path.join(base, "rushiranpise.toml"),
            os.path.join(base, "stylus.toml"),
            os.path.join(base, "tiktok.toml")
        ]
    }
    
    for out_name, sources in groups.items():
        out_path = os.path.join(merged_dir, out_name)
        merge_tomls(sources, out_path)

if __name__ == "__main__":
    main()
