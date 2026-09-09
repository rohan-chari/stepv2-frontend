"""Pack the owner-supplied baraturtle.zip (Pillow required).

Usage: python3 scripts/pack_turtle_frames.py /path/to/baraturtle.zip output.png
Only border-connected white is removed; interior art is preserved. All frames
use one scale, horizontal centering, and the existing turtle ground line y=69.
"""

import sys
from collections import deque
from zipfile import ZipFile

from PIL import Image


def pack(source, destination):
    frames = []
    with ZipFile(source) as archive:
        for index in range(8):
            image = Image.open(archive.open(f"image{index}.png")).convert("RGBA")
            if image.size != (900, 900):
                raise ValueError("Expected eight 900x900 source frames")
            pixels = image.load()
            queue = deque(
                [(x, y) for x in range(900) for y in (0, 899)]
                + [(x, y) for y in range(900) for x in (0, 899)]
            )
            while queue:
                x, y = queue.popleft()
                if not (0 <= x < 900 and 0 <= y < 900):
                    continue
                if pixels[x, y] != (255, 255, 255, 255):
                    continue
                pixels[x, y] = (0, 0, 0, 0)
                queue.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
            bounds = image.getbbox()
            if bounds is None:
                raise ValueError("Empty frame")
            frames.append(image.crop(bounds))

    scale = 81 / max(frame.width for frame in frames)
    sheet = Image.new("RGBA", (704, 88))
    for index, frame in enumerate(frames):
        frame = frame.resize(
            (round(frame.width * scale), round(frame.height * scale)),
            Image.Resampling.NEAREST,
        )
        if frame.height > 69:
            raise ValueError("Frame exceeds the existing ground line")
        sheet.paste(frame, (index * 88 + (88 - frame.width) // 2, 69 - frame.height))
    sheet.save(destination)


if __name__ == "__main__":
    pack(*sys.argv[1:])
