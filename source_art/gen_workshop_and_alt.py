"""
1. Adds an "AEGIS-M" wordmark to the (already-shipped) Style A workshop
   preview.
2. Generates the full Style C (Bold Emblem) final asset set as a labeled
   "Alternative" -- same pipeline as gen_finals.py, but for the emblem
   glyphs, not wired into any config, saved under final_alt/ for review/
   future swap-in. Its workshop preview also gets the AEGIS-M wordmark
   plus a small "ALTERNATIVE" corner tag so it's unambiguous in the gallery.
"""
import os
import sys
import math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icons import (
    canvas, save as _save_local, OUT, hud_frame, HUD_BG, HUD_LINE, HUD_DIM, HUD_AMBER,
    emblem_badge, EMBLEM_ACCENTS,
)
from PIL import Image, ImageDraw, ImageFont

FINAL_DIR = os.path.join(OUT, "final")
ALT_DIR = os.path.join(OUT, "final_alt")
os.makedirs(ALT_DIR, exist_ok=True)

CONSOLAS_BOLD = "C:/Windows/Fonts/consolab.ttf"
ARIAL_BOLD = "C:/Windows/Fonts/arialbd.ttf"
TAHOMA_BOLD = "C:/Windows/Fonts/tahomabd.ttf"

def save(img, path):
    img.save(path)
    print("wrote", path)

def draw_tracked_text(d, xy, text, font, fill, tracking=0, anchor_center_x=None):
    """Draws text with manual letter-spacing (tracking, in px). If
    anchor_center_x is given, horizontally centers the tracked string on
    that x coordinate; xy's x is then ignored (only y is used)."""
    widths = [d.textbbox((0, 0), ch, font=font)[2] for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = (anchor_center_x - total / 2) if anchor_center_x is not None else xy[0]
    y = xy[1]
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=font, fill=fill)
        x += w + tracking

# ---------------------------------------------------------------------------
# 1. Style A (HUD) workshop preview -- add the AEGIS-M wordmark
# ---------------------------------------------------------------------------
def render_hud_master(s, line_color=HUD_LINE, dim_color=HUD_DIM, amber=HUD_AMBER, bg=HUD_BG):
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

def build_workshop_hud():
    workshop_master = render_hud_master(900)
    workshop = canvas(1024, HUD_BG)
    wd = ImageDraw.Draw(workshop)
    for x in range(0, 1024, 32):
        wd.line([(x, 0), (x, 1024)], fill=(20, 30, 38, 255), width=1)
    for y in range(0, 1024, 32):
        wd.line([(0, y), (1024, y)], fill=(20, 30, 38, 255), width=1)
    hud_frame(wd, 1024, 1024 * 0.05, color=HUD_LINE, w=4)

    # Emblem shrunk & shifted up to make room for the wordmark beneath it.
    ms = 620
    emblem_r = workshop_master.resize((ms, ms), Image.LANCZOS)
    workshop.alpha_composite(emblem_r, (int(512 - ms / 2), 96))

    title_font = ImageFont.truetype(CONSOLAS_BOLD, 92)
    sub_font = ImageFont.truetype(CONSOLAS_BOLD, 26)
    draw_tracked_text(wd, (0, 760), "AEGIS-M", title_font, HUD_LINE, tracking=14, anchor_center_x=512)
    draw_tracked_text(wd, (0, 862), "INTEGRATED AIR DEFENSE FRAMEWORK", sub_font, HUD_DIM, tracking=6, anchor_center_x=512)

    save(workshop.convert("RGB"), os.path.join(FINAL_DIR, "workshop_preview.png"))

build_workshop_hud()

