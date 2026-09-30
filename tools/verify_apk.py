#!/usr/bin/env python3
"""Verify a test APK's native architecture coverage and bundled street data."""
import argparse
import hashlib
import struct
from pathlib import Path
import zipfile

SUPPORTED = {'arm64-v8a':183, 'x86_64':62}
ASSET = 'assets/flutter_assets/assets/geo/bremen-center.streets.geojson'


REQUIRED_GEO_SYMBOLS = {
    'wanderlust_matcher_from_geojson', 'wanderlust_match_gpx_options',
    'wanderlust_matcher_free', 'wanderlust_string_free',
}


def exported_symbols(data):
    """Read defined, externally visible symbols from a little-endian ELF64 dynsym."""
    try:
        offset = struct.unpack_from('<Q', data, 40)[0]
        size, count = struct.unpack_from('<HH', data, 58)
        if size < 64 or offset + size * count > len(data):
            raise ValueError('invalid ELF section table')
        sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * size)
                    for i in range(count)]
        symbols = set()
        for section in sections:
            if section[1] != 11:  # SHT_DYNSYM
                continue
            start, length, link, entry = section[4], section[5], section[6], section[9]
            if entry < 24 or length % entry or start + length > len(data):
                raise ValueError('invalid ELF dynamic symbols')
            strings = sections[link]
            if strings[4] + strings[5] > len(data):
                raise ValueError('invalid ELF string table')
            names = data[strings[4]:strings[4] + strings[5]]
            for position in range(start, start + length, entry):
                name, info, visibility, defined, _, _ = struct.unpack_from('<IBBHQQ', data, position)
                if not defined or info >> 4 not in (1, 2) or visibility & 3 not in (0, 3):
                    continue
                end = names.find(b'\0', name)
                if end < 0:
                    raise ValueError('invalid ELF symbol name')
                symbols.add(names[name:end].decode('ascii'))
        return symbols
    except (struct.error, IndexError, UnicodeError) as error:
        raise ValueError('malformed ELF symbol tables') from error


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
                if library == 'libwanderlust_geo.so':
                    missing = REQUIRED_GEO_SYMBOLS - exported_symbols(data)
                    if missing:
                        raise ValueError(f'missing required geo-core ABI symbols in {name}: {sorted(missing)}')
        if archive.read(ASSET) != Path(network).read_bytes():
            raise ValueError('bundled Bremen network does not match the tested asset')
    return hashlib.sha256(Path(apk).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path)
    parser.add_argument('--network',type=Path,default=Path('app/assets/geo/bremen-center.streets.geojson'))
    args = parser.parse_args()
    digest = verify(args.apk,args.network)
    print(f'Verified arm64-v8a + x86_64 Flutter/Rust libraries, required matcher ABI, and exact Bremen asset.\nSHA-256: {digest}')

if __name__ == '__main__': main()
