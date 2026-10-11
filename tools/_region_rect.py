"""找出截图里某个纯色区域的外接矩形。

用来量弹出菜单、卡片、色块这类「一块纯色」的边界 —— 比逐个像素看颜色快得多。
弹出菜单的底色是 `#FAFAFA`（原版实测值），卡片是 `#FFFFFF`，分得开。

用法:
  python tools/_region_rect.py <图片> <RRGGBB> [y最小] [y最大] [最少像素数]

  y最小 / y最大  只在纵向这个范围内找（默认整个高度）
  最少像素数     某一行的命中像素少于这个数就不算这一行（默认 8，用来滤掉
                 抗锯齿的零星像素；扫到菜单时会先命中上百个）

输出：命中行数、行范围、以及这些行的左右边界中位数（抗锯齿会让边缘差 1px，
所以取中位数而不是极值）。
"""

import statistics
import sys

DENSITY = 2.625


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    path = sys.argv[1]
    target = sys.argv[2].lstrip("#")
    want = tuple(int(target[i : i + 2], 16) for i in (0, 2, 4))
    y_lo = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    y_hi = int(sys.argv[4]) if len(sys.argv) > 4 else 10**9
    min_run = int(sys.argv[5]) if len(sys.argv) > 5 else 8

    from PIL import Image

    image = Image.open(path).convert("RGB")
    width, height = image.size
    pixels = image.load()
    y_hi = min(y_hi, height)

    rows = []
    for y in range(max(0, y_lo), y_hi):
        xs = [x for x in range(width) if pixels[x, y] == want]
        if len(xs) >= min_run:
            rows.append((y, xs[0], xs[-1]))

    if not rows:
        print("没找到 #%s 的区域" % target)
        return 1

    lefts = [row[1] for row in rows]
    rights = [row[2] for row in rows]
    left = int(statistics.median(lefts))
    right = int(statistics.median(rights))
    top = rows[0][0]
    bottom = rows[-1][0] + 1

    print("%s  (%dx%d)" % (path, width, height))
    print("颜色 #%s  命中 %d 行（阈值 ≥%d 像素/行）" % (target, len(rows), min_run))
    print("矩形 x=%d..%d  y=%d..%d" % (left, right, top, bottom))
    print(
        "     宽 %d px (%.1f dp)  高 %d px (%.1f dp)"
        % (right - left, (right - left) / DENSITY, bottom - top, (bottom - top) / DENSITY)
    )
    print(
        "     dp 坐标 x=%.1f..%.1f  y=%.1f..%.1f"
        % (left / DENSITY, right / DENSITY, top / DENSITY, bottom / DENSITY)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