# ---------------------------------------------------------------------------
# 2. Style C (Bold Emblem) -- full alternative asset set
# ---------------------------------------------------------------------------
def render_emblem_master(s):
    img, d, cx, cy, inner = emblem_badge(s, EMBLEM_ACCENTS["master"])
    for r in [0.24, 0.16]:
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 200, 340, fill=EMBLEM_ACCENTS["master"], width=max(4, s // 130))
    sweep = math.radians(-20)
    d.line([(cx, cy), (cx + inner * 0.85 * math.cos(sweep), cy + inner * 0.85 * math.sin(sweep))], fill=(255, 210, 90, 255), width=max(4, s // 150))
    d.ellipse([cx - s * 0.018, cy - s * 0.018, cx + s * 0.018, cy + s * 0.018], fill=(255, 255, 255, 255))
    return img

def downscale(img, size):
    return img.resize((size, size), Image.LANCZOS)

master_hi = render_emblem_master(1024)
logo = downscale(master_hi, 128).convert("RGB")
save(logo, os.path.join(ALT_DIR, "logo.png"))
logo_small = downscale(master_hi, 64).convert("RGB")
save(logo_small, os.path.join(ALT_DIR, "logo_small.png"))

# Hover variant: brighter rim accent.
def render_emblem_master_hover(s):
    img, d, cx, cy, inner = emblem_badge(s, (240, 90, 80, 255))
    for r in [0.24, 0.16]:
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 200, 340, fill=(240, 90, 80, 255), width=max(4, s // 130))
    sweep = math.radians(-20)
    d.line([(cx, cy), (cx + inner * 0.85 * math.cos(sweep), cy + inner * 0.85 * math.sin(sweep))], fill=(255, 225, 130, 255), width=max(4, s // 150))
    d.ellipse([cx - s * 0.018, cy - s * 0.018, cx + s * 0.018, cy + s * 0.018], fill=(255, 255, 255, 255))
    return img

logo_over = downscale(render_emblem_master_hover(1024), 128).convert("RGB")
save(logo_over, os.path.join(ALT_DIR, "logo_over.png"))

# --- Mod-list "picture" (wide banner), emblem style ---
def picture_emblem_final(w=1024, h=512):
    img = Image.new("RGBA", (w, h), (14, 15, 17, 255))
    d = ImageDraw.Draw(img)

    ms = int(h * 0.68)
    badge_top = int(h * 0.30 - ms / 2) + 20
    badge_cx, badge_cy = w * 0.5, badge_top + ms / 2

    # Decorative backdrop rings share the badge's own center, not the
    # canvas center, so they read as radiating from the emblem instead of
    # sitting visibly off-axis from it.
    for i in range(6):
        r = (i + 1) * w * 0.09
        d.ellipse([badge_cx - r, badge_cy - r, badge_cx + r, badge_cy + r], outline=(28, 29, 32, 255), width=1)

    master = render_emblem_master(1024)
    master_r = master.resize((ms, ms), Image.LANCZOS)
    img.alpha_composite(master_r, (int(w * 0.5 - ms / 2), badge_top))

    title_font = ImageFont.truetype(ARIAL_BOLD, 64)
    draw_tracked_text(d, (0, h * 0.68), "AEGIS-M", title_font, (235, 236, 238, 255), tracking=4, anchor_center_x=w / 2)

    save(img.convert("RGB"), os.path.join(ALT_DIR, "picture.png"))
    return img

picture_emblem_final()

# --- Steam Workshop preview (square), emblem style ---
def workshop_emblem_final():
    workshop = Image.new("RGBA", (1024, 1024), (14, 15, 17, 255))
    d = ImageDraw.Draw(workshop)

    ms = 620
    badge_top = 96
    badge_cx, badge_cy = 512, badge_top + ms / 2

    # Decorative backdrop rings share the badge's own center, not the
    # canvas center, so they read as radiating from the emblem instead of
    # sitting visibly off-axis from it.
    for i in range(9):
        r = (i + 1) * 1024 * 0.06
        d.ellipse([badge_cx - r, badge_cy - r, badge_cx + r, badge_cy + r], outline=(28, 29, 32, 255), width=1)

    master = render_emblem_master(1024)
    master_r = master.resize((ms, ms), Image.LANCZOS)
    workshop.alpha_composite(master_r, (int(512 - ms / 2), badge_top))

    title_font = ImageFont.truetype(ARIAL_BOLD, 92)
    sub_font = ImageFont.truetype(TAHOMA_BOLD, 24)
    draw_tracked_text(d, (0, 760), "AEGIS-M", title_font, (235, 236, 238, 255), tracking=6, anchor_center_x=512)
    draw_tracked_text(d, (0, 862), "INTEGRATED AIR DEFENSE FRAMEWORK", sub_font, (150, 152, 156, 255), tracking=4, anchor_center_x=512)

    save(workshop.convert("RGB"), os.path.join(ALT_DIR, "workshop_preview.png"))

workshop_emblem_final()

# --- Module icons (Style C glyphs, downscaled from the 512px gallery set) ---
module_srcs = {
    "icon_system": "emblem_system.png",
    "icon_engagement": "emblem_engagement.png",
    "icon_crew": "emblem_crew.png",
    "icon_network": "emblem_network.png",
}
for out_name, src_name in module_srcs.items():
    src = Image.open(os.path.join(OUT, src_name)).convert("RGB")
    icon64 = src.resize((64, 64), Image.LANCZOS)
    save(icon64, os.path.join(ALT_DIR, out_name + ".png"))

print("done")
