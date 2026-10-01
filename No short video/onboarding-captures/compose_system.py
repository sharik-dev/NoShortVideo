# Écrans système qu'un simulateur ne sait pas produire (WebKit n'y fait ni PiP
# ni lecture en arrière-plan) : vrai fond capturé + élément système iOS
# reconstitué (lecteur de l'écran verrouillé, fenêtre PiP), rendu par Chrome.
import os, subprocess, sys, pathlib
S = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SONG = {"en": ("Long Purr (No Short Mix)", "The Catles"), "fr": ("Long Ronron (No Short Mix)", "Les Chats Noirs")}
BG_LOCK = {"en": "shots/sys_lock2_en.png", "fr": "shots/sys_lock_fr.png"}
BG_HOME = {"en": "shots/clean_home_en.png", "fr": "shots/clean_home_fr.png"}
ALBUM = f"file://{S}/cats/album1.png"; PIPIMG = f"file://{S}/cats/thumb2.png"

ICON = {
 "prev": '<svg viewBox="0 0 40 24" width="40" height="24"><path fill="#fff" d="M19 2v20L4 12zM36 2v20L21 12z"/></svg>',
 "pause": '<svg viewBox="0 0 24 28" width="24" height="28"><rect fill="#fff" x="3" y="2" width="6" height="24" rx="2"/><rect fill="#fff" x="15" y="2" width="6" height="24" rx="2"/></svg>',
 "next": '<svg viewBox="0 0 40 24" width="40" height="24"><path fill="#fff" d="M4 2v20l15-10zM21 2v20l15-10z"/></svg>',
 "airplay": '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="#fff" stroke-width="1.8" opacity=".85"><path d="M5 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-1"/><path fill="#fff" stroke="none" d="M12 14l5 7H7z"/></svg>',
}
BASE = """<html><head><style>*{margin:0;box-sizing:border-box}html,body{background:#000}#s{width:402px;height:874px;position:absolute;left:0;top:0;overflow:hidden;
font-family:-apple-system,'SF Pro Text',sans-serif;background:url('%s') 0 0/402px 874px no-repeat}</style></head><body><div id="s">%s</div></body></html>"""

def lock(L):
    t, a = SONG[L]
    card = f"""<div style="position:absolute;left:14px;right:14px;top:548px;height:178px;border-radius:34px;
      background:rgba(60,55,60,.28);backdrop-filter:blur(26px) saturate(1.6);-webkit-backdrop-filter:blur(26px) saturate(1.6);
      box-shadow:inset 0 0 0 .6px rgba(255,255,255,.35);padding:16px 18px;color:#fff">
      <div style="display:flex;align-items:center;gap:12px">
        <div style="width:54px;height:54px;border-radius:11px;background:url('{ALBUM}') center/cover;box-shadow:0 2px 8px rgba(0,0,0,.25)"></div>
        <div style="flex:1;min-width:0"><div style="font-weight:600;font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{t}</div>
          <div style="font-size:15px;opacity:.72">{a}</div></div>{ICON['airplay']}</div>
      <div style="margin-top:14px;height:5px;border-radius:3px;background:rgba(255,255,255,.28)"><div style="width:34%;height:100%;border-radius:3px;background:#fff"></div></div>
      <div style="display:flex;justify-content:space-between;font-size:11px;font-weight:600;opacity:.6;margin-top:5px"><span>1:12</span><span>-2:22</span></div>
      <div style="display:flex;justify-content:center;align-items:center;gap:52px;margin-top:6px">{ICON['prev']}{ICON['pause']}{ICON['next']}</div></div>"""
    return BASE % (f"file://{S}/{BG_LOCK[L]}", card)

def pip(L):
    win = f"""<div style="position:absolute;left:150px;top:525px;width:238px;height:134px;border-radius:17px;overflow:hidden;
      background:url('{PIPIMG}') center/cover;box-shadow:0 18px 40px rgba(0,0,0,.45),0 0 0 .5px rgba(255,255,255,.25)"></div>"""
    return BASE % (f"file://{S}/{BG_HOME[L]}", win)

for L in ["en", "fr"]:
    for name, fn in [("syslock", lock), ("syspip", pip)]:
        html = pathlib.Path(S, f"_{name}_{L}.html"); html.write_text(fn(L))
        out = os.path.join(S, "shots", f"{name}_{L}.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                        "--force-device-scale-factor=3", "--window-size=402,874", f"--screenshot={out}", f"file://{html}"],
                       capture_output=True)
        print(out, os.path.exists(out))
