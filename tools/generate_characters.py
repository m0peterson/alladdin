#!/usr/bin/env python3
"""Own T18 NPC atlases from the project's T02 silhouette; stdlib only."""
from pathlib import Path
import struct
import zlib
import sys
sys.dont_write_bytecode = True
from generate_player import DOWN, RIGHT, UP, PALETTE, frame, chunk

ROOT = Path(__file__).resolve().parents[1]
COLORS = {
    'merchant': {'P': (51, 105, 103, 255), 'p': (92, 158, 140, 255), 'R': (212, 151, 63, 255), 'r': (249, 224, 181, 255)},
    'fence': {'P': (59, 39, 76, 255), 'p': (100, 68, 113, 255), 'R': (59, 39, 76, 255), 'r': (142, 82, 156, 255), 'W': (100, 68, 113, 255), 'w': (59, 39, 76, 255)},
    'bandit': {'P': (132, 62, 56, 255), 'p': (180, 82, 66, 255), 'R': (180, 52, 66, 255), 'r': (230, 86, 76, 255), 'W': (106, 76, 66, 255), 'w': (76, 43, 51, 255)},
    'guard': {'P': (49, 68, 91, 255), 'p': (74, 110, 163, 255), 'R': (150, 173, 177, 255), 'r': (220, 224, 208, 255), 'W': (74, 110, 163, 255), 'w': (49, 68, 91, 255)},
}

def main():
    for role, changes in COLORS.items():
        palette = PALETTE | changes
        width, height = 48, 96
        pixels = bytearray(width * height * 4)
        for direction in range(4):
            base = [DOWN, RIGHT, RIGHT, UP][direction]
            for step in range(3):
                rows = frame(base, step)
                if role == 'fence':
                    rows[:3] = ['......pppp......', '.....PPPPPP.....', '....HPPPPPPH....']
                elif role == 'guard':
                    rows[:3] = ['......rrrr......', '.....rRRRRr.....', '....rRRRRRRr....']
                elif role == 'merchant':
                    rows[:3] = ['......rrrr......', '....rrrrrrrr....', '....rRRRRRRr....']
                if role == 'bandit' and direction != 3:
                    rows[7] = '.....RRRRRR.....'
                if direction == 1:
                    rows = [row[::-1] for row in rows]
                assert len(rows) == 24 and all(len(row) == 16 for row in rows)
                assert any(c != '.' for c in rows[23])
                for y, row in enumerate(rows):
                    for x, color in enumerate(row):
                        offset = ((direction * 24 + y) * width + step * 16 + x) * 4
                        pixels[offset:offset + 4] = bytes(palette[color])
        scanlines = b''.join(b'\0' + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
        png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
               + chunk(b'IDAT', zlib.compress(scanlines)) + chunk(b'IEND', b''))
        (ROOT / 'assets/characters' / f'{role}.png').write_bytes(png)
        print(f'{role}.png: 12 frames; 16x24; feet y=23')

if __name__ == '__main__':
    main()
