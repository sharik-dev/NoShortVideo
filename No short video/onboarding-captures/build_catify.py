import base64, io, glob, os, json
from PIL import Image
S=os.path.dirname(os.path.abspath(__file__))
def data(path, size):
    im=Image.open(path).convert("RGB")
    w,h=size; r=max(w/im.width,h/im.height)
    im=im.resize((int(im.width*r)+1,int(im.height*r)+1))
    l=(im.width-w)//2; t=(im.height-h)//2
    im=im.crop((l,t,l+w,t+h)); b=io.BytesIO(); im.save(b,"JPEG",quality=82)
    return "data:image/jpeg;base64,"+base64.b64encode(b.getvalue()).decode()
thumbs=[data(p,(640,360)) for p in sorted(glob.glob(f"{S}/cats/thumb*.*"))]
albums=[data(p,(500,500)) for p in sorted(glob.glob(f"{S}/cats/album*.*"))] or thumbs[:1]
js=open(f"{S}/catify.template.js").read()
video="data:video/mp4;base64,"+base64.b64encode(open(f"{S}/cats/catvideo.mp4","rb").read()).decode()
js=js.replace("__CATVIDEO__",video)
js=js.replace("__THUMBS__",json.dumps(thumbs)).replace("__ALBUMS__",json.dumps(albums))
open(f"{S}/catify.js","w").write(js)
print(len(thumbs),len(albums),len(js)//1024,"KB")
