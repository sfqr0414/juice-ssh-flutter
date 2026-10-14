import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/juice_theme.dart';

/// @brief 动作条溢出 / 长按上下文菜单里的一项。
class JuicePopupItem<T> {
  /// @brief 用返回值与显示文案构造一个菜单项。
  const JuicePopupItem({required this.value, required this.label});

  /// @brief 选中后返回给调用方的值。
  final T value;
  /// @brief 菜单项显示文案。
  final String label;
}

// ---------------------------------------------------------------------------
// 实测几何（原版是 AppCompat 的 `MenuPopupWindow`，420dpi 模拟器）
//
// 两个文案完全不同的菜单量出来是这样的：
//
//   | 菜单                       | 底色矩形(px)        | 文字(px)          |
//   |----------------------------|---------------------|-------------------|
//   | 首页溢出（FAQ / Rate）     | 555..1069 × 138..390| 597..1028 起 172  |
//   | 通讯录溢出（只有 New Group）| 555..1069 × 138..264| 597..1028 起 172  |
//
// 由此定下四条：
//
// 1. **宽度的下限是固定的 196dp**（515px），不随文案变 —— 两项的那个菜单里
//    "View our FAQ" 明显比 "New Group" 长，但两者量到的文字框都是
//    `[597,172][1028,229]`，宽度一模一样。
// 2. **每项 48dp，总高 = 项数 × 48dp，没有任何额外的上下内边距**
//    （一项 126px、两项 252px，正好整数倍）；文字在 48dp 里垂直居中。
// 3. **顶边与锚点顶边对齐**（都是 138px），**右边距屏幕右缘 11px**（4.19dp）。
// 4. 底色是 `#FAFAFA`，**没有 scrim**：弹出时上方那条品牌黄的亮度一点没变。
//
// 为什么不用 Flutter 的 `showMenu`：它有 8dp 的上下内边距（所以高 112dp 而不是
// 96dp）、宽度按内容算（168dp）、底色纯白，而且 `_PopupMenuRouteLayout` 里
// 硬编码了 `_kMenuScreenPadding = 8.0`，菜单离屏幕边缘最少 8dp —— 原版只留
// 4.19dp，这一条靠调参数是绕不过去的，只能自己画。
// ---------------------------------------------------------------------------

/// @brief 单项高度。
const double juicePopupItemHeight = 48;

/// @brief 宽度下限（见上文第 1 条）。
const double juicePopupMinWidth = 196;

/// @brief 单项的左右内边距。原版文字左边界 597px 减去底色左边界 555px = 42px =
/// 16dp。
const double juicePopupHorizontalPadding = 16;

/// @brief 弹层右边距屏幕右缘 11px。
const double _rightInset = 11 / 2.625;

