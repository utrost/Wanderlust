from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_store_build import verify_elf, verify_apk_manifest


def elf(alignment=16384, address=0, offset=0):
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<IIQQQQQQ', data, 64, 1, 5, offset, address, 0, 0, 0, alignment)
    return data


class StoreBuildTests(unittest.TestCase):
    def test_16k_load_segments(self):
        verify_elf(elf())
        verify_elf(elf(65536))
        for data in [elf(4096), elf(address=4096), elf(24576), b'bad ELF', elf()[:80]]:
            with self.subTest(data=data[:6]), self.assertRaises(ValueError):
                verify_elf(data)

    def test_debug_package_rejected_before_alignment(self):
        with patch('verify_store_build.subprocess.check_output', return_value="application-debuggable\n"), \
             patch('verify_store_build.subprocess.run') as run:
            with self.assertRaises(ValueError):
                verify_apk_manifest(Path('app.apk'), Path('/tools'))
            run.assert_not_called()

    def test_offline_and_public_policy_are_identical(self):
        import html
        root = Path(__file__).parents[2]
        text = (root / 'app/assets/legal/privacy.txt').read_text()
        self.assertIn(html.escape(text), (root / 'docs/privacy.html').read_text())
