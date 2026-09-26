import sys
from pathlib import Path
import tempfile
import unittest
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from verify_apk import verify, ASSET, SUPPORTED

class ApkTests(unittest.TestCase):
    def test_missing_native_library_is_rejected(self):
        self.check(missing=True,corrupt=False)
    def test_changed_asset_is_rejected(self):
        self.check(missing=False,corrupt=True)
    def test_complete_package_passes(self):
        self.check(missing=False,corrupt=False)
    def check(self,missing,corrupt):
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder)/'test.apk'; network = Path(folder)/'network.json'
            network.write_bytes(b'tested-network')
            with zipfile.ZipFile(apk,'w') as archive:
                for abi,machine in SUPPORTED.items():
                    header = bytearray(20); header[:4] = b'\x7fELF'; header[4] = 2; header[5] = 1
                    header[18:20] = machine.to_bytes(2,'little')
                    for lib in ['libflutter.so','libwanderlust_geo.so']:
                        if missing and abi == 'arm64-v8a' and lib == 'libwanderlust_geo.so': continue
                        archive.writestr(f'lib/{abi}/{lib}',header)
                archive.writestr(ASSET,b'changed-network' if corrupt else b'tested-network')
            if missing or corrupt:
                with self.assertRaises(ValueError): verify(apk,network)
            else: self.assertEqual(len(verify(apk,network)),64)

if __name__ == '__main__': unittest.main()
