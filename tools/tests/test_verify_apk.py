import sys
import struct
from pathlib import Path
import tempfile
import unittest
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from verify_apk import verify, ASSET, SUPPORTED, REQUIRED_GEO_SYMBOLS

def native_elf(machine, stale=False, undefined=False):
    names = bytearray(b'\0')
    symbols = bytearray(24)
    for name in sorted(REQUIRED_GEO_SYMBOLS):
        if stale and name == 'wanderlust_match_gpx_options':
            continue
        offset = len(names)
        names.extend(name.encode() + b'\0')
        symbols.extend(struct.pack('<IBBHQQ', offset, 0x12, 0, 0 if undefined else 1, 1, 1))
    header = bytearray(64)
    header[:6] = b'\x7fELF\x02\x01'
    header[18:20] = machine.to_bytes(2, 'little')
    struct.pack_into('<Q', header, 40, 64)
    struct.pack_into('<HH', header, 58, 64, 3)
    sections = bytes(64)
    sections += struct.pack('<IIQQQQIIQQ', 0, 3, 0, 0, 256, len(names), 0, 0, 1, 0)
    sections += struct.pack('<IIQQQQIIQQ', 0, 11, 0, 0, 256 + len(names), len(symbols), 1, 0, 8, 24)
    return header + sections + names + symbols

class ApkTests(unittest.TestCase):
    def test_missing_native_library_is_rejected(self):
        self.check(missing=True,corrupt=False)
    def test_changed_asset_is_rejected(self):
        self.check(missing=False,corrupt=True)
    def test_complete_package_passes(self):
        self.check(missing=False,corrupt=False)
    def test_stale_matcher_abi_is_rejected(self):
        self.check(missing=False, corrupt=False, stale=True)
    def test_undefined_symbols_do_not_satisfy_matcher_abi(self):
        self.check(missing=False, corrupt=False, undefined=True)
    def check(self,missing,corrupt,stale=False,undefined=False):
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder)/'test.apk'; network = Path(folder)/'network.json'
            network.write_bytes(b'tested-network')
            with zipfile.ZipFile(apk,'w') as archive:
                for abi,machine in SUPPORTED.items():
                    header = bytearray(20); header[:4] = b'\x7fELF'; header[4] = 2; header[5] = 1
                    header[18:20] = machine.to_bytes(2,'little')
                    for lib in ['libflutter.so','libwanderlust_geo.so']:
                        if missing and abi == 'arm64-v8a' and lib == 'libwanderlust_geo.so': continue
                        archive.writestr(f'lib/{abi}/{lib}', native_elf(machine, stale=stale, undefined=undefined) if lib == 'libwanderlust_geo.so' else header)
                archive.writestr(ASSET,b'changed-network' if corrupt else b'tested-network')
            if missing or corrupt or stale or undefined:
                with self.assertRaises(ValueError): verify(apk,network)
            else: self.assertEqual(len(verify(apk,network)),64)

if __name__ == '__main__': unittest.main()
