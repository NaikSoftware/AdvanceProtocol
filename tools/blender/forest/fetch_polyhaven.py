"""Завантажує джерела хвойних з Poly Haven (CC0): pine_tree_01 і fir_tree_01, .blend 1k з текстурами.
Запуск: python3 -I fetch_polyhaven.py <тека>
Пише <тека>/<актив>/...; наявні файли не завантажує вдруге. Тека — поза репозиторієм: Godot
ламає імпорт, якщо бачить .blend у проєкті.
"""
import json
import os
import sys
import urllib.request

op = urllib.request.build_opener()
op.addheaders = [("User-Agent", "advance-protocol-asset-fetch/1.0")]
urllib.request.install_opener(op)
D = sys.argv[1]
for a in ("pine_tree_01", "fir_tree_01"):
    x = json.load(urllib.request.urlopen(f"https://api.polyhaven.com/files/{a}"))["blend"]["1k"]["blend"]
    jobs = [(x["url"], f"{a}/{x['url'].split('/')[-1]}")] + [(v["url"], f"{a}/{k}") for k, v in x["include"].items()]
    for u, f in jobs:
        p = os.path.join(D, f)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.exists(p):
            urllib.request.urlretrieve(u, p)
        print(f, os.path.getsize(p), flush=True)
