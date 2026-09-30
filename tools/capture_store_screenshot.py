#!/usr/bin/env python3
"""Capture the current Android framebuffer as an opaque, store-sized PNG.

Set the emulator display to 1080x1920 first (adb shell wm size 1080x1920).
This captures the UI at its actual resolution; it does not crop or resize it.
Requires Pillow. Use synthetic content only for store listings.
"""
import argparse
from pathlib import Path
import struct
import subprocess
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--adb', default='adb')
parser.add_argument('--serial', required=True)
parser.add_argument('output', type=Path)
args = parser.parse_args()
raw = subprocess.check_output([args.adb, '-s', args.serial, 'exec-out', 'screencap'])
width, height, pixel_format = struct.unpack_from('<III', raw)
if not (320 <= min(width, height) and max(width, height) <= 3840 and max(width, height) <= 2 * min(width, height)):
    raise SystemExit(f'Unsupported store screenshot dimensions: {width}x{height}')
header_size = len(raw) - width * height * 4
if pixel_format not in (1, 2) or header_size not in (12, 16):
    raise SystemExit('Expected an Android RGBA/RGBX 8888 framebuffer')
frame = Image.frombytes('RGBA', (width, height), raw[header_size:])
args.output.parent.mkdir(parents=True, exist_ok=True)
frame.convert('RGB').save(args.output)
print(f'Captured {width}x{height} opaque screenshot: {args.output}')
