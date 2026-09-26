#!/usr/bin/env python3
"""Verify a test APK's native architecture coverage and bundled street data."""
import argparse
import hashlib
from pathlib import Path
import zipfile

SUPPORTED = {'arm64-v8a':183, 'x86_64':62}
ASSET = 'assets/flutter_assets/assets/geo/bremen-center.streets.geojson'


def verify(apk, network):
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        architectures = {n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('.so')}
        if architectures != set(SUPPORTED):
            raise ValueError(f'APK architectures {architectures} do not match supported Rust ABIs {set(SUPPORTED)}')
        for abi, machine in SUPPORTED.items():
            for library in ['libwanderlust_geo.so','libflutter.so']:
                name = f'lib/{abi}/{library}'
                if name not in names: raise ValueError(f'missing {name}')
                data = archive.read(name)
                if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1 or int.from_bytes(data[18:20],'little') != machine:
                    raise ValueError(f'incorrect ELF architecture for {name}')
        if archive.read(ASSET) != Path(network).read_bytes():
            raise ValueError('bundled Bremen network does not match the tested asset')
    return hashlib.sha256(Path(apk).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path)
    parser.add_argument('--network',type=Path,default=Path('app/assets/geo/bremen-center.streets.geojson'))
    args = parser.parse_args()
    digest = verify(args.apk,args.network)
    print(f'Verified arm64-v8a + x86_64 Flutter/Rust libraries and exact Bremen asset.\nSHA-256: {digest}')

if __name__ == '__main__': main()
