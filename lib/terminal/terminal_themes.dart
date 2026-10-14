import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../data/generated/terminal_palettes.g.dart';

/// @brief 把原版的 260 项调色板数组转成 xterm 需要的 [TerminalTheme]。
///
/// 原版的 `EmulatorView.setColors(int[])` 要求恰好 260 个 int：
/// `[0..255]` 是 256 色表，`[256]` 是默认前景，`[257]` 是默认背景。
/// 这份数据由 `tools/extract_from_apk.py` 从 `com/sonelli/ni0.smali` 里
/// 的 9 个 int 数组直接提取，未做任何人工调整。
class JuiceTerminalThemes {
  /// @brief 私有构造：全部能力都是静态方法。
  const JuiceTerminalThemes._();

  /// @brief 方案数量（对应设置里 `terminal:theme` 的 0..8）。
  static int get count => kTerminalPalettes.length;

  /// @brief 全部方案显示名，顺序即 `terminal:theme` 的取值顺序。
  static List<String> get names => kTerminalThemeNames;

  /// @brief 取某个方案的原始 260 项数组。
  static List<int> paletteAt(int index) {
    if (index < 0 || index >= kTerminalPalettes.length) {
      return kTerminalPalettes.first;
    }
    return kTerminalPalettes[index];
  }

  /// @brief 从调色板数组取一项，并做下标边界保护。
  static Color _color(List<int> palette, int index) =>
      Color(palette[index.clamp(0, kPaletteLength - 1)]);

  /// @brief 默认前景色（数组第 256 项）。
  static Color foregroundAt(int index) => _color(paletteAt(index), 256);

  /// @brief 默认背景色（数组第 257 项）。
  static Color backgroundAt(int index) => _color(paletteAt(index), 257);

  /// @brief 终端画布底色在主题背景上叠的**白色**比例。
  ///
  /// 实测原版 Solarized Dark：主题背景是 `#073642`，画布真正渲染的是
  /// `#254E59`。反推是叠白，且三个通道解出的比例一致到小数点后两位：
  ///
  ///     R: 7  + a*(255-7) = 37 -> a = 0.1210
  ///     G: 54 + a*(255-54) = 78 -> a = 0.1194
  ///     B: 66 + a*(255-66) = 89 -> a = 0.1217
  ///
  /// 取 0.12 恰好得到 `#254E59`。注意这**不是**叠前景色：按叠前景色 0.115
  /// 实现后模拟器实测为 `#224A53`，偏暗。也不要改 `paletteAt()` 的原始数组。
  static const double surfaceOverlay = 0.12;

  /// @brief 快捷键栏底色叠的**前景色**比例（注意：与画布叠的不是同一种颜色）。
  ///
  /// 原版快捷键栏实测 `#1D4750`，按叠白反推三个通道对不上
  /// （0.089 / 0.085 / 0.074）；按叠该方案的前景色 `#EEE8D5` 反推则三通道一致：
  ///
  ///     R: 0.095*238 + 0.905*7  = 28.9 -> 0x1D
  ///     G: 0.095*232 + 0.905*54 = 70.9 -> 0x47
  ///     B: 0.095*213 + 0.905*66 = 80.0 -> 0x50
  static const double keyBarOverlay = 0.095;

  /// @brief 把主题背景按比例混入该方案的前景色。
  ///
  /// 把主题背景按 [overlay] 混入该方案的**前景色**（快捷键栏用这一档）。
  static Color blendWithForeground(int index, double overlay) {
    final palette = paletteAt(index);
    return Color.alphaBlend(
      _color(palette, 256).withValues(alpha: overlay),
      _color(palette, 257),
    );
  }

  /// @brief 把主题背景按 [overlay] 混入白色（终端画布用这一档）。
  static Color blendWithWhite(int index, double overlay) {
    final palette = paletteAt(index);
    return Color.alphaBlend(
      const Color(0xFFFFFFFF).withValues(alpha: overlay),
      _color(palette, 257),
    );
  }

  /// @brief 构造 xterm 的配色。
  ///
  /// 关于数组第 258/259 项：它们确实是一对「光标前景 / 光标背景」
  /// （`TextStyle.smali` 里命名为 `ciCursorForeground` / `ciCursorBackground`），
  /// 但 `EmulatorView.updateText()` 只用了 256/257 去构造 `ColorScheme`，
  /// 3.2.2 里 258/259 唯一被写入的地方是选中文本时 `colors[259] = colors[1]`。
  /// 换句话说**光标实际是用前景色画的**，所以这里沿用前景色，
  /// 而不是照搬 258 —— 那样反而会和原版观感不一致。
  ///
  /// 选区同理：原版靠反显（交换前后景）表现选中，而 xterm 用一层半透明
  /// 覆盖绘制选区，因此取前景色的 30% 透明度来逼近反显观感。
  /// [surfaceOverlay] 大于 0 时，背景会按该比例混入白色 —— 终端画布要用
  /// 这一档（见 [surfaceOverlay]），而快捷键栏底色另用 [blendWithForeground]。
  static TerminalTheme build(int index, {double surfaceOverlay = 0}) {
    final palette = paletteAt(index);
    final foreground = _color(palette, 256);
    final background = _color(palette, 257);

    return TerminalTheme(
      cursor: foreground,
      // 选中区高亮 = 原版 `@color/copy_instructions_start_selection_background`
      // = `#F44336`（红）。此前这里是前景色 30% 透明度，暗色主题下几乎看不出来 ——
      // 用户实测"用'复制从屏幕'选开头和结尾时没有颜色区分提示反馈"。
      // 半透明红作**底色**：用户实测"复制（从屏幕）选中时红色把文字全部覆盖，
      // 看不见内容" —— 之前是不透明 `0xFFF44336`，选区里的字直接被盖掉。
      // 40% 透明度让被选文字仍可读（原版也是底色高亮而不是蒙层）。
      selection: const Color(0x66F44336),
      foreground: foreground,
      background: surfaceOverlay <= 0
          ? background
          : Color.alphaBlend(
              const Color(0xFFFFFFFF).withValues(alpha: surfaceOverlay),
              background,
            ),
      black: _color(palette, 0),
      red: _color(palette, 1),
      green: _color(palette, 2),
      yellow: _color(palette, 3),
      blue: _color(palette, 4),
      magenta: _color(palette, 5),
      cyan: _color(palette, 6),
      white: _color(palette, 7),
      brightBlack: _color(palette, 8),
      brightRed: _color(palette, 9),
      brightGreen: _color(palette, 10),
      brightYellow: _color(palette, 11),
      brightBlue: _color(palette, 12),
      brightMagenta: _color(palette, 13),
      brightCyan: _color(palette, 14),
      brightWhite: _color(palette, 15),
      // 原版没有搜索功能，这三项在本复刻里也用不到，取能看清的值即可。
      searchHitBackground: _color(palette, 3),
      searchHitBackgroundCurrent: _color(palette, 11),
      searchHitForeground: background,
    );
  }

  /// @brief 设置页配色方案条目左侧的预览色块。
  ///
  /// 依据 `res/layout/terminal_theme_item.xml`：条目用一个横向条展示该方案的
  /// 主要颜色。这里取 ANSI 前 8 色 —— 正好是 xterm 默认调色板里最直观的
  /// 一组，也和原版预览条的观感一致。
  static List<Color> swatches(int index) {
    final palette = paletteAt(index);
    return List<Color>.generate(8, (i) => _color(palette, i));
  }
}
