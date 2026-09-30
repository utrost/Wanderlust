#!/usr/bin/env python3
"""Keep five downloadable previews per channel; dry-run unless --apply is set."""

import argparse
import json
import subprocess


def releases_to_delete(releases, keep=5):
    if keep < 1:
        raise ValueError("At least one release must be retained")
    obsolete = []
    for prefix, draft, extensions in (
        ("test-apk-", False, (".apk",)),
        ("store-candidate-", True, (".apk", ".aab")),
    ):
        candidates = [
            release for release in releases
            if release["tag_name"].startswith(prefix)
            and release["prerelease"]
            and release["draft"] == draft
            and all(any(
                asset["name"].endswith(extension)
                and asset.get("state") == "uploaded"
                and asset.get("size", 0) > 0
                for asset in release.get("assets", [])
            ) for extension in extensions)
        ]
        candidates.sort(
            key=lambda release: (
                release.get("published_at") or release["created_at"],
                release["id"],
            ), reverse=True,
        )
        obsolete.extend(candidates[keep:])
    return obsolete


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub owner/repository")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    pages = json.loads(subprocess.check_output([
        "gh", "api", "--paginate", "--slurp",
        f"repos/{args.repo}/releases?per_page=100",
    ], text=True))
    obsolete = releases_to_delete([release for page in pages for release in page])
    for release in obsolete:
        print(f"{'Deleting' if args.apply else 'Would delete'} {release['tag_name']}", flush=True)
        if args.apply:
            # Delete the release/assets only. Keep tags and source history.
            subprocess.run([
                "gh", "api", "--method", "DELETE",
                f"repos/{args.repo}/releases/{release['id']}",
            ], check=True)
    print(f"{'Deleted' if args.apply else 'Selected'} {len(obsolete)} old previews; keep five per channel.")


if __name__ == "__main__":
    main()
