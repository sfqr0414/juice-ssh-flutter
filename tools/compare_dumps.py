"""把原版与复刻的 `uiautomator` 层级放在一起逐项对照。

背景：本机模型看不到图片，`uiautomator dump` 导出的层级就是最可靠的「视觉」证据 ——
它同时给出文案与像素坐标（这里换算成 dp，密度 420dpi → 2.625）。

原版是原生 View 树（标题、副标题各是一个 TextView）；
复刻是 Flutter 的 semantics 树（一张卡片合成一个带换行描述的节点）。
所以先把两边都归一化成「标签 + 纵向位置」的序列，再做序列对齐。

两个曾经吃过亏的地方：

1. **不能按序号硬对齐。** 两边节点数天然不同（原版会把 TextView 和它的
   容器都报出来，Flutter 会合并），按序号对齐会把后面所有项都标成「不一致」，
   真正的差异反而被淹没。这里改用标签序列的 LCS 对齐，只报真实的多/少/错位。
2. **不能只认 `text`/`content-desc`。** 原版的 FAB 是**没有任何内容描述**的
   `ImageButton`，只靠 desc 取标签会把它整个丢掉 —— 于是曾误判成
   「身份页没有 FAB」。现在对没有文案的可点击节点回退到资源 id（`#fab_new_identity`）。

用法:
  python tools/compare_dumps.py <原版.xml> <复刻.xml> [--ids]

  --ids  把所有带 resource-id 的节点都列出来（默认只列无文案的可点击节点），
         用来核对 `pagerTabStrip` / `list_container` 这类容器。
"""

import re
import sys
import xml.etree.ElementTree as ET

DENSITY = 2.625  # 420dpi

# Flutter 会把图标占位符写成 "Icon"，原版里图标是 ImageView 没有文字。
NOISE = {"icon"}

BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def dp(px):
    return round(px / DENSITY, 1)


def short_id(value):
    return "#" + value.split("/")[-1] if value else ""


def parse(path, include_ids=False):
    """返回 [(标签, top_px, height_px), ...]，按纵向、横向排序。"""
    tree = ET.parse(path)
    items = []
    for node in tree.iter():
        bounds = node.get("bounds")
        if not bounds:
            continue
        match = BOUNDS.match(bounds)
        if not match:
            continue
        x1, y1, x2, y2 = (int(value) for value in match.groups())

        raw = node.get("text") or node.get("content-desc") or ""
        if not raw.strip():
            # 没文案的节点：只有「可点击」或显式要求时才用资源 id 兜底，
            # 否则满屏的容器节点会把有用的信息淹掉。
            resource = short_id(node.get("resource-id", ""))
            clickable = node.get("clickable") == "true"
            if not resource or not (include_ids or clickable):
                continue
            raw = resource

        # 一个节点里的多行描述拆成多条标签。
        for line in raw.split("\n"):
            label = " ".join(line.split())
            if not label or label.lower() in NOISE:
                continue
            items.append((label, x1, y1, y2 - y1))

    items.sort(key=lambda row: (row[2], row[1]))
    return items


def align(left, right):
    """按标签做 LCS 对齐，返回 [(左下标 or None, 右下标 or None), ...]。"""
    n, m = len(left), len(right)
    table = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            if left[i][0] == right[j][0]:
                table[i][j] = table[i + 1][j + 1] + 1
            else:
                table[i][j] = max(table[i + 1][j], table[i][j + 1])

    pairs = []
    i = j = 0
    while i < n and j < m:
        if left[i][0] == right[j][0]:
            pairs.append((i, j))
            i += 1
            j += 1
        elif table[i + 1][j] >= table[i][j + 1]:
            pairs.append((i, None))
            i += 1
        else:
            pairs.append((None, j))
            j += 1
    while i < n:
        pairs.append((i, None))
        i += 1
    while j < m:
        pairs.append((None, j))
        j += 1
    return pairs


def main():
    argv = [a for a in sys.argv[1:] if a != "--ids"]
    include_ids = "--ids" in sys.argv
    if len(argv) != 2:
        print(__doc__)
        return 2

    left = parse(argv[0], include_ids)
    right = parse(argv[1], include_ids)

    print("原版 %d 条标签，复刻 %d 条标签" % (len(left), len(right)))
    print("(只列有文案的节点；无文案的可点击节点回退到资源 id，前缀 #)")
    print()
    print("%-44s %8s | %-44s %8s" % ("原版", "top", "复刻", "top"))
    print("-" * 112)

    problem = 0
    for i, j in align(left, right):
        l_text = left[i][0] if i is not None else ""
        r_text = right[j][0] if j is not None else ""
        l_top = "%.1f" % dp(left[i][2]) if i is not None else "-"
        r_top = "%.1f" % dp(right[j][2]) if j is not None else "-"

        if i is not None and j is not None:
            delta = dp(right[j][2]) - dp(left[i][2])
            flag = "" if abs(delta) <= 1.5 else "   top 差 %+.1fdp" % delta
            if flag:
                problem += 1
            print(
                "%-44s %8s | %-44s %8s%s"
                % (l_text[:44], l_top, r_text[:44], r_top, flag)
            )
        elif i is not None:
            problem += 1
            print("%-44s %8s | %-44s %8s   仅原版有" % (l_text[:44], l_top, "", "-"))
        else:
            problem += 1
            print("%-44s %8s | %-44s %8s   仅复刻有" % ("", "-", r_text[:44], r_top))

    print("-" * 112)
    print("需要人工确认 %d 行 / 对齐 %d 行" % (problem, len(align(left, right))))
    return 0 if problem == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
