"""
Finalizes the chosen HUD style into the actual asset files AEGIS-M ships:
  - mod.cpp imagery (logo / logoOver / logoSmall / picture) as loose PNGs
    at the repo root (converted to .paa afterward, referenced by plain
    filename from mod.cpp per BI convention -- these are NOT packed in a PBO).
  - Per-module Eden icons, packed into addons/main/data/ and referenced
    cross-PBO by every module (all already depend on aegism_main).
  - A square Steam Workshop preview image (stays PNG -- Workshop uploads
    are not game assets, so they're never converted to .paa).

Re-renders at high resolution and downsamples with LANCZOS for clean
anti-aliased small icons, rather than shrinking the already-small preview
PNGs.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import (
    hud_base, HUD_LINE, HUD_DIM, HUD_AMBER, HUD_BG, hud_frame,
    canvas, save as _save_local, OUT,
)
from PIL import Image, ImageDraw
import math

FINAL_DIR = os.path.join(OUT, "final")
os.makedirs(FINAL_DIR, exist_ok=True)

def save_final(img, name):
    path = os.path.join(FINAL_DIR, name)
    img.save(path)
    print("wrote", path)
    return path

# ---------------------------------------------------------------------------
# Re-render master emblem + module glyphs at high res for clean downscaling
# ---------------------------------------------------------------------------
def render_master(s, line_color=HUD_LINE, dim_color=HUD_DIM, amber=HUD_AMBER, bg=HUD_BG):
    img = canvas(s, bg)
    d = ImageDraw.Draw(img)
    pad = s * 0.06
    d.rectangle([pad, pad, s - pad, s - pad], outline=dim_color, width=max(1, s // 220))
    hud_frame(d, s, pad * 0.5, color=line_color)
    cx, cy = s / 2, s / 2

    def ring(cx, cy, r, n, rot=0):
        pts = []
        for i in range(n):
            a = rot + (2 * math.pi * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        return pts

    d.polygon(ring(cx, cy, s * 0.36, 6, rot=math.pi / 6), outline=line_color, width=max(2, s // 180))
    d.polygon(ring(cx, cy, s * 0.30, 6, rot=math.pi / 6), outline=dim_color, width=max(1, s // 300))
    for r in [0.20, 0.13]:
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 195, 345, fill=line_color, width=max(2, s // 220))
    sweep = math.radians(-25)
    d.line([(cx, cy), (cx + s * 0.22 * math.cos(sweep), cy + s * 0.22 * math.sin(sweep))], fill=amber, width=max(3, s // 200))
    d.ellipse([cx - s * 0.015, cy - s * 0.015, cx + s * 0.015, cy + s * 0.015], fill=amber)
    for a in range(0, 360, 45):
        rad = math.radians(a)
        x1, y1 = cx + math.cos(rad) * s * 0.40, cy + math.sin(rad) * s * 0.40
        x2, y2 = cx + math.cos(rad) * s * 0.44, cy + math.sin(rad) * s * 0.44
        d.line([(x1, y1), (x2, y2)], fill=dim_color, width=2)
    return img

def downscale(img, size):
    return img.resize((size, size), Image.LANCZOS)

# --- mod.cpp imagery ---
HOVER_LINE = (140, 235, 255, 255)
HOVER_AMBER = (255, 205, 90, 255)

master_hi = render_master(1024)
logo = downscale(master_hi, 128).convert("RGB")
save_final(logo, "logo.png")
logo_small = downscale(master_hi, 64).convert("RGB")
save_final(logo_small, "logo_small.png")

master_hover_hi = render_master(1024, line_color=HOVER_LINE, amber=HOVER_AMBER)
logo_over = downscale(master_hover_hi, 128).convert("RGB")
save_final(logo_over, "logo_over.png")

# Wide mod-list "picture" -- reuse the already-approved banner composition.
picture_src = Image.open(os.path.join(OUT, "picture_hud.png")).convert("RGB")
save_final(picture_src, "picture.png")

# --- Steam Workshop preview: square, standalone (not shipped in the mod) ---
workshop_master = render_master(900)
workshop = canvas(1024, HUD_BG)
wd = ImageDraw.Draw(workshop)
for x in range(0, 1024, 32):
    wd.line([(x, 0), (x, 1024)], fill=(20, 30, 38, 255), width=1)
for y in range(0, 1024, 32):
    wd.line([(0, y), (1024, y)], fill=(20, 30, 38, 255), width=1)
hud_frame(wd, 1024, 1024 * 0.05, color=HUD_LINE, w=4)
workshop.alpha_composite(workshop_master, (62, 62))
save_final(workshop.convert("RGB"), "workshop_preview.png")

# --- Per-module Eden icons (downscaled from the already-generated 512px glyphs) ---
module_srcs = {
    "icon_system": "hud_system.png",
    "icon_engagement": "hud_engagement.png",
    "icon_crew": "hud_crew.png",
    "icon_network": "hud_network.png",
}
for out_name, src_name in module_srcs.items():
    src = Image.open(os.path.join(OUT, src_name)).convert("RGB")
    icon64 = downscale(src, 64)
    save_final(icon64, out_name + ".png")

print("done")
