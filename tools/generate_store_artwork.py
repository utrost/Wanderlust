#!/usr/bin/env python3
"""Render original Wanderlust store artwork. Requires Pillow; no remote assets."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / 'fastlane/metadata/android/en-US/images'
OUT.mkdir(parents=True, exist_ok=True)
BG, INK, WARM = '#F4EDE3', '#75421F', '#C19B76'

def mark(draw, left, top, scale):
    points = [(left + x * scale, top + y * scale) for x, y in [(26, 32), (38, 76), (54, 48), (70, 76), (82, 32)]]
    width = round(8 * scale)
    draw.line(points, fill=INK, width=width, joint='curve')
    for x, y in points:
        draw.ellipse((x-width/2, y-width/2, x+width/2, y+width/2), fill=INK)
    draw.ellipse((left+48*scale, top+23*scale, left+60*scale, top+35*scale), fill=WARM)

icon = Image.new('RGBA', (1024, 1024), BG)
mark(ImageDraw.Draw(icon), 0, 0, 1024 / 108)
icon.resize((512, 512), Image.Resampling.LANCZOS).save(OUT / 'icon.png')
feature = Image.new('RGB', (2048, 1000), BG)
draw = ImageDraw.Draw(feature)
mark(draw, 90, 170, 6)
font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
draw.text((760, 335), 'Wanderlust', fill=INK, font=ImageFont.truetype(font_path, 135))
draw.text((767, 520), 'Explore at your own pace.', fill=INK, font=ImageFont.truetype(font_path, 58))
feature.resize((1024, 500), Image.Resampling.LANCZOS).save(OUT / 'featureGraphic.png')
print(OUT)