/// @brief 弹出菜单，几何与原版 `MenuPopupWindow` 一致。
///
/// [anchor] 用 overlay 坐标；菜单的顶边与它对齐、右边距按 [anchor] 的右边界算。
/// 返回被点中项的值；点空白处或返回键返回 null。
Future<T?> showJuicePopupMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<JuicePopupItem<T>> items,
  String? title,
  bool anchorAtTouch = false,
}) {
  if (items.isEmpty) return Future<T?>.value();

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future<T?>.value();

  final palette = context.palette;
  final style = TextStyle(
    fontSize: 16,
    // 与原生 `TextView` 的盒子高度一致（1.172em 行高 + 0.19em
    // `includeFontPadding`），这样 48dp 里的垂直居中才是同一个位置。
    height: 1.362,
    color: palette.textHeading,
  );

  // 文案比下限宽时按「内容 + 左右各 16dp」撑开。实测的两个样本都没超过下限，
  // 所以表现就是固定 196dp；留这条是为了长了也不会被截断。
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final label in <String>[
    ?title,
    ...items.map((i) => i.label),
  ]) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
  }

  final width = math.max(
    juicePopupMinWidth,
    widest + juicePopupHorizontalPadding * 2,
  );
  final height =
      juicePopupItemHeight * (items.length + (title == null ? 0 : 1));

  final overlaySize = overlay.size;
  // 溢出菜单（原版 `MenuPopupWindow`）右对齐锚点；长按上下文菜单是 Android 的
  // 浮动菜单，底色框左上角就落在触点上（实测：底色框左边缘 266px 正好等于
  // 触点 x，顶边等于触点 y，行高同为 48dp，宽度仍是「最宽文案 + 左右各 16dp」）。
  final left = (anchorAtTouch ? anchor.left : anchor.right - _rightInset - width)
      .clamp(0.0, math.max(0.0, overlaySize.width - width))
      .toDouble();
  final top = anchor.top
      .clamp(0.0, math.max(0.0, overlaySize.height - height))
      .toDouble();

  return showDialog<T>(
    context: context,
    useSafeArea: false,
    // 原版弹出菜单不遮暗背景，所以 barrier 完全透明。
    barrierColor: Colors.transparent,
    // 原版这一层是原生 `PopupWindow`，界面上根本没有 barrier 这个语义节点；
    // 而 `showDialog` 的透明 barrier 会多出一个满屏、文案为 "Dismiss" 的节点
    // （uiautomator 与读屏软件都能看到，第 58 轮起就记录在案的偏差）。
    // `barrierLabel` 传空串后该节点不再带可见文案，而"点外部关闭"的行为不变。
    barrierLabel: '',
    builder: (dialogContext) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: Material(
            // AppCompat 弹出菜单底色：亮色取 `abc_popup_background_mtrl_mult`
            // = #FAFAFA，暗色 = #303030。第 62 轮把界面切到暗色后，这里原先写死的
            // #FAFAFA 变成了「白字压近白底」，菜单几乎看不见。第 63 轮改为按主题
            // 取值，并用截图核对了原版暗色菜单底色实测就是 (48,48,48) = #303030。
            color: palette.isDark
                ? const Color(0xFF303030)
                : const Color(0xFFFAFAFA),
            elevation: 8,
            child: Column(
              children: [
                // 表头行：原版长按菜单的第一行是 `@string/manage_connection`
                // （实测与其余项同宽同高、不可点），不是可选项。
                //
                // 表头文字取主题的 `colorAccent`（本复刻的 `accentBold`）：原版
                // 暗色下实测表头是 (213,186,49) = #D5BA31，与该调色板的
                // `accentBold` 一致；条目文字仍用 `textHeading`（暗色下实测为纯白，
                // 与克隆一致）。
                if (title != null)
                  SizedBox(
                    height: juicePopupItemHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: juicePopupHorizontalPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(color: palette.accentBold),
                        ),
                      ),
                    ),
                  ),
                for (final item in items)
                  _JuicePopupEntry<T>(
                    item: item,
                    style: style,
                    onTap: () =>
                        Navigator.of(dialogContext).pop<T>(item.value),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// @brief 长按上下文菜单的**兜底**锚点。
///
/// 原版这类菜单是 Android 的浮动上下文菜单，底色框左上角就落在触点上。
/// 本复刻从第 58 轮起在各处长按的 `onLongPress` 外层包 `Listener` 记录
/// `onPointerDown` 的坐标，并以 `anchorAtTouch: true` 把那个点作为锚点，因此
/// 实际渲染位置已经与触点一致（连接、身份、代码片段、端口转发、分组、终端
/// 六处菜单均已逐屏核验）。只有在拿不到触摸坐标时，才退回这里给的固定位置
/// （横向 1/4、纵向 1/3）。
Rect juiceContextMenuAnchor(BuildContext context) {
  final overlay = Overlay.of(context).context.findRenderObject();
  final size = overlay is RenderBox ? overlay.size : const Size(411.4, 914.3);
  return Rect.fromLTWH(
    size.width / 4,
    size.height / 3,
    juicePopupMinWidth,
    0,
  );
}

/// @brief 弹出菜单里的一行：48dp 高、整行可点。
class _JuicePopupEntry<T> extends StatelessWidget {
  /// @brief 用菜单项、文字样式与点击回调构造菜单里的一行。
  const _JuicePopupEntry({
    required this.item,
    required this.style,
    required this.onTap,
  });

  /// @brief 本行对应的菜单项。
  final JuicePopupItem<T> item;
  /// @brief 由弹层统一算好的文字样式。
  final TextStyle style;
  /// @brief 点击本行的回调。
  final VoidCallback onTap;

  /// @brief 构建 48dp 高的菜单行。
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: juicePopupItemHeight,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: juicePopupHorizontalPadding,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}
