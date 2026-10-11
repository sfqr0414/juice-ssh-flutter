"""打印一张截图某区域的逐行墨迹轮廓（细粒度），用于看清元素到底画在哪。

用法: python tools/_row_profile.py <png> <x1> <y1> <x2> <y2> [step]
"""
import sys
from PIL import Image

p, x1, y1, x2, y2 = sys.argv[1], *map(int, sys.argv[2:6])
step = int(sys.argv[6]) if len(sys.argv) > 6 else 4

im = Image.open(p).convert("RGB")
px = im.load()
for y in range(y1, y2, step):
    xs = [x for x in range(x1, x2) if min(px[x, y]) < 170]
    if xs:
        # 连续段
        segs, s, prev = [], xs[0], xs[0]
        for x in xs[1:]:
            if x - prev > 6:
                segs.append((s, prev))
                s = x
            prev = x
        segs.append((s, prev))
        print("y=%-5d %3d段 %s" % (y, len(xs), " ".join("%d-%d" % t for t in segs[:8])))
