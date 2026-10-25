import json, sys, os, urllib.request
op = urllib.request.build_opener(); op.addheaders=[('User-Agent','Mozilla/5.0')]; urllib.request.install_opener(op)
# usage: ph_get.py asset res outdir  -- downloads the glTF bundle (gltf + bin + textures)
a, res, out = sys.argv[1:4]
d = json.load(urllib.request.urlopen(f"https://api.polyhaven.com/files/{a}"))
g = d["gltf"][res]["gltf"]
os.makedirs(out, exist_ok=True)
def get(url, rel):
    p = os.path.join(out, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    urllib.request.urlretrieve(url, p)
get(g["url"], os.path.basename(g["url"]))
for rel, v in g.get("include", {}).items():
    get(v["url"], rel)
print(a, "ok", os.listdir(out))
