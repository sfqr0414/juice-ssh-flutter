import 'dart:math' as math;

import 'package:flutter/material.dart';

/// `androidx.viewpager.widget.PagerTabStrip` 的 Flutter 复刻。
///
/// 原版 `res/layout/address_book.xml`：
///
/// ```xml
/// <ViewPager android:id="@id/viewpager" ...>
///     <PagerTabStrip android:textColor="@color/text_heading"
///                    android:layout_gravity="top"
///                    android:id="@id/pagerTabStrip"
///                    android:layout_width="wrap_content"
///                    android:layout_height="wrap_content" />
/// </ViewPager>
/// ```
///
/// 所以它是一个**浮在页面内容之上**的条带，而不是把内容挤下去的固定标签栏。
///
/// ## 常量（逐个从 smali 读出）
///
/// | 常量 | 值 | 出处 |
/// |---|---|---|
/// | `PagerTabStrip.INDICATOR_HEIGHT` | 3dp | `PagerTabStrip.smali:9` |
/// | `PagerTabStrip.TAB_PADDING` | 16dp | `PagerTabStrip.smali:17` |
/// | `PagerTabStrip.TAB_SPACING` | 32dp | `PagerTabStrip.smali:19`（覆盖了 `PagerTitleStrip` 构造里的 16dp） |
/// | `PagerTitleStrip.SIDE_ALPHA` | **0.6** | `PagerTitleStrip.smali:21`（常量字段），构造里 `setNonPrimaryAlpha(0.6f)`（smali:283） |
///
/// 条带高度没有写死的常量（`wrap_content`），420dpi 实测 84px = **32dp**。
///
/// ## 位置规则（`PagerTitleStrip.updateTextPositions`，smali:1094 起）
///
/// * 当前标题：`left = 宽度/2 - 当前标题宽/2`，即**严格居中**；
/// * 前一个标题：`left = min(0, 当前left - spacing - 前一个宽)`，即**贴左边缘**；
/// * 后一个标题：`left = max(宽度 - 后一个宽, 当前right + spacing)`，即**贴右边缘**；
/// * 再远的标题根本不参与布局。
///
/// 这三条在 420dpi 实测里逐像素对得上：
/// 当前 "Connections" left=438px（居中），前一个 "Port Forwards" left=0px，
/// 后一个 "Identities" left=928px（=1080−152）。
///
/// 注意：`PagerTitleStrip` / `PagerTabStrip` 里**没有任何 `Typeface`/粗体代码**，
/// 所以当前标题并不是粗体，只是不透明度为 1。
///
/// ## 点击行为（`PagerTabStrip.onTouchEvent`，smali:450 起）
///
/// 容易想当然地以为它是「逐个标签做命中测试」，实际不是。`ACTION_UP` 分支只有
/// 两条判断：
///
/// ```java
/// if (x < mCurrText.getLeft() - mTabPadding) {
///     mPager.setCurrentItem(mPager.getCurrentItem() - 1);
/// } else if (x > mCurrText.getRight() + mTabPadding) {
///     mPager.setCurrentItem(mPager.getCurrentItem() + 1);
/// }
/// ```
///
/// 也就是说：**点在当前标题（左右各外扩 `TAB_PADDING`）之外就翻一页**，
/// 落在当前标题附近则什么都不做。另外 `ACTION_MOVE` 里一旦位移超过
/// `mTouchSlop` 就置 `mIgnoreTap`，松手时不再翻页（交给 ViewPager 去滚动）。
///
/// 这解释了一个实测现象：在「Identities」页上，最左边的标签其实是
/// 「Connections」（它是 *prev*，贴左显示），此时点 x=117px 落在
/// 当前标题 "Identities" 左侧 → 于是回到**上一页 Connections**，
/// 而不是跳到第一个标签。
///
/// 翻页动画用 `ViewPager.smoothScrollTo`（velocity=0）的时长
/// `(|Δ页| + 1) × 100ms`（上限 600ms）与它自带的五次方缓出插值器。
class JuicePagerTabStrip extends StatelessWidget {
  const JuicePagerTabStrip({
    super.key,
    required this.titles,
    required this.controller,
    required this.index,
    required this.textColor,
  });

