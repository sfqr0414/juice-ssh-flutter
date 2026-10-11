"""在 `uiautomator` 层级里按文案或资源 id 找节点，输出可点的中心坐标。

写脚本点按钮时不要硬编码坐标 —— 换个字号、换个语言就全错位了。
先在 dump 里按文案定位，再 `adb shell input tap <x> <y>`。

**为什么也要匹配资源 id**：原版很多可点控件没有任何文案。例如右下角的
`ImageView` 只有 `resource-id="fab_new_connection"`，`text` 与 `content-desc`
都是空的 —— 只搜文案会得出「原版这里没有按钮」的错误结论。
（这个坑我已经踩过一次。）

用法:
  python tools/_find_node.py <层级.xml> <文案或 id 子串> [--all]

  --all  列出所有匹配项，默认只输出第一个

命中的资源 id 在输出里带 `#` 前缀。
"""

import re
import sys

BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def main():
    args = [a for a in sys.argv[1:] if a != "--all"]
    show_all = "--all" in sys.argv
    if len(args) != 2:
        print(__doc__)
        return 2

    path, needle = args
    needle = needle.lower()

    raw = open(path, encoding="utf-8", errors="replace").read()
    found = []
    for match in re.finditer(r"<node\b([^>]*)>", raw):
        attrs = dict(re.findall(r'([\w:-]+)="([^"]*)"', match.group(1)))
        label = (attrs.get("text") or attrs.get("content-desc") or "").replace(
            "\n", " / "
        )
        resource_id = attrs.get("resource-id", "").split("/")[-1]
        haystacks = [label.lower(), resource_id.lower()]
        if not any(needle in h for h in haystacks if h):
            continue
        bounds = BOUNDS.match(attrs.get("bounds", ""))
        if not bounds:
            continue
        # 没有文案的节点用资源 id 显示，前缀 `#` 表示「这是 id 不是文案」。
        shown = label or ("#" + resource_id if resource_id else "")
        x1, y1, x2, y2 = (int(value) for value in bounds.groups())
        found.append((shown, x1, y1, x2, y2, attrs))

    if not found:
        print("没找到包含 %r 的节点" % needle)
        return 1

    for label, x1, y1, x2, y2, attrs in found if show_all else found[:1]:
        print(
            "tap %d %d      # %s  [%d,%d][%d,%d] clickable=%s"
            % (
                (x1 + x2) // 2,
                (y1 + y2) // 2,
                label[:60],
                x1,
                y1,
                x2,
                y2,
                attrs.get("clickable"),
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
