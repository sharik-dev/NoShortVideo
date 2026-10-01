# Prépare les captures pour shotsmith : projecteur (voile léger + anneau rouge)
# sur la fonction, et une loupe ronde pour les boutons trop petits pour être
# lus à la taille d'une vignette de l'App Store.
#   raw/<écran>_<lang>.png  ->  build/<écran>_<lang>.png (+ _zoom)
import os
from PIL import Image, ImageDraw, ImageFilter
H = os.path.dirname(os.path.abspath(__file__))
RED = (255, 0, 0)
SPOTS = {  # fractions de la capture ; zoom = côté du recadrage de la loupe
    "watch":      ((0.0, 0.125, 1.0, 0.26), 0.02, None),
    "music":      ((0.03, 0.605, 0.94, 0.225), 0.05, None),
    "syslock":    ((0.035, 0.627, 0.93, 0.204), 0.085, None),
    "syspip":     ((0.373, 0.60, 0.592, 0.153), 0.042, None),
    "library":    ((0.025, 0.225, 0.95, 0.105), 0.04, None),
    "home":       ((0.06, 0.26, 0.88, 0.28), 0.06, None),
    "background": ((0.025, 0.81, 0.95, 0.06), 0.05, None),
}
os.makedirs(f"{H}/build", exist_ok=True)
for name, (spot, rad, zoom) in SPOTS.items():
    for L in ("en", "fr"):
        im = Image.open(f"{H}/raw/{name}_{L}.png").convert("RGB"); W, Hh = im.size
        x0, y0 = spot[0] * W, spot[1] * Hh; x1, y1 = x0 + spot[2] * W, y0 + spot[3] * Hh
        r = rad * W
        # Voile hors projecteur.
        mask = Image.new("L", im.size, 55); ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1, y1), r, fill=0)
        out = Image.composite(Image.new("RGB", im.size, (0, 0, 0)), im, mask)
        # Anneau rouge + halo.
        glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(glow).rounded_rectangle((x0 - 4, y0 - 4, x1 + 4, y1 + 4), r + 4, outline=RED + (255,), width=16)
        glow = glow.filter(ImageFilter.GaussianBlur(18))
        ring = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(ring).rounded_rectangle((x0 - 4, y0 - 4, x1 + 4, y1 + 4), r + 4, outline=RED + (255,), width=8)
        out = Image.alpha_composite(Image.alpha_composite(out.convert("RGBA"), glow), ring)
        out.convert("RGB").save(f"{H}/build/{name}_{L}.png")
        if zoom:
            cx, cy, side = (x0 + x1) / 2, (y0 + y1) / 2, zoom * W
            # Bouton au centre de la loupe, même au bord de l'écran : on
            # prolonge la capture par du noir plutôt que de décaler le cadrage.
            pad = int(side)
            padded = Image.new("RGB", (W + 2 * pad, Hh + 2 * pad), (0, 0, 0)); padded.paste(im, (pad, pad))
            crop = padded.crop((int(cx - side / 2) + pad, int(cy - side / 2) + pad, int(cx + side / 2) + pad, int(cy + side / 2) + pad)).resize((900, 900), Image.LANCZOS)
            m = Image.new("L", (900, 900), 0); ImageDraw.Draw(m).ellipse((0, 0, 899, 899), fill=255)
            z = Image.new("RGBA", (960, 960), (0, 0, 0, 0)); z.paste(crop, (30, 30), m)
            ImageDraw.Draw(z).ellipse((12, 12, 947, 947), outline=RED + (255,), width=24)
            z.save(f"{H}/build/{name}_zoom_{L}.png")
print("ok")
