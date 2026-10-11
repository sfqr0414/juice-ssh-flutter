"""在截图里找出「文字带」的位置与尺寸。

本机模型看不了图片，所以观感只能靠像素测量。这个脚本在一个矩形区域里
逐行（或逐列）统计目标像素数，把连续命中的行/列合并成「文字带」，
输出每条的起止坐标与长度（同时换算 dp，密度 420dpi → 2.625）。

两种扫描方向各有用途：

* `rows`（默认）—— 找**纵向**位置。比如空状态标题在第几行、卡片标题在第几行。
* `cols` —— 找**横向**位置。`uiautomator` 会把 `PagerTabStrip` 里的多个标题
  合并成一个语义节点，拿不到各自的 x，只能这样量。

明暗阈值也分两种：AppBar 是白字压在品牌黄上（背景亮度约 201），用默认的
「暗于 128」一个都找不到，这时要加 `--bright`；但注意亮色主题下卡片底色是
纯白（255），所以用 `--bright` 时必须把矩形收窄到文字所在的那一条，
否则整块白底都会被算成文字。

用法:
  python tools/_text_bands.py <图片> <x1> <y1> <x2> <y2> [--axis rows|cols] [--dark|--bright] [--max N]

  --axis rows   按行扫（默认），输出每条带的上下边界
  --axis cols   按列扫，输出每条带的左右边界
  --dark        命中「亮度 < N」的像素（默认 N=128，深字压浅底）
  --bright      命中「亮度 > N」的像素（默认 N=230，白字压深底）
  --max N       覆盖上面的阈值 N

`--max` 是为了一类特殊情况：`PagerTabStrip` 里非当前标题会被降低不透明度，
`#073642` 半透明压在白底上混出来约 148，用默认的 128 抓不到，用 200 才能
和当前标题一起抓到 —— 这才好数「这一页到底画了几个标签」。

例:
  # 空状态标题在第几行（深字压浅底）
  python tools/_text_bands.py shot.png 0 359 1080 2337

  # 标签条里各标题的左右范围，只扫条带那 32dp 高的一条
  python tools/_text_bands.py shot.png 0 292 1080 343 --axis cols --max 200
"""

import sys

from PIL import Image

DENSITY = 2.625


def luminance(pixel):
    red, green, blue = pixel[:3]
    return 0.299 * red + 0.587 * green + 0.114 * blue


def main():
    positional = []
    axis = "rows"
    mode = "dark"
    explicit_max = None
    argv = sys.argv[1:]
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--axis":
            index += 1
            axis = argv[index]
        elif arg in ("rows", "cols"):
            axis = arg
        elif arg in ("--bright", "--dark"):
            mode = arg[2:]
        elif arg == "--max":
            index += 1
            explicit_max = float(argv[index])
        else:
            positional.append(arg)
        index += 1

    if len(positional) != 5:
        print(__doc__)
        return 2

    threshold = explicit_max if explicit_max is not None else (
        230.0 if mode == "bright" else 128.0
    )

    path = positional[0]
    x1, y1, x2, y2 = (int(value) for value in positional[1:])

    def hit(pixel):
        value = luminance(pixel)
        return value > threshold if mode == "bright" else value < threshold

    image = Image.open(path).convert("RGB")
    width, height = image.size
    pixels = image.load()
    x1, x2 = max(0, x1), min(x2, width)
    y1, y2 = max(0, y1), min(y2, height)

    if axis == "rows":
        span_lo, span_hi = y1, y2
        bands_from = [
            sum(1 for x in range(x1, x2) if hit(pixels[x, y]))
            for y in range(y1, y2)
        ]
    else:
        span_lo, span_hi = x1, x2
        bands_from = [
            sum(1 for y in range(y1, y2) if hit(pixels[x, y]))
            for x in range(x1, x2)
        ]

    bands = []
    begin = None
    for offset, count in enumerate(bands_from):
        here = span_lo + offset
        if count > 0 and begin is None:
            begin = here
        elif count == 0 and begin is not None:
            bands.append((begin, here))
            begin = None
    if begin is not None:
        bands.append((begin, span_hi))

    print("%s  (%dx%d)" % (path, width, height))
    print(
        "矩形 x=%d..%d y=%d..%d  按 %s 扫描  %s阈值=%.0f（命中 %d 条）"
        % (
            x1,
            x2,
            y1,
            y2,
            "行" if axis == "rows" else "列",
            "<" if mode == "dark" else ">",
            threshold,
            len(bands),
        )
    )
    print("%-18s %-10s %s" % ("区间", "长度", "dp"))
    for begin, end in bands:
        print(
            "%-18s %-10s %.1f..%.1f 长 %.1f"
            % (
                "%d..%d" % (begin, end),
                "%d px" % (end - begin),
                begin / DENSITY,
                end / DENSITY,
                (end - begin) / DENSITY,
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
