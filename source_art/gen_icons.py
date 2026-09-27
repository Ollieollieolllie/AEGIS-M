"""
Procedural icon generator for AEGIS-M -- draws all imagery with Pillow shape
primitives only (no external art assets, no fonts), so everything here is
reproducible and license-clean. Three style variants x (master emblem + 4
module glyphs), plus a mod-list "picture" composition per style.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.dirname(os.path.abspath(__file__))

def canvas(size, bg=(0, 0, 0, 0)):
    return Image.new("RGBA", (size, size), bg)

def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", path)

def lerp(a, b, t):
    return a + (b - a) * t

def polygon_ring(cx, cy, r, n, rot=0):
    pts = []
    for i in range(n):
        a = rot + (2 * math.pi * i / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

# ---------------------------------------------------------------------------
# Style A: Military stencil / HUD
# ---------------------------------------------------------------------------
HUD_BG = (8, 13, 18, 255)
HUD_LINE = (58, 214, 255, 255)
HUD_DIM = (34, 110, 130, 255)
HUD_AMBER = (255, 176, 32, 255)

def hud_frame(d, s, pad, color=HUD_LINE, w=None):
    w = w or max(2, s // 96)
    b = pad
    L = s * 0.12
    for (x, y, dx, dy) in [(b, b, 1, 1), (s - b, b, -1, 1), (b, s - b, 1, -1), (s - b, s - b, -1, -1)]:
        d.line([(x, y), (x + dx * L, y)], fill=color, width=w)
        d.line([(x, y), (x, y + dy * L)], fill=color, width=w)

def hud_base(s):
    img = canvas(s, HUD_BG)
    d = ImageDraw.Draw(img)
    pad = s * 0.06
    d.rectangle([pad, pad, s - pad, s - pad], outline=HUD_DIM, width=max(1, s // 220))
    hud_frame(d, s, pad * 0.5)
    return img, d

def hud_system(s=512):
    img, d = hud_base(s)
    cx, cy = s / 2, s / 2
    for i, r in enumerate([0.32, 0.22, 0.12]):
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 200, 340, fill=HUD_LINE, width=max(2, s // 140))
    d.ellipse([cx - s * 0.02, cy - s * 0.02, cx + s * 0.02, cy + s * 0.02], fill=HUD_AMBER)
    sweep = math.radians(20)
    d.line([(cx, cy), (cx + s * 0.34 * math.cos(sweep), cy + s * 0.34 * math.sin(sweep))], fill=HUD_AMBER, width=max(2, s // 160))
    d.line([(cx - s * 0.4, cy), (cx + s * 0.4, cy)], fill=HUD_DIM, width=1)
    save(img, "hud_system.png")

def hud_engagement(s=512):
    img, d = hud_base(s)
    cx, cy = s / 2, s / 2
    r = s * 0.28
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=HUD_LINE, width=max(2, s // 140))
    d.ellipse([cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55], outline=HUD_DIM, width=max(1, s // 220))
    for a in range(0, 360, 30):
        rad = math.radians(a)
        x1, y1 = cx + math.cos(rad) * r * 1.0, cy + math.sin(rad) * r * 1.0
        x2, y2 = cx + math.cos(rad) * r * 1.12, cy + math.sin(rad) * r * 1.12
        d.line([(x1, y1), (x2, y2)], fill=HUD_DIM, width=1)
    d.line([(cx - r * 1.3, cy), (cx + r * 1.3, cy)], fill=HUD_AMBER, width=max(2, s // 160))
    d.line([(cx, cy - r * 1.3), (cx, cy + r * 1.3)], fill=HUD_AMBER, width=max(2, s // 160))
    save(img, "hud_engagement.png")

def hud_crew(s=512):
    img, d = hud_base(s)
    cx, cy = s / 2, s / 2
    for i, dy in enumerate([-0.10, 0.04, 0.18]):
        yy = cy + s * dy
        width_ = s * (0.28 - i * 0.03)
        d.line([(cx - width_, yy + s * 0.06), (cx, yy - s * 0.06), (cx + width_, yy + s * 0.06)],
               fill=HUD_LINE if i < 2 else HUD_AMBER, width=max(3, s // 110), joint="curve")
    save(img, "hud_crew.png")

def hud_network(s=512):
    img, d = hud_base(s)
    cx, cy = s / 2, s / 2
    nodes = [(cx, cy - s * 0.26), (cx - s * 0.26, cy + s * 0.14), (cx + s * 0.26, cy + s * 0.14), (cx, cy)]
    for i in range(3):
        d.line([nodes[3], nodes[i]], fill=HUD_DIM, width=max(2, s // 160))
    for i, (x, y) in enumerate(nodes):
        r = s * (0.045 if i < 3 else 0.03)
        color = HUD_AMBER if i == 3 else HUD_LINE
        d.ellipse([x - r, y - r, x + r, y + r], outline=color, width=max(2, s // 160))
    save(img, "hud_network.png")

def hud_master(s=1024):
    img, d = hud_base(s)
    cx, cy = s / 2, s / 2
    d.polygon(polygon_ring(cx, cy, s * 0.36, 6, rot=math.pi / 6), outline=HUD_LINE, width=max(2, s // 180))
    d.polygon(polygon_ring(cx, cy, s * 0.30, 6, rot=math.pi / 6), outline=HUD_DIM, width=max(1, s // 300))
    for i, r in enumerate([0.20, 0.13]):
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 195, 345, fill=HUD_LINE, width=max(2, s // 220))
    sweep = math.radians(-25)
    d.line([(cx, cy), (cx + s * 0.22 * math.cos(sweep), cy + s * 0.22 * math.sin(sweep))], fill=HUD_AMBER, width=max(3, s // 200))
    d.ellipse([cx - s * 0.015, cy - s * 0.015, cx + s * 0.015, cy + s * 0.015], fill=HUD_AMBER)
    for a in range(0, 360, 45):
        rad = math.radians(a)
        x1, y1 = cx + math.cos(rad) * s * 0.40, cy + math.sin(rad) * s * 0.40
        x2, y2 = cx + math.cos(rad) * s * 0.44, cy + math.sin(rad) * s * 0.44
        d.line([(x1, y1), (x2, y2)], fill=HUD_DIM, width=2)
    save(img, "hud_master.png")

# ---------------------------------------------------------------------------
# Style B: NATO map-symbol (blueprint line art)
# ---------------------------------------------------------------------------
NATO_BG = (245, 246, 240, 255)
NATO_LINE = (20, 24, 20, 255)
NATO_RED = (168, 30, 30, 255)

def nato_frame(s, shape="circle"):
    img = canvas(s, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = s * 0.08
    w = max(3, s // 90)
    if shape == "circle":
        d.ellipse([pad, pad, s - pad, s - pad], outline=NATO_LINE, width=w)
    return img, d

def nato_system(s=512):
    img, d = nato_frame(s)
    cx, cy = s / 2, s / 2
    d.line([(cx - s * 0.24, cy + s * 0.20), (cx + s * 0.24, cy + s * 0.20)], fill=NATO_LINE, width=max(3, s // 100))
    for r in [0.30, 0.22, 0.14]:
        d.arc([cx - s * r, cy - s * r + s * 0.10, cx + s * r, cy + s * r + s * 0.10], 180, 360, fill=NATO_LINE, width=max(3, s // 100))
    d.ellipse([cx - s * 0.015, cy + s * 0.10 - s * 0.015, cx + s * 0.015, cy + s * 0.10 + s * 0.015], fill=NATO_RED)
    save(img, "nato_system.png")

def nato_engagement(s=512):
    img, d = nato_frame(s)
    cx, cy = s / 2, s / 2
    r = s * 0.22
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=NATO_LINE, width=max(3, s // 100))
    d.line([(cx - r * 1.4, cy), (cx - r * 0.5, cy)], fill=NATO_LINE, width=max(3, s // 100))
    d.line([(cx + r * 0.5, cy), (cx + r * 1.4, cy)], fill=NATO_LINE, width=max(3, s // 100))
    d.line([(cx, cy - r * 1.4), (cx, cy - r * 0.5)], fill=NATO_LINE, width=max(3, s // 100))
    d.line([(cx, cy + r * 0.5), (cx, cy + r * 1.4)], fill=NATO_LINE, width=max(3, s // 100))
    d.ellipse([cx - s * 0.02, cy - s * 0.02, cx + s * 0.02, cy + s * 0.02], fill=NATO_RED)
    save(img, "nato_engagement.png")

def nato_crew(s=512):
    img, d = nato_frame(s)
    cx, cy = s / 2, s / 2
    r = s * 0.10
    d.ellipse([cx - r, cy - s * 0.22, cx + r, cy - s * 0.22 + 2 * r], outline=NATO_LINE, width=max(3, s // 110))
    d.arc([cx - s * 0.20, cy - s * 0.02, cx + s * 0.20, cy + s * 0.34], 200, 340, fill=NATO_LINE, width=max(3, s // 100))
    save(img, "nato_crew.png")

def nato_network(s=512):
    img, d = nato_frame(s)
    cx, cy = s / 2, s / 2
    nodes = [(cx, cy - s * 0.22), (cx - s * 0.22, cy + s * 0.12), (cx + s * 0.22, cy + s * 0.12)]
    for i in range(3):
        for j in range(i + 1, 3):
            d.line([nodes[i], nodes[j]], fill=NATO_LINE, width=max(2, s // 130))
    for (x, y) in nodes:
        r = s * 0.045
        d.ellipse([x - r, y - r, x + r, y + r], fill=NATO_BG, outline=NATO_LINE, width=max(2, s // 130))
    save(img, "nato_network.png")

def nato_master(s=1024):
    img, d = nato_frame(s)
    cx, cy = s / 2, s / 2
    d.ellipse([cx - s * 0.30, cy - s * 0.30, cx + s * 0.30, cy + s * 0.30], outline=NATO_LINE, width=max(3, s // 160))
    d.line([(cx, cy - s * 0.26), (cx, cy + s * 0.10)], fill=NATO_RED, width=max(4, s // 130))
    d.line([(cx - s * 0.14, cy - s * 0.02), (cx, cy - s * 0.26), (cx + s * 0.14, cy - s * 0.02)], fill=NATO_RED, width=max(4, s // 130), joint="curve")
    d.line([(cx - s * 0.20, cy + s * 0.10), (cx + s * 0.20, cy + s * 0.10)], fill=NATO_LINE, width=max(3, s // 160))
    save(img, "nato_master.png")

# ---------------------------------------------------------------------------
# Style C: Bold logo / emblem (unit-patch style)
# ---------------------------------------------------------------------------
EMBLEM_ACCENTS = {
    "system": (64, 140, 255, 255),
    "engagement": (220, 60, 60, 255),
    "crew": (70, 190, 110, 255),
    "network": (170, 90, 230, 255),
    "master": (200, 60, 50, 255),
}

def emblem_badge(s, accent):
    img = canvas(s, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = s / 2, s / 2
    outer = s * 0.47
    d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=(28, 30, 34, 255), outline=(12, 12, 14, 255), width=max(3, s // 120))
    ring = s * 0.40
    d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], outline=accent, width=max(4, s // 90))
    inner = s * 0.33
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=(18, 19, 22, 255))
    return img, d, cx, cy, inner

def emblem_system(s=512):
    img, d, cx, cy, inner = emblem_badge(s, EMBLEM_ACCENTS["system"])
    for r in [0.20, 0.12]:
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 200, 340, fill=EMBLEM_ACCENTS["system"], width=max(3, s // 110))
    d.ellipse([cx - s * 0.02, cy - s * 0.02, cx + s * 0.02, cy + s * 0.02], fill=(255, 255, 255, 255))
    d.line([(cx - inner * 0.9, cy), (cx + inner * 0.9, cy)], fill=(60, 62, 68, 255), width=2)
    save(img, "emblem_system.png")

def emblem_engagement(s=512):
    img, d, cx, cy, inner = emblem_badge(s, EMBLEM_ACCENTS["engagement"])
    r = inner * 0.75
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=EMBLEM_ACCENTS["engagement"], width=max(3, s // 110))
    d.line([(cx - inner, cy), (cx + inner, cy)], fill=EMBLEM_ACCENTS["engagement"], width=max(3, s // 130))
    d.line([(cx, cy - inner), (cx, cy + inner)], fill=EMBLEM_ACCENTS["engagement"], width=max(3, s // 130))
    save(img, "emblem_engagement.png")

def emblem_crew(s=512):
    img, d, cx, cy, inner = emblem_badge(s, EMBLEM_ACCENTS["crew"])
    for i, dy in enumerate([-0.10, 0.06]):
        yy = cy + s * dy
        width_ = inner * (0.75 - i * 0.18)
        d.line([(cx - width_, yy + s * 0.05), (cx, yy - s * 0.05), (cx + width_, yy + s * 0.05)],
               fill=EMBLEM_ACCENTS["crew"], width=max(4, s // 90), joint="curve")
    save(img, "emblem_crew.png")

def emblem_network(s=512):
    img, d, cx, cy, inner = emblem_badge(s, EMBLEM_ACCENTS["network"])
    nodes = [(cx, cy - inner * 0.7), (cx - inner * 0.7, cy + inner * 0.45), (cx + inner * 0.7, cy + inner * 0.45), (cx, cy)]
    for i in range(3):
        d.line([nodes[3], nodes[i]], fill=EMBLEM_ACCENTS["network"], width=max(3, s // 130))
    for i, (x, y) in enumerate(nodes):
        r = s * (0.035 if i < 3 else 0.025)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 255) if i == 3 else EMBLEM_ACCENTS["network"])
    save(img, "emblem_network.png")

def emblem_master(s=1024):
    img, d, cx, cy, inner = emblem_badge(s, EMBLEM_ACCENTS["master"])
    for r in [0.24, 0.16]:
        d.arc([cx - s * r, cy - s * r, cx + s * r, cy + s * r], 200, 340, fill=EMBLEM_ACCENTS["master"], width=max(4, s // 130))
    sweep = math.radians(-20)
    d.line([(cx, cy), (cx + inner * 0.85 * math.cos(sweep), cy + inner * 0.85 * math.sin(sweep))], fill=(255, 210, 90, 255), width=max(4, s // 150))
    d.ellipse([cx - s * 0.018, cy - s * 0.018, cx + s * 0.018, cy + s * 0.018], fill=(255, 255, 255, 255))
    for i, r in enumerate([0.44]):
        pass
    save(img, "emblem_master.png")

# ---------------------------------------------------------------------------
# Mod-list "picture" compositions (wide banner per style)
# ---------------------------------------------------------------------------
def picture_hud(w=1024, h=512):
    img = Image.new("RGBA", (w, h), HUD_BG)
    d = ImageDraw.Draw(img)
    for x in range(0, w, 28):
        d.line([(x, 0), (x, h)], fill=(20, 30, 38, 255), width=1)
    for y in range(0, h, 28):
        d.line([(0, y), (w, y)], fill=(20, 30, 38, 255), width=1)
    hud_frame(d, w, h * 0.06, color=HUD_LINE, w=3)
    master = hud_master(1024) if False else Image.open(os.path.join(OUT, "hud_master.png"))
    ms = int(h * 0.8)
    master_r = master.resize((ms, ms), Image.LANCZOS)
    img.alpha_composite(master_r, (int(w * 0.5 - ms / 2), int(h * 0.5 - ms / 2)))
    save(img, "picture_hud.png")

def picture_nato(w=1024, h=512):
    img = Image.new("RGBA", (w, h), NATO_BG)
    d = ImageDraw.Draw(img)
    d.rectangle([w * 0.03, h * 0.06, w * 0.97, h * 0.94], outline=NATO_LINE, width=3)
    master = Image.open(os.path.join(OUT, "nato_master.png"))
    ms = int(h * 0.78)
    master_r = master.resize((ms, ms), Image.LANCZOS)
    img.alpha_composite(master_r, (int(w * 0.5 - ms / 2), int(h * 0.5 - ms / 2)))
    save(img, "picture_nato.png")

def picture_emblem(w=1024, h=512):
    img = Image.new("RGBA", (w, h), (14, 15, 17, 255))
    d = ImageDraw.Draw(img)
    for i in range(6):
        r = (i + 1) * w * 0.09
        d.ellipse([w * 0.5 - r, h * 0.5 - r, w * 0.5 + r, h * 0.5 + r], outline=(28, 29, 32, 255), width=1)
    master = Image.open(os.path.join(OUT, "emblem_master.png"))
    ms = int(h * 0.82)
    master_r = master.resize((ms, ms), Image.LANCZOS)
    img.alpha_composite(master_r, (int(w * 0.5 - ms / 2), int(h * 0.5 - ms / 2)))
    save(img, "picture_emblem.png")

if __name__ == "__main__":
    hud_master(); hud_system(); hud_engagement(); hud_crew(); hud_network()
    nato_master(); nato_system(); nato_engagement(); nato_crew(); nato_network()
    emblem_master(); emblem_system(); emblem_engagement(); emblem_crew(); emblem_network()
    picture_hud(); picture_nato(); picture_emblem()
    print("done")
