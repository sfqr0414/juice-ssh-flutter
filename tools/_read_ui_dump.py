"""把 uiautomator 导出的视图层级整理成易读的结构，并把像素换算成 dp。

用法: python tools/_read_ui_dump.py <ui.xml>
"""

import io
import re
import sys
import xml.etree.ElementTree as ET

DENSITY = 420.0 / 160.0  # 1080x2400 @ 420dpi


def to_dp(px):
    return round(px / DENSITY, 1)


def parse_bounds(text):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", text or "")
    if not m:
        return None
    return tuple(int(g) for g in m.groups())


def main(path):
    tree = ET.parse(io.open(path, encoding="utf-8"))
    root = tree.getroot()

    def walk(node, depth=0):
        for child in node:
            b = parse_bounds(child.get("bounds"))
            cls = (child.get("class") or "").split(".")[-1]
            rid = child.get("resource-id") or ""
            rid = rid.split("/")[-1] if rid else ""
            text = (child.get("text") or "").replace("\n", "\\n")
            desc = child.get("content-desc") or ""
            visible = child.get("displayed", "true") != "false"

            bits = [cls]
            if rid:
                bits.append("#" + rid)
            if b:
                w, h = b[2] - b[0], b[3] - b[1]
                bits.append(
                    "xy=(%s,%s) wh=(%sx%s)dp=(%sx%s)"
                    % (
                        b[0],
                        b[1],
                        w,
                        h,
                        to_dp(w),
                        to_dp(h),
                    )
                )
            if text:
                cps = " ".join("U+%04X" % ord(c) for c in text if ord(c) > 0x7F)
                bits.append('text="%s"%s' % (text, (" [" + cps + "]") if cps else ""))
            if desc:
                bits.append('desc="%s"' % desc)
            if not visible:
                bits.append("NOT_DISPLAYED")

            print("  " * depth + " ".join(bits))
            walk(child, depth + 1)

    walk(root)


if __name__ == "__main__":
    main(sys.argv[1])
