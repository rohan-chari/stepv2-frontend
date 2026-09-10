"""Verify the bounded, owner-approved native fringe correction (no image edits)."""
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class TurtleCleanupTest(unittest.TestCase):
    def test_fringe_fixed_without_changing_shape_or_animation(self):
        before = Image.open(ROOT / 'docs/artifacts/turtle-cleanup-2026-09-10/before.png').convert('RGBA')
        after = Image.open(ROOT / 'assets/images/turtle_walk_right.png').convert('RGBA')
        self.assertEqual(before.size, (704, 88))
        self.assertEqual(after.size, before.size)
        # The inspected original has 90 isolated pale residues, including the
        # repeated shell-top flecks (33/37, y33/34) visible in the report.
        residues = {(x, y) for y in range(88) for x in range(704)
                    if before.getpixel((x, y))[3] and min(before.getpixel((x, y))[:3]) >= 150}
        self.assertEqual(len(residues), 90)
        changed = set()
        for y in range(88):
            for x in range(704):
                old, new = before.getpixel((x, y)), after.getpixel((x, y))
                self.assertEqual(old[3], new[3], (x, y, 'silhouette changed'))
                if old != new:
                    changed.add((x, y))
                if (x, y) in residues:
                    self.assertLess(min(new[:3]), 150, (x, y, 'pale residue remains'))
                    neighbors = {before.getpixel((x + dx, y + dy))
                                 for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1))}
                    self.assertIn(new, neighbors, (x, y, 'introduced new color'))
        self.assertEqual(changed, residues)
        # Identical alpha and untouched non-residue pixels preserve the exact
        # tail-tip/root motion, gait, frame order, bounce and attachment geometry.


if __name__ == '__main__':
    unittest.main()
