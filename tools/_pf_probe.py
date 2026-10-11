"""端口转发编辑页的像素核对：文字纵向带、下划线位置与横向范围。

用法: python tools/_pf_probe.py <png>
"""
import sys

from PIL import Image

INK = 200  # 判定「有内容」的亮度阈值


def bands(px, x1, x2, y1, y2, min_dark=2):
    out = []
    cur = None
    for y in range(y1, y2):
        dark = 0
        for x in range(x1, x2):
            c = px[x, y]
            if min(c[:3]) < INK:
                dark += 1
        if dark >= min_dark:
            if cur is None:
                cur = [y, y]
            else:
                cur[1] = y
        else:
            if cur is not None:
                out.append(tuple(cur))
                cur = None
    if cur:
        out.append(tuple(cur))
    return out


def hspan(px, y, x1, x2, pred):
    xs = [x for x in range(x1, x2) if pred(px[x, y])]
    return (min(xs), max(xs)) if xs else None


def main(path):
    im = Image.open(path).convert("RGB")
    px = im.load()
    print("== %s  %dx%d" % (path, im.width, im.height))

    print("-- 纵向文字带 (x 42..1038) --")
    for i, (a, b) in enumerate(bands(px, 42, 1038, 290, 1300), 1):
        print("   %2d  %4d..%-4d  高 %d" % (i, a, b, b - a + 1))

    # 下划线：#666666 附近的深灰，只出现在行底部
    def is_line(c):
        return abs(c[0] - 0x66) < 26 and abs(c[1] - 0x66) < 26 and abs(c[2] - 0x66) < 26

    print("-- 下划线（#666666 横线）--")
    for name, y1, y2 in (
        ("name", 422, 528),
        ("local_port", 781, 887),
        ("remote_host", 908, 1014),
        ("remote_port", 1035, 1141),
    ):
        found = []
        for y in range(y1, y2):
            s = hspan(px, y, 200, 1060, is_line)
            if s and s[1] - s[0] > 100:
                found.append((y, s))
        if found:
            y = found[len(found) // 2][0]
            print("   %-12s y=%s  x=%d..%d" % (name, [f[0] for f in found], found[len(found) // 2][1][0], found[len(found) // 2][1][1]))
        else:
            print("   %-12s 未找到" % name)

    # 复选框方块：CheckBox 的方框是深色描边，找 1162..1246 里的方块
    print("-- 复选框区域 (y 1162..1246) --")
    for y in range(1162, 1247, 4):
        s = hspan(px, y, 42, 300, lambda c: min(c[:3]) < 150)
        if s:
            print("   y=%d  x=%d..%d" % (y, s[0], s[1]))


if __name__ == "__main__":
    main(sys.argv[1])
