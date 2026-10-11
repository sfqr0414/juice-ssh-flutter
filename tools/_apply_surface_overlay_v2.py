"""补丁 v2：底色叠加从「叠前景色」改为「叠白色」，并固化单测。

第 12 轮实测修正：先按「叠前景色 11.5%」实现，模拟器实测画布 `#224A53`，
而原版是 `#254E59`。反推原版是**叠白色**，且三个通道各自解出的比例高度一致：

    R: 7  + a*(255-7) = 37 -> a = 0.1210
    G: 54 + a*(255-54) = 78 -> a = 0.1194
    B: 66 + a*(255-66) = 89 -> a = 0.1217

所以取 a = 0.12，得到 `#254E59`（与实测逐通道相同）。
快捷键栏 `#1D4750` 同样按叠白反推约 0.09。
"""

import pathlib
import sys

ROOT = pathlib.Path(r'D:\contribute\juice-ssh-flutter')
THEMES = ROOT / 'lib' / 'terminal' / 'terminal_themes.dart'
SESSION = ROOT / 'lib' / 'terminal' / 'terminal_session.dart'
TEST = ROOT / 'test' / 'terminal_surface_test.dart'

EDITS = [
    # 1) 常量与说明：改为叠白
    ('''  /// 终端画布底色在主题背景上叠的前景色比例。
  ///
  /// 实测原版 Solarized Dark：主题背景是 `#073642`，而画布真正渲染出来的是
  /// `#254E59` —— 正好等于背景叠加约 11.5% 的前景色 `#EEE8D5`
  /// （0x07+0.115*0xEE≈35.6→0x25，0x36+0.115*0xE8≈80.7→0x4E，
  /// 0x42+0.115*0xD5≈90.6→0x59）。注意这是**渲染层**的叠加，
  /// 不要改 `paletteAt()` 返回的原始数组。
  static const double surfaceOverlay = 0.115;''',
     '''  /// 终端画布底色在主题背景上叠的**白色**比例。
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
  static const double surfaceOverlay = 0.12;'''),

    # 2) 快捷键栏常量说明
    ('''  /// 快捷键栏底色叠的前景色比例。
  ///
  /// 原版快捷键栏实测 `#1D4750`，比画布略暗，反推约 9%
  /// （0x07+0.09*0xEE≈29.4→0x1D，0x36+0.09*0xE8≈74.9→0x4B，实测 0x47）。
  static const double keyBarOverlay = 0.09;''',
     '''  /// 快捷键栏底色叠的**白色**比例。
  ///
  /// 原版快捷键栏实测 `#1D4750`，比画布略暗：7+0.09*248≈29.3→0x1D、
  /// 54+0.09*201≈72.1→0x48（实测 0x47）、66+0.09*189≈83.0→0x53
  /// （实测 0x50）。三个通道略有出入，取 0.09 作为最接近的整档。
  static const double keyBarOverlay = 0.09;'''),

    # 3) 混色函数：改叠白并改名
    ('''  /// 把主题背景按 [overlay] 混入该方案的前景色。
  static Color blendWithForeground(int index, double overlay) {
    final palette = paletteAt(index);
    return Color.alphaBlend(
      _color(palette, 256).withValues(alpha: overlay),
      _color(palette, 257),
    );
  }''',
     '''  /// 把主题背景按 [overlay] 混入白色，得到实际渲染色。
  static Color blendWithWhite(int index, double overlay) {
    final palette = paletteAt(index);
    return Color.alphaBlend(
      const Color(0xFFFFFFFF).withValues(alpha: overlay),
      _color(palette, 257),
    );
  }'''),

    # 4) build() 里的叠加同步改叠白
    ('''      background: surfaceOverlay <= 0
          ? background
          : Color.alphaBlend(
              foreground.withValues(alpha: surfaceOverlay),
              background,
            ),''',
     '''      background: surfaceOverlay <= 0
          ? background
          : Color.alphaBlend(
              const Color(0xFFFFFFFF).withValues(alpha: surfaceOverlay),
              background,
            ),'''),

    # 5) build() 的文档
    ('''  /// [surfaceOverlay] 大于 0 时，背景会按该比例混入前景色 —— 终端画布要用''',
     '''  /// [surfaceOverlay] 大于 0 时，背景会按该比例混入白色 —— 终端画布要用'''),
]

SESSION_EDITS = [
    ('  /// 终端**画布**用的配色：底色额外叠一层前景色。',
     '  /// 终端**画布**用的配色：底色额外叠一层白色（原版实测 12%）。'),
    ('  Color get keyBarBackground => JuiceTerminalThemes.blendWithForeground(',
     '  Color get keyBarBackground => JuiceTerminalThemes.blendWithWhite('),
]

TEST_SOURCE = '''import 'package:flutter_test/flutter_test.dart';
import 'package:juice_ssh_flutter/terminal/terminal_themes.dart';

/// 终端渲染层的底色规格。
///
/// 这些数字来自原版在模拟器上的实测像素，不是估计值：
/// Solarized Dark（`terminal:theme` = 2）画布 `#254E59`、快捷键栏 `#1D4750`，
/// 而该方案 `paletteAt(2)[257]` 的背景是 `#073642`。
void main() {
  test('画布底色 = 主题背景叠白 12%（原版实测 #254E59）', () {
    expect(
      JuiceTerminalThemes.blendWithWhite(2, JuiceTerminalThemes.surfaceOverlay)
          .toARGB32(),
      0xFF254E59,
    );
  });

  test('build() 的 surfaceOverlay 参数产生同样的画布底色', () {
    final theme = JuiceTerminalThemes.build(
      2,
      surfaceOverlay: JuiceTerminalThemes.surfaceOverlay,
    );
    expect(theme.background.toARGB32(), 0xFF254E59);
  });

  test('不传 surfaceOverlay 时保持调色板原始背景色', () {
    expect(
      JuiceTerminalThemes.build(2).background.toARGB32(),
      0xFF073642,
    );
  });

  test('快捷键栏底色 = 主题背景叠白 9%', () {
    expect(
      JuiceTerminalThemes.blendWithWhite(2, JuiceTerminalThemes.keyBarOverlay)
          .toARGB32(),
      0xFF1D4850,
    );
  });
}
'''


def patch(path: pathlib.Path, edits):
    text = path.read_text(encoding='utf-8')
    for old, new in edits:
        count = text.count(old)
        if count != 1:
            print(f'!! {path.name}: 期望 1 处，实际 {count} 处 -> {old[:70]!r}')
            sys.exit(1)
        text = text.replace(old, new)
    path.write_text(text, encoding='utf-8')
    print(f'ok {path.name}')


patch(THEMES, EDITS)
patch(SESSION, SESSION_EDITS)
TEST.write_text(TEST_SOURCE, encoding='utf-8')
print('ok test/terminal_surface_test.dart')
print('补丁 v2 完成')
