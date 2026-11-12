"""Render MileLog's original road/M icon using only Python's standard library."""
from pathlib import Path
import json
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'MileLog/Resources/Assets.xcassets/AppIcon.appiconset'
POINTS = [(264, 736), (264, 306), (512, 570), (760, 306), (760, 736)]
SEGMENTS = []
offset = 0
for a, b in zip(POINTS, POINTS[1:]):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    SEGMENTS.append((a[0], a[1], dx, dy, length, offset))
    offset += length

def blend(base, top, amount):
    amount = min(1, max(0, amount))
    return tuple(round(a + (b - a) * amount) for a, b in zip(base, top))

def chunk(name, data):
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data) & 0xffffffff)

def render(size):
    scale = 1024 / size
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        py = (y + 0.5) * scale
        for x in range(size):
            px = (x + 0.5) * scale
            color = blend((13, 32, 45), (17, 73, 68), (px + py) / 2048)
            distance, along = 10000, 0
            for ax, ay, dx, dy, length, offset in SEGMENTS:
                t = min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / (length * length)))
                d = math.hypot(px - ax - t * dx, py - ay - t * dy)
                if d < distance:
                    distance, along = d, offset + t * length
            color = blend(color, (174, 240, 208), (53 - distance) / scale + 0.5)
            color = blend(color, (23, 102, 88), (32 - distance) / scale + 0.5)
            if int(along / 42) % 2 == 0:
                color = blend(color, (213, 251, 230), (4 - distance) / scale + 0.5)
            for cx, cy in [POINTS[0], POINTS[-1]]:
                d = math.hypot(px - cx, py - cy)
                color = blend(color, (174, 240, 208), (53 - d) / scale + 0.5)
                color = blend(color, (13, 40, 48), (35 - d) / scale + 0.5)
                color = blend(color, (240, 255, 247), (15 - d) / scale + 0.5)
            rows.extend(color)
    header = struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')

OUT.mkdir(parents=True, exist_ok=True)
images = []
for points in [20, 29, 40, 60]:
    for scale in [2, 3]:
        pixels = points * scale
        filename = f'Icon-{pixels}.png'
        (OUT / filename).write_bytes(render(pixels))
        images.append({'idiom': 'iphone', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': filename})
(OUT / 'Icon-1024.png').write_bytes(render(1024))
images.append({'idiom': 'ios-marketing', 'size': '1024x1024', 'scale': '1x', 'filename': 'Icon-1024.png'})
(OUT / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(OUT.parent / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
print('Created opaque iPhone and App Store icon assets.')
