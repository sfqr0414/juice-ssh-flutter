"""对同一块屏幕区域在两份截图里取主要颜色，用来做亮/暗两套主题的逐项核对。

用法: python tools/_color_compare.py 文件A.png 文件B.png "名称:box" ["名称:box" ...]
box 形如 x1,y1,x2,y2
"""
import collections
import sys

from PIL import Image


def top_colors(path, box, n=4):
    im = Image.open(path).convert("RGB")
    c = collections.Counter(im.crop(tuple(box)).getdata())
    total = sum(c.values())
    return [
        "#%02X%02X%02X %5.1f%%" % (p[0][0], p[0][1], p[0][2], 100.0 * p[1] / total)
        for p in c.most_common(n)
    ]


a, b = sys.argv[1], sys.argv[2]
print("  %-16s | %-34s | %s" % ("区域", a.split("\\")[-1], b.split("\\")[-1]))
for spec in sys.argv[3:]:
    name, box = spec.rsplit(":", 1)
    box = [int(v) for v in box.split(",")]
    print("  %-16s | %-34s | %s" % (name, "  ".join(top_colors(a, box, 3)), "  ".join(top_colors(b, box, 3))))
