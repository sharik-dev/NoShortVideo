import json, sys, os, glob, shutil, time
from PIL import Image
S=os.path.dirname(os.path.abspath(__file__))
data, lang = sys.argv[1], sys.argv[2]
docs=f"{data}/Documents"; dl=f"{docs}/Downloads"; os.makedirs(dl, exist_ok=True)
titles = {"fr": ["Mon chat refuse de regarder des Shorts (documentaire complet)","Chef Moustache cuisine des pâtes — 45 min en direct",
                 "L'ascension du Mont Miaou — randonnée intégrale","Routine muscu de chaton : aucun raccourci",
                 "Pluie & ronrons — 8 heures, zéro pub"],
          "en": ["My cat refuses to watch Shorts (full documentary)","Chef Whiskers cooks pasta — 45 min live",
                 "Climbing Mount Meowtain — the full hike","Kitten gym routine: no shortcuts",
                 "Rain & purring — 8 hours, zero ads"]}[lang]
durs=[2712,2745,3980,1860,28800]
thumbs=sorted(glob.glob(f"{S}/cats/thumb*.*"))
now=time.time()-978307200
vids=[]
for i,t in enumerate(titles):
    vid=f"cat{i+1:02d}xxxxx"[:11]
    im=Image.open(thumbs[i%len(thumbs)]).convert("RGB"); im.thumbnail((640,640)); im.save(f"{dl}/{vid}.jpg","JPEG",quality=85)
    open(f"{dl}/{vid}.mp4","wb").write(b"\0"*1024)
    vids.append(dict(id=vid,title=t,thumbnailURL=f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",url=f"https://m.youtube.com/watch?v={vid}",
                     lastTime=0,duration=durs[i],dateAdded=now-i*3600,folder="",localFileName=f"{vid}.mp4"))
json.dump(vids, open(f"{docs}/saved_videos.json","w"))
print("ok", len(vids))
