# Captures App Store — Meow-Tube (iPhone 6,5", EN + FR)

Version actuelle : **3D** (`out3d/`). L'ancienne version à plat (`design.json` → `out/`) reste
pour mémoire.

```bash
python3 prep.py                          # raw/ -> build/ (projecteur, loupes)
cd phone3d && python3 -m http.server 8765 &
node render.mjs ../phones/x_en.png "shot=build/x_en.png&yaw=-20&pitch=8&roll=-14&w=1200&h=1900&dist=2.35"
python3 gen_design.py                    # -> design3d.json (mise en page, panorama, loupes)
shotsmith design3d.json --out out3d
```

- `raw/` : vraies captures de l'app (cf. `../onboarding-captures/README.md`).
- `phone3d/` : rendu three.js d'un vrai iPhone 3D, capture plaquée sur l'écran. Modèle
  « (FREE) iPhone 13 Pro 2021 » par SDC PERFORMANCE (Sketchfab), **CC-BY-4.0** — lien
  symbolique vers la bibliothèque partagée du NVMe. Crédit à conserver si on le publie ailleurs.
- `phones/markers.json` : position des boutons ⬇︎ / MP3 sur les iPhone 3D, trouvée en
  rendant un marqueur vert à leur place — c'est ce qui ancre les loupes.
- `cats/` : poses de la mascotte de l'app (planches `Assets.xcassets/Cat`), en rouge.
- Écrans 2-3 : un seul iPhone à cheval sur la jonction (centré à x=1 puis x=0), et un
  chat qui saute de l'un à l'autre.
- Déposées dans le brouillon appstore-studio (app 6760180650, `APP_IPHONE_65`).
