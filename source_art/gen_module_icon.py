"""
Bold module icon for Eden/Zeus (addons/main/data/aegism_logo_ca.paa).

The master emblem (gen_finals.render_master) uses hairline strokes (1/180 to
1/220 of its width); shrunk to a ~1-inch Eden/Zeus icon those fall below a
pixel and the icon reads as faint lines. This draws the same motif --
hexagon, radar arcs, amber sweep and centre dot -- with strokes several times
heavier, drops the hairline details (inner hexagon, border, tick marks,
corner frame), and uses a transparent background so Eden can show it on its
dark UI.

Renders at 1024 and downsamples with LANCZOS to 128, then:
    hemtt utils paa convert source_art/logo_icon.png addons/main/data/aegism_logo_ca.paa
"""
import math
import os
from PIL import Image, ImageDraw

LINE = (0, 200, 255, 255)
AMBER = (255, 184, 33, 255)

def render(s):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = s / 2, s / 2

    hexagon = [(cx + s * 0.42 * math.cos(math.pi / 6 + i * math.pi / 3),
                cy + s * 0.42 * math.sin(math.pi / 6 + i * math.pi / 3)) for i in range(6)]
    d.line(hexagon + [hexagon[0]], fill=LINE, width=int(s * 0.075), joint="curve")

    for r in (0.27, 0.16):
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 195, 345, fill=LINE, width=int(s * 0.06))

    sweep = math.radians(-25)
    d.line([(cx, cy), (cx + s * 0.30 * math.cos(sweep), cy + s * 0.30 * math.sin(sweep))], fill=AMBER, width=int(s * 0.07))
    dot = s * 0.07
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=AMBER)
    return img

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "logo_icon.png")
render(1024).resize((128, 128), Image.LANCZOS).save(out)
print("wrote", out)
