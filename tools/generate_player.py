#!/usr/bin/env python3
"""Generate the original T02 placeholder atlas; no third-party libraries."""
from pathlib import Path
import struct
import zlib

PALETTE = {
    '.': (0, 0, 0, 0), 'H': (42, 28, 40, 255),
    'h': (76, 43, 51, 255), 'R': (180, 52, 66, 255),
    'r': (230, 86, 76, 255), 'S': (237, 167, 107, 255),
    's': (184, 111, 78, 255), 'P': (83, 47, 113, 255),
    'p': (142, 82, 156, 255), 'B': (212, 151, 63, 255),
    'W': (249, 224, 181, 255), 'w': (203, 177, 147, 255),
}
DOWN = [
    '......rrrr......', '.....HRRRRH.....', '....HHHHHHHH....',
    '...HHSSSSSSHH...', '...HSSSSSSSSH...', '...HSHSSSSHSH...',
    '....SSSSSSSS....', '.....sSSSSs.....', '......ssss......',
    '....PpSSSSpP....', '...SPpSSSSpPS...', '...SPpSSSSpPS...',
    '...SPpSSSSpPS...', '...sPpSSSSpPs...', '...ssPSSSSPss...',
    '.....BBBBBB.....', '....WWWWWWWW....', '....WWWWWWWW....',
    '....WWWWWWWW....', '....WWWwwWWW....', '.....WW..WW.....',
    '.....ss..ss.....', '....SSS..SSS....', '....sss..sss....',
]
UP = [
    '......rrrr......', '.....HRRRRH.....', '....HHHHHHHH....',
    '...HHHHHHHHHH...', '...HHhHHHHhHH...', '...HHHHHHHHHH...',
    '....HHHHHHHH....', '.....HHHHHH.....', '......ssss......',
    '....PppppppP....', '...SPppppppPS...', '...SPppppppPS...',
    '...SPppppppPS...', '...sPppppppPs...', '...ssPPPPPPss...',
    '.....BBBBBB.....', '....wwwwwwww....', '....WWWWWWWW....',
    '....WWWWWWWW....', '....WWWwwWWW....', '.....WW..WW.....',
    '.....ss..ss.....', '.....SS..SS.....', '.....ss..ss.....',
]
RIGHT = [
    '......rrrr......', '.....HRRRR......', '....HHHHHHH.....',
    '....HHHHSSS.....', '....HHHSSSSS....', '....HHHSSHSS....',
    '....HHSSSSSSS...', '.....HSSSSS.....', '......ssss......',
    '.....PppSS......', '.....PppSSS.....', '.....PpSSSS.....',
    '.....PpSSSS.....', '.....PpsSSS.....', '.....PPssS......',
    '.....BBBBBB.....', '.....WWWWWW.....', '.....WWWWWW.....',
    '.....WWWWWW.....', '.....WWwwWW.....', '......WW.WW.....',
    '......ss.ss.....', '......SSSSSS....', '......ssssss....',
]


def frame(base: list[str], step: int) -> list[str]:
    rows = base.copy()
    # The support foot stays on y=23; the other foot lifts one pixel.
    if step:
        if base is RIGHT:
            rows[20:24] = [
                '.....WWW.WW.....', '.....ss..ss.....',
                '.....SSS.SSS....' if step == 1 else '......SSSSSS....',
                '.....sss........' if step == 1 else '.........sss....',
            ]
        else:
            rows[20:24] = [
                '.....WW..WW.....', '.....ss..ss.....', '....SSS..SSS....',
                '....sss.........' if step == 1 else '.........sss....',
            ]
    assert len(rows) == 24 and all(len(row) == 16 for row in rows)
    return rows


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack('>I', len(payload)) + kind + payload
            + struct.pack('>I', zlib.crc32(kind + payload)))


def main() -> None:
    width, height = 48, 96
    pixels = bytearray(width * height * 4)
    for direction in range(4):
        base = [DOWN, RIGHT, RIGHT, UP][direction]
        for step in range(3):
            rows = frame(base, step)
            if direction == 1:
                rows = [row[::-1] for row in rows]
            for y, row in enumerate(rows):
                for x, color in enumerate(row):
                    offset = ((direction * 24 + y) * width + step * 16 + x) * 4
                    pixels[offset:offset + 4] = bytes(PALETTE[color])
    scanlines = b''.join(
        b'\0' + pixels[y * width * 4:(y + 1) * width * 4]
        for y in range(height)
    )
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(scanlines)) + chunk(b'IEND', b''))
    target = Path(__file__).resolve().parents[1] / 'assets/characters/aladdin.png'
    target.write_bytes(png)
    print(f'Generated {target.name}: {width}x{height}, 12 frames')


if __name__ == '__main__':
    main()
