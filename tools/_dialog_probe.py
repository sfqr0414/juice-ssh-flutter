"""对话框几何 + 取色对照工具。

用法：
    python tools/_dialog_probe.py <截图.png> <uiautomator.xml> [标签]

输出四段：
1. 节点表（只打对话框相关的、以及带文字的节点）
2. 对话框面板的**像素范围**（从正中一行/一列的连续同色段推出，不依赖 dump）
3. 关键区域的取色（标题、正文、单选标记、按钮、遮罩）
4. 按钮文字的墨迹范围
"""

from __future__ import annotations

import re
import sys
from collections import Counter

import numpy as np
from PIL import Image


def panel_rect(px: np.ndarray, w: int, h: int) -> tuple[int, int, int, int]:
    """找出对话框面板的像素范围。

    做法：屏幕中心一定落在面板里，取那一点的颜色；然后统计**每一行**里
    该颜色的像素个数 —— 属于面板的行即使被文字/输入框打断，个数也很多，
    用它定出上下列；左右边界取其中最「干净」的那一行（通常是内边距那几行）。
    这样不受正文打断中心列的影响（早期版本就是因为只沿中心列找连续段，
    在 Quick Connect 上把输入框的行内空白当成了面板边界）。
    """
    cx, cy = w // 2, h // 2
    panel = px[cy, cx]
    match = np.all(px == panel, axis=2)
    counts = match.sum(axis=1)
    rows = np.where(counts >= max(300, int(counts.max() * 0.6)))[0]
    if len(rows) == 0:
        return 0, 0, w, h
    y0, y1 = int(rows.min()), int(rows.max()) + 1
    best = int(rows[int(np.argmax(counts[rows]))])
    xs = np.where(match[best])[0]
    return int(xs.min()), y0, int(xs.max()) + 1, y1


def main() -> None:
    png, xml = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else png

    im = Image.open(png).convert('RGB')
    w, h = im.size
    px = np.asarray(im).astype(np.int16)

    print('=== %s ===' % label)
    print('--- 节点 ---')
    text = open(xml, encoding='utf-8').read()
    for node in re.findall(r'<node[^>]*>', text):
        b = re.search(r'bounds="([^"]*)"', node).group(1)
        if b == '[0,0][0,0]':
            continue
        cls = re.search(r'class="([^"]*)"', node).group(1).split('.')[-1]
        t = re.search(r'text="([^"]*)"', node)
        t = t.group(1)[:30] if t else ''
        i = re.search(r'resource-id="([^"]*)"', node)
        i = i.group(1).split('/')[-1] if i else ''
        if i or t:
            print('  %-15s %-24s %-22s %s' % (cls, b, i, t))

    x0, y0, x1, y1 = panel_rect(px, w, h)
    print('--- 面板像素范围 [%d,%d][%d,%d]  %d×%d ---'
          % (x0, y0, x1, y1, x1 - x0, y1 - y0))

    def top(rx0, ry0, rx1, ry1, what, dark=True):
        region = px[ry0:ry1, rx0:rx1].reshape(-1, 3)
        if dark:
            mask = region.sum(axis=1) < 450
            region = region[mask]
        if len(region) == 0:
            print('  %-20s (无墨迹)' % what)
            return
        c = Counter(map(tuple, region))
        tot = sum(c.values())
        print('  %-20s 墨迹 %5d  ' % (what, tot)
              + '  '.join('#%02X%02X%02X %.0f%%' % (k[0], k[1], k[2], v * 100.0 / tot)
                          for k, v in c.most_common(3)))

    print('--- 取色（暗色主题请忽略"暗于阈值"的过滤结果）---')
    top(400, 150, 900, 250, 'ActionBar(被遮罩)', dark=False)
    top(x0, y0 + 60, x1, y0 + 140, '标题带', dark=False)
    top(x0 + 50, y0 + 190, x1 - 50, y0 + 300, '第1行带', dark=False)

    print('--- 按钮文字墨迹 ---')
    band = px[y1 - 170:y1 - 40, x0:x1]
    cols = np.where((band.sum(axis=2) < 600).any(axis=0))[0]
    if len(cols):
        print('  相对面板 x %d..%d（绝对 %d..%d）'
              % (cols.min(), cols.max(), x0 + cols.min(), x0 + cols.max()))

    print('--- 面板内逐行墨迹（非面板色像素数 > 0 的连续区间）---')
    inner = px[y0:y1, x0:x1].astype(np.int16)
    panel = px[(y0 + y1) // 2, x0 + 2]
    diff = (np.abs(inner - panel).sum(axis=2) > 30).sum(axis=1)
    runs = []
    start = None
    for i, n in enumerate(diff):
        if n > 0 and start is None:
            start = i
        elif n == 0 and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(diff) - 1))
    for a, b in runs:
        if b - a < 2:
            continue
        width = np.where((np.abs(inner[a:b + 1] - panel).sum(axis=2) > 30).any(axis=0))[0]
        print('  y %4d..%-4d (绝对 %4d..%-4d, 高 %3d)  x %d..%d 峰值%d'
              % (a, b, y0 + a, y0 + b, b - a + 1, x0 + width.min(), x0 + width.max(),
                 diff[a:b + 1].max()))


if __name__ == '__main__':
    main()
