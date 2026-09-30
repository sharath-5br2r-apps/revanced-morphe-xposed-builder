#!/usr/bin/env python3
"""Patcher tool classification — CI-side mirror of .github/scripts/patchers.sh.

Single place where a cli-source repo string maps to a tool kind, so CI and the
engine's registry can't drift.
The tables must stay in sync with patchers.sh (same case rules); the engine
reads that file, CI reads this one. Divergence here = the bug class P1 removes.

Kinds: revanced | morphe | npatch | lspatch | instafel | generic | apksigner | none

CLI:
    patchers.py kind <cli-source>            # print kind
    patchers.py bundle-globs <kind>          # print shell globs for patch bundles
"""
import fnmatch
import sys

# Mirrors patchers.sh resolve_patcher(); keep both in sync.
_SUBSTR_KINDS = [
    # (lowercase substring patterns -> kind); first match wins, same order as shell case
    (("apksigner",), "apksigner"),
    (("none",), "none"),
    (("npatch",), "npatch"),
    (("lspatch",), "lspatch"),
    (("instafel",), "instafel"),
    (("morphe-desktop",), "morphe"),
    (("revanced-cli",), "revanced"),
]

BUNDLE_GLOBS = {
    "npatch": ["*.apk"],
    "lspatch": ["*.apk"],
    "instafel": ["*.mpp", "*.rvp", "*.jar"],   # instafel core ships as *.jar
    "morphe": ["*.mpp", "*.rvp", "*.jar"],
    "revanced": ["*.mpp", "*.rvp", "*.jar"],
    "generic": ["*.mpp", "*.rvp", "*.jar"],
    "apksigner": [],
    "none": [],
}


def classify(cli_source: str) -> str:
    c = (cli_source or "").lower()
    for patterns, kind in _SUBSTR_KINDS:
        if any(p in c for p in patterns):
            return kind
    return "generic"


def ci_bundle_diffable(cli_sources) -> bool:
    """Preserves ci_check_app_patches.py's existing rule verbatim: a repo with
    no known cli is treated diffable; otherwise any cli-source containing
    'revanced' or 'morphe'. Note this is DELIBERATELY broader than classify():
    CI 'diffable' gates bundle-hash checking, the engine flag gates runtime
    behavior; do not "unify" them without deciding the semantics."""
    if not cli_sources:
        return True
    return any("revanced" in c or "morphe" in c for c in cli_sources)


def _matches_any(name: str, globs) -> bool:
    return any(fnmatch.fnmatch(name.lower(), g.lower()) for g in globs)


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "kind" and len(argv) == 3:
        print(classify(argv[2]))
        return 0
    if cmd == "bundle-globs" and len(argv) == 3:
        print(" ".join(BUNDLE_GLOBS.get(argv[2], BUNDLE_GLOBS["generic"])))
        return 0
    print(f"unknown invocation: {' '.join(argv[1:])}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