  final List<String> titles;
  final PageController controller;

  /// 当前页索引，用于 `controller` 尚未 attach 时的回退值。
  final int index;

  final Color textColor;

  /// 条带高度。`wrap_content`，420dpi 实测 84px。
  static const double height = 32;

  /// 字号。`PagerTitleStrip` 的默认标题字号 14sp，实测文字框高 51px。
  static const double fontSize = 14;

  /// 相邻标题的间距，`TAB_SPACING`。
  static const double spacing = 32;

  /// 指示条在标题左右各外扩的距离，`TAB_PADDING`。
  static const double tabPadding = 16;

  /// 指示条高度，`INDICATOR_HEIGHT`。
  ///
  /// 第 66 轮实测（420dpi）：原版指示条占 y 351..355（5px ≈ 2dp），其下另有
  /// 一条满宽的 1dp 细线 y 356..358（整行 1080px 纯白）。克隆原本是 3dp 且
  /// **没有**那条细线，于是条带白像素总数 2749 对原版 5318。改成 2dp + 补细线
  /// 后应为 877(文字) + 1170(指示条) + 3240(细线) ≈ 5287，与原版 5318 差 0.6%。
  static const double indicatorHeight = 2;

  /// 指示条下方那条满宽细线的高度，实测 3px ≈ 1dp。
  static const double bottomRuleHeight = 1;

  /// 非当前标题的不透明度，`PagerTitleStrip.SIDE_ALPHA` = 0.6。
  ///
  /// 原版不是渐变：构造函数里 `setNonPrimaryAlpha(0.6f)` 把 prev/next 两个
  /// `TextView` 的文字色一次性设成 `0x99FFFFFF`（`(int)(0.6×255)=0x99` 左移 24 位
  /// 或上原色），只有当"主角"换人时才整体重设。所以这里也是**两档**：
  /// 最靠近中心的那一页 1.0，其余 0.6。
  ///
  /// 实测佐证（420dpi，暗色主题，`text_heading` = 白）：未选中标签
  /// `#999999`（= 白 × 0.6），选中 `#FFFFFF`；亮色下未选中应是
  /// `#586E75 × 0.6` 叠白 ≈ `#9BA8AC`。
  static const double sideAlpha = 0.6;

  /// `ViewPager.smoothScrollTo` 在 `velocity == 0`（点击翻页）时的时长：
  /// `(|Δ页| + 1) × 100ms`，上限 `MAX_SETTLE_DURATION` = 600ms。
  static Duration settleDuration(int pageDelta) =>
      Duration(milliseconds: ((pageDelta.abs() + 1) * 100).clamp(0, 600));

