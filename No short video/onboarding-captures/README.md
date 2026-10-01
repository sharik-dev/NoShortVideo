# Captures de l'onboarding

Les images `onb_<écran>_<en|fr>` d'Assets.xcassets sont de **vraies captures de l'app**.
Seuls les miniatures et les titres des vidéos sont remplacés par des chats (clin d'œil).

À refaire dès que l'interface d'un de ces écrans change.

1. `python3 build_catify.py` → `catify.js` (images `cats/` intégrées en base64, titres EN/FR)
2. Build Debug sur un simulateur iPhone 17 (1206 × 2622), barre d'état figée :
   `xcrun simctl status_bar <udid> override --time 9:41 --batteryState discharging --batteryLevel 100`
3. `./cap.sh <nom> <en|fr> <attente s> [args]` — règle la langue, remplit la Librairie
   (`fixtures.py`), injecte `catify.js` (`-debugCaptureScript`) et capture dans `shots/`.
   **Toujours ajouter** `-storeCapture YES -hasSeenOnboarding YES -hasSeenQuickstart YES` :
   le build Debug montre le téléchargement manuel (usage perso), que la version App Store
   n'a pas — `-storeCapture` le masque. Aucune capture ne doit montrer ⬇︎ ni « Hors ligne ».

| écran | args |
|---|---|
| home | — |
| watch | `-debugOpenURL https://m.youtube.com/watch?v=aqz-KE-bpKQ` (18 s) |
| music | `-debugOpenURL https://music.youtube.com/watch?v=dQw4w9WgXcQ` (24 s) |
| background | music + `-debugOpenURL2 https://en.m.wikipedia.org/wiki/Cat` (fr : `fr.m…/wiki/Chat`, 34 s) |
| library | `-debugOpenDownloads YES -debugOpenVideosFolder YES` (8 s) |

La page d'arrière-plan n'est **pas** YouTube : l'app met la musique en pause quand une vidéo
YouTube démarre, le mini-lecteur y afficherait « pause ».

4. Recadrer en 900 px de large (JPEG q84) dans les imagesets, puis vérifier les zones
   `spot` de `OnboardingView.swift` (fractions de la capture).

## Écran verrouillé et PiP (captures système)

Le simulateur ne sait faire **ni PiP web** (`NotSupportedError`), **ni lecture WebKit en
arrière-plan** (la musique se fige dès qu'on quitte l'app). On part donc de vraies
captures système et on reconstitue l'élément iOS par-dessus :

1. `./cap-system.sh <en|fr>` (optionnel `SIM=<udid>`, `ONLY=testBackgroundAndLock`) —
   lance `OnboardingCaptureTests` (appui home, verrouillage, PiP) et écrit dans `shots/`.
   Un simulateur neuf donne un écran d'accueil propre ; langue système réglée par
   `defaults write -g AppleLanguages` + redémarrage.
2. `python3 compose_system.py` — lecteur de l'écran verrouillé et fenêtre PiP (pochette /
   vidéo de chat) rendus par Chrome sur `shots/sys_lock*` et `shots/clean_home_*`.

Les captures App Store (`../store-screenshots/`) réutilisent tout ça : `prep.py` pose
projecteur et loupes, `shotsmith design.json --out out` compose, puis les PNG sont déposés
dans le brouillon d'appstore-studio (app 6760180650, iPhone 6,5").
