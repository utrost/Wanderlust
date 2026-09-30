import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prune_preview_releases import releases_to_delete


def release(number, prefix="test-apk-", draft=False):
    return {
        "id": number, "tag_name": f"{prefix}{number}",
        "prerelease": True, "draft": draft,
        "created_at": f"2026-09-{number:02d}T00:00:00Z",
        "published_at": None,
        "assets": [{"name": f"app{ext}", "state": "uploaded", "size": 100}
                   for ext in (".apk", ".aab")],
    }


class ReleaseRetentionTest(unittest.TestCase):
    def test_keeps_five_per_channel_regardless_of_api_order(self):
        releases = [release(n) for n in range(1, 8)]
        releases += [release(n, "store-candidate-", True) for n in range(1, 7)]
        self.assertEqual(
            [r["tag_name"] for r in releases_to_delete(releases)],
            ["test-apk-2", "test-apk-1", "store-candidate-1"],
        )

    def test_stable_custom_incomplete_and_unexpected_states_are_protected(self):
        protected = [release(1), release(2, "v"), release(3, draft=True),
                     release(4, "store-candidate-"), release(5), release(6)]
        protected[0]["prerelease"] = False
        protected[4]["assets"] = []
        protected[5]["assets"][0]["state"] = "starter"
        self.assertEqual(releases_to_delete(protected + [release(n) for n in range(7, 12)]), [])

    def test_uses_publication_date_instead_of_commit_creation_date(self):
        releases = [release(n) for n in range(1, 7)]
        releases[0]["published_at"] = "2026-09-30T00:00:00Z"
        self.assertEqual([r["id"] for r in releases_to_delete(releases)], [2])


if __name__ == "__main__":
    unittest.main()
