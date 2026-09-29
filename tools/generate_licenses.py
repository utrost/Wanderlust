#!/usr/bin/env python3
"""Bundle the project licence and licences of Cargo's enabled dependencies.

Run after cargo fetch/build with the same CARGO_HOME used for the build.
Flutter bundles its own dependency notices through LicenseRegistry.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def generate():
    tree = subprocess.check_output(
        ["cargo", "tree", "--locked", "--offline", "--prefix", "none",
         "--format", "{p}"], cwd=ROOT, text=True)
    registry = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo")) / "registry/src"
    notices = []
    for line in sorted(set(tree.splitlines())):
        parts = line.split()
        if len(parts) < 2 or "(/" in line:
            continue
        name, version = parts[0], parts[1].removeprefix("v")
        if any(n["name"] == name for n in notices):
            continue
        directories = list(registry.glob(f"*/{name}-{version}"))
        if len(directories) != 1:
            raise RuntimeError(f"Expected one source directory for {name} {version}")
        files = sorted(p for p in directories[0].iterdir()
                       if p.is_file() and p.name.upper().startswith(("LICENSE", "COPYING", "NOTICE")))
        if not files:
            raise RuntimeError(f"No licence text found for {name} {version}")
        notices.append({"name": name, "version": version,
                        "text": "\n\n".join(p.name + "\n" + p.read_text() for p in files)})
    destination = ROOT / "app/assets/legal"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "AGPL-3.0.txt").write_bytes((ROOT / "LICENSE").read_bytes())
    (destination / "rust-licenses.json").write_text(json.dumps(notices, indent=2) + "\n")


if __name__ == "__main__":
    generate()
