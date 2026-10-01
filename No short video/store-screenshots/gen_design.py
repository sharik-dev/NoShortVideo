# Génère design3d.json : iPhone 3D (phone3d/ -> phones/), mascotte de l'app
# (cats/). Aucun écran ne montre le téléchargement : la version App Store
# n'en a plus d'interface. Tout le calcul de mise en page est ici ;
# shotsmith ne fait que composer.
import json, os
from PIL import Image
H = os.path.dirname(os.path.abspath(__file__))
SW, SH = 1242, 2688                     # iPhone 6,5" portrait
MK = json.load(open(f"{H}/phones/markers.json"))

def phone(name, cx, cy, h, z=3):
    """Téléphone 3D centré en (cx, cy), hauteur h (fractions du slide)."""
    iw, ih = Image.open(f"{H}/phones/{name}_en.png").size
    w = h * SH * iw / ih / SW
    layer = {"id": f"ph-{name}", "type": "sticker", "src": {"en": f"phones/{name}_en.png", "fr": f"phones/{name}_fr.png"},
             "at": {"x": cx, "y": cy, "w": round(w, 4)}, "anchor": "center", "z": z,
             "shadow": {"y": 0.018, "blur": 0.03, "color": "rgba(0,0,0,0.75)"}}
    return layer, (cx - w / 2, cy - h / 2, w, h)

def zoom(src, box, mark, bx, by, size=0.40):
    """Loupe en (bx, by) reliée par un trait rouge au bouton repéré sur le 3D."""
    x0, y0, w, h = box
    px, py = x0 + mark["fx"] * w, y0 + mark["fy"] * h
    X = lambda v: v * SW; Y = lambda v: v * SH
    svg = (f'<svg viewBox="0 0 {SW} {SH}" preserveAspectRatio="none" style="position:absolute;left:0;top:0;width:100%;height:100%">'
           f'<line x1="{X(px):.0f}" y1="{Y(py):.0f}" x2="{X(bx):.0f}" y2="{Y(by):.0f}" stroke="#FF1A1A" stroke-width="8" stroke-linecap="round"/>'
           f'<circle cx="{X(px):.0f}" cy="{Y(py):.0f}" r="44" fill="none" stroke="#FF1A1A" stroke-width="9"/></svg>')
    return [{"id": "zline", "type": "html", "content": svg, "at": {"x": 0, "y": 0, "w": 1, "h": 1}, "z": 5},
            {"id": "zoom", "type": "sticker", "src": {"en": f"build/{src}_zoom_en.png", "fr": f"build/{src}_zoom_fr.png"},
             "at": {"x": bx, "y": by, "w": size}, "anchor": "center", "z": 6,
             "glow": {"color": "rgba(255,0,0,0.55)", "blur": 0.02}}]

def cat(pose, x, y, w, flip=False, z=7, rot=0):
    return {"id": f"cat-{pose}-{x}", "type": "sticker", "src": f"cats/cat_{pose}.png", "at": {"x": x, "y": y, "w": w},
            "anchor": "bottom" if not rot else "center", "z": z, "rotate": rot,
            "scale": None, "glow": {"color": "rgba(255,0,0,0.45)", "blur": 0.012},
            **({"flip": True} if flip else {})}

def paws(seed, avoid):
    return {"id": "paws", "type": "scatter", "items": ["cats/paw.png"], "size": 0.045, "seed": seed, "opacity": 0.13,
            "jitter": 0.4, "avoid": avoid, "z": 1,
            "spots": [{"x": 0.08, "y": 0.30}, {"x": 0.14, "y": 0.36}, {"x": 0.09, "y": 0.43}, {"x": 0.15, "y": 0.49},
                      {"x": 0.88, "y": 0.72}, {"x": 0.93, "y": 0.78}, {"x": 0.87, "y": 0.85}, {"x": 0.92, "y": 0.91}]}

def bg(glows):
    return {"id": "bg", "type": "background", "gradient": {"angle": 180, "stops": ["#1B0404", "#0B0B0B", "#060606"]},
            "glows": [{"x": x, "y": y, "r": r, "color": f"rgba(255,0,0,{a})"} for x, y, r, a in glows], "vignette": 0.3}

def copy(eyebrow, headline, x=0.5, align="center", w=0.9):
    return [{"id": "eyebrow", "type": "eyebrow", "content": eyebrow, "color": "#FF1A1A", "size": 0.021, "align": align,
             "at": {"x": x, "y": 0.052, "w": w}, "anchor": "top" if align == "center" else "top-left", "z": 8},
            {"id": "headline", "type": "headline", "content": headline, "accent": "#FF1A1A", "size": 0.038, "weight": 800,
             "transform": "none", "tracking": -0.01, "lineHeight": 1.04, "align": align,
             "at": {"x": x, "y": 0.082, "w": w}, "anchor": "top" if align == "center" else "top-left", "z": 8,
             "shadow": {"y": 0.004, "blur": 0.02, "color": "rgba(0,0,0,0.6)"}}]