  /// 按 `PagerTabStrip.onTouchEvent` 的 `ACTION_UP` 分支决定翻到哪一页。
  ///
  /// [currentLeft] / [currentWidth] 是当前标题在条带里的实际位置与宽度
  /// （滚动过程中按插值后的位置算，也就是用户看到的位置）。
  void _handleTap(double x, double currentLeft, double currentWidth) {
    final left = currentLeft - tabPadding;
    final right = currentLeft + currentWidth + tabPadding;
    final int target;
    if (x < left) {
      target = index - 1;
    } else if (x > right) {
      target = index + 1;
    } else {
      // 落在当前标题附近：原版这两条判断都不成立，什么都不做。
      return;
    }
    // `setCurrentItem` 内部会把越界值夹到两端，夹完仍是当前页就等于什么都不做。
    if (target < 0 || target >= titles.length) return;
    controller.animateToPage(
      target,
      duration: settleDuration(target - index),
      curve: const _ViewPagerInterpolator(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final page = controller.hasClients &&
                      controller.position.hasContentDimensions
                  ? (controller.page ?? index.toDouble())
                  : index.toDouble();

              final widths = [
                for (final title in titles) _measure(title),
              ];

              // 原版 `PagerTitleStrip` 只持有 **三个** TextView
              // （`mPrevText` / `mCurrText` / `mNextText`），`updateText` 在换页时
              // 重新给它们派文案，页头/页尾则把对应那个设为 `INVISIBLE`。
              // 所以一页里最多只有 prev / curr / next 三个标题参与 layout ——
              // 实测正是：Port Forwards 页 2 个、Connections 页 3 个、
              // Identities 页 2 个。
              final current = page.floor().clamp(0, titles.length - 1);
              final t = (page - current).clamp(0.0, 1.0);

              /// 第 [p] 页时标题 [i] 的左边界；null = 该页不参与 layout。
              double? leftOnPage(int p, int i) {
                if (p < 0 || p >= titles.length) return null;
                final centre = width / 2 - widths[p] / 2;
                if (i == p) return centre;
                if (i == p - 1) {
                  return math.min(0, centre - spacing - widths[i]);
                }
                if (i == p + 1) {
                  return math.max(
                    width - widths[i],
                    centre + widths[p] + spacing,
                  );
                }
                return null;
              }

              // 当前标题只是从左页的居中位置滑向右页属于它的位置；
              // 「上一个 / 下一个」再由它的位置用原版那两条 `min` / `max`
              // 公式推出来，而不是各自独立插值 —— 这样「上一个」会在被挤出
              // 屏幕之前一直贴着左边不动，与原版一致。
              final fromCentre = leftOnPage(current, current)!;
              final toCentre = leftOnPage(current + 1, current) ?? fromCentre;
              final currentLeft = fromCentre + (toCentre - fromCentre) * t;

              final lefts = <int, double>{
                current: currentLeft,
                if (current > 0)
                  current - 1: math.min(
                    0,
                    currentLeft - spacing - widths[current - 1],
                  ),
                if (current + 1 < titles.length)
                  current + 1: math.max(
                    width - widths[current + 1],
                    currentLeft + widths[current] + spacing,
                  ),
              };

              // 「主角」= 离中心最近的那一页。原版在 `positionOffset + 0.5 > 1`
              // （`PagerTitleStrip.smali:1200` 那段）时换主角，也就是跨过 0.5。
              final primary = page.round().clamp(0, titles.length - 1);

              return GestureDetector(
                // 原版条带整体可点（`onTouchEvent` 无条件 `return true`），
                // 所以这里用 opaque 抢下命中测试。
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _handleTap(
                  details.localPosition.dx,
                  currentLeft,
                  widths[current],
                ),
                child: ClipRect(
                  child: Stack(
                    children: [
                      for (final entry in lefts.entries)
                        Positioned(
                          left: entry.value,
                          top: 0,
                          bottom: 0,
                          width: widths[entry.key],
                          child: Center(
                            child: Text(
                              titles[entry.key],
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              // 没有粗体，只有两档不透明度。
                              style: TextStyle(
                                fontSize: fontSize,
                                height: 1.36,
                                color: textColor.withValues(
                                  alpha: entry.key == primary ? 1 : sideAlpha,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // 指示条：贴在条带底部，宽度 = 当前标题左右各外扩 16dp，
                      // 是一个直角矩形（`Canvas.drawRect`）。
                      Positioned(
                        left: currentLeft - tabPadding,
                        bottom: bottomRuleHeight,
                        width: widths[current] + tabPadding * 2,
                        height: indicatorHeight,
                        child: ColoredBox(color: textColor),
                      ),
                      // 指示条下方还有一条满宽细线：实测原版 y 356..358 整行
                      // 1080px 纯白（两个标签页都在，说明是条带结构而非页面元素）。
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: bottomRuleHeight,
                        child: ColoredBox(color: textColor),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 量一段文字在当前字号下的宽度，用来把标题精确摆到条带中心。
  static double _measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

/// `ViewPager` 自带的滚动插值器。
///
/// `ViewPager` 里那个匿名 `Interpolator` 的实现是 `t--; return t*t*t*t*t + 1;`，
/// 换元即 `1 - (1-t)^5` —— 一条精确的五次方缓出曲线。Flutter 的
/// `Curves.easeOutQuint` 只是三次贝塞尔近似，所以这里直接写出原式。
class _ViewPagerInterpolator extends Curve {
  const _ViewPagerInterpolator();

  @override
  double transformInternal(double t) {
    final u = t - 1;
    return u * u * u * u * u + 1;
  }
}
