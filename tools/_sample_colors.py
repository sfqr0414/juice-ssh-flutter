"""对原版截图做定点取色，用来核实那些「资源里查不到、只能看实际效果」的颜色。

用法: python tools/_sample_colors.py <screenshot.png>
"""

import io
import sys
from collections import Counter

from PIL import Image

# (标签, 左, 上, 右, 下) —— 坐标取自 uiautomator 导出的 ui_home.xml
REGIONS = [
    ("状态栏背景", 400, 40, 700, 100),
    ("ActionBar 背景", 400, 190, 700, 240),
    ("ActionBar 标题笔画", 60, 165, 320, 240),
    ("卡片背景(空白处)", 700, 330, 900, 350),
    ("列表背景(卡片之间)", 500, 505, 700, 520),
    ("QuickConnect 标题笔画", 90, 365, 480, 410),
    ("QuickConnect 副标题笔画", 90, 420, 480, 455),
    ("QuickConnect 图标", 950, 360, 1000, 455),
    ("FrequentlyUsed 图标", 915, 590, 1000, 680),
    ("ManageConnections 图标", 920, 1258, 1000, 1348),
    ("Settings 图标", 902, 1480, 1000, 1570),
    ("Welcome 标题笔画", 100, 720, 900, 920),
]


def top_colors(img, box, limit=6, ignore_near=None):
    crop = img.crop(box).convert("RGB")
    counter = Counter(crop.getdata())
    out = []
    for color, count in counter.most_common(60):
        if ignore_near:
            bg = ignore_near
            if all(abs(a - b) <= 12 for a, b in zip(color, bg)):
                continue
        out.append((color, count))
        if len(out) >= limit:
            break
    return out


def hexs(color):
    return "#%02X%02X%02X" % color


def main(path):
    img = Image.open(path)
    print("screenshot: %s  size=%s" % (path, img.size))

    # 先取卡片背景当作「忽略色」的参考
    card_bg = img.convert("RGB").getpixel((800, 340))
    list_bg = img.convert("RGB").getpixel((600, 512))
    print("卡片背景采样 = %s" % hexs(card_bg))
    print("列表背景采样 = %s" % hexs(list_bg))
    print("=" * 90)

    for label, l, t, r, b in REGIONS:
        print("\n%s  box=(%d,%d)-(%d,%d)" % (label, l, t, r, b))
        for color, count in top_colors(img, (l, t, r, b), limit=6):
            print("    %s  x%d" % (hexs(color), count))


if __name__ == "__main__":
    main(sys.argv[1])