T = lambda en, fr: {"en": en, "fr": fr}
slides = []

# 1 — Héros : deux iPhone croisés, le chat assis sur celui du fond.
a, abox = phone("hero_music", 0.66, 0.60, 0.56, z=3)
b, bbox = phone("hero_watch", 0.38, 0.64, 0.60, z=4)
slides.append({"id": "01-hero", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.7, 0.8, 0.18)]), paws(3, [0.2, 0.25, 0.8, 1]),
    *copy(T("Meow-Tube", "Meow-Tube"), T("Videos & music\n*with zero ads*", "Vidéos et musique\n*sans aucune pub*")),
    a, b, cat("sitting", abox[0] + abox[2] * 0.72, abox[1] + 0.035, 0.16, z=5)]})

# 2 — Librairie : les favoris, rangés par dossier.
lib, libox = phone("library", 0.5, 0.635, 0.66)
slides.append({"id": "02-library", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.75, 0.8, 0.2)]), paws(5, [0.15, 0.25, 0.85, 1]),
    *copy(T("Library", "Librairie"), T("Your favourites,\n*all in one place*", "Tes favoris,\n*tous au même endroit*")),
    lib, cat("jump", 0.84, 0.30, 0.26, z=7, rot=-8)]})

# 3 — Écran verrouillé.
l, lbox = phone("lock", 0.5, 0.635, 0.66)
slides.append({"id": "03-lock", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.75, 0.8, 0.2)]), paws(11, [0.15, 0.25, 0.85, 1]),
    *copy(T("Background play", "Arrière-plan"), T("Music keeps playing\n*screen locked*", "La musique continue\n*écran verrouillé*")),
    l, cat("sitdown", 0.86, 0.975, 0.15, z=5)]})

# 4 — Musique sans pub.
m, mbox = phone("music", 0.56, 0.635, 0.66)
slides.append({"id": "04-music", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.75, 0.8, 0.2)]), paws(13, [0.15, 0.25, 0.9, 1]),
    *copy(T("Music", "Musique"), T("Your music,\n*zero ads*", "Ta musique,\n*zéro pub*")),
    m, cat("walk", 0.20, 0.975, 0.24, z=5)]})

# 5 — PiP.
p, pbox = phone("pip", 0.5, 0.635, 0.66)
slides.append({"id": "05-pip", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.75, 0.8, 0.2)]), paws(17, [0.15, 0.25, 0.85, 1]),
    *copy(T("Picture in Picture", "Image dans l'image"), T("Keep watching in a\n*floating window*", "Regarde en\n*fenêtre flottante*")),
    p, cat("idle", 0.15, 0.975, 0.22, z=5)]})

# 6 — Accueil sans Shorts.
h_, hbox = phone("home", 0.5, 0.635, 0.66)
slides.append({"id": "06-noshorts", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.75, 0.8, 0.2)]), paws(19, [0.15, 0.25, 0.85, 1]),
    *copy(T("No Shorts", "Zéro Shorts"), T("Your usual sites,\n*without Shorts*", "Tes sites préférés,\n*sans les Shorts*")),
    h_, cat("sitting", 0.85, 0.975, 0.14, z=5)]})

# 7 — Mini-lecteur pendant la navigation.
w_, wbox = phone("browse", 0.5, 0.635, 0.66)
slides.append({"id": "07-browse", "layers": [bg([(0.5, 0.0, 0.85, 0.42), (0.5, 0.75, 0.8, 0.2)]), paws(23, [0.15, 0.25, 0.85, 1]),
    *copy(T("While you browse", "Pendant que tu navigues"), T("Keep the music on\n*while you browse*", "Ta musique continue\n*quand tu navigues*")),
    w_, cat("walk", 0.82, 0.975, 0.22, z=5, flip=True)]})

def clean(o):
    if isinstance(o, dict): return {k: clean(v) for k, v in o.items() if v is not None}
    if isinstance(o, list): return [clean(v) for v in o]
    return o

design = {"assetRoot": ".", "out": "out3d", "devices": ["iphone65"], "orientation": "portrait", "locales": ["en", "fr"],
          "defaultLocale": "en", "ascLocales": {"en": "en-US", "fr": "fr-FR"}, "slides": clean(slides)}
json.dump(design, open(f"{H}/design3d.json", "w"), indent=1, ensure_ascii=False)
print("design3d.json:", len(slides), "slides")
