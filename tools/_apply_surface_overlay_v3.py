"""补丁 v3：快捷键栏底色改用「叠前景色 9.5%」。

实测（模拟器，Solarized Dark）：
  画布   = `#073642` 叠白 12%        -> `#254E59`（三通道精确）
  快捷键栏 = `#073642` 叠前景色 `#EEE8D5` 9.5% -> `#1D4750`（三通道精确）
             R: 0.095*238+0.905*7  = 28.9 -> 0x1D
             G: 0.095*232+0.905*54 = 70.9 -> 0x47
             B: 0.095*213+0.905*66 = 80.0 -> 0x50

v2 里把两者都当成叠白，画布对了、快捷键栏蓝通道差 3（`#1D4853`）。
"""

import pathlib
import sys

ROOT = pathlib.Path(r'D:\contribute\juice-ssh-flutter')
THEMES = ROOT / 'lib' / 'terminal' / 'terminal_themes.dart'
SESSION = ROOT / 'lib' / 'terminal' / 'terminal_session.dart'
TEST = ROOT / 'test' / 'terminal_surface_test.dart'

EDITS = [
    ('''  /// 快捷键栏底色叠的**白色**比例。
  ///
  /// 原版快捷键栏实测 `#1D4750`，比画布略暗：7+0.09*248≈29.3→0x1D、
  /// 54+0.09*201≈72.1→0x48（实测 0x47）、66+0.09*189≈83.0→0x53
  /// （实测 0x50）。三个通道略有出入，取 0.09 作为最接近的整档。
  static const double keyBarOverlay = 0.09;''',
     '''  /// 快捷键栏底色叠的**前景色**比例（注意：与画布叠的不是同一种颜色）。
  ///
  /// 原版快捷键栏实测 `#1D4750`，按叠白反推三个通道对不上
  /// （0.089 / 0.085 / 0.074）；按叠该方案的前景色 `#EEE8D5` 反推则三通道一致：
  ///
  ///     R: 0.095*238 + 0.905*7  = 28.9 -> 0x1D
  ///     G: 0.095*232 + 0.905*54 = 70.9 -> 0x47
  ///     B: 0.095*213 + 0.905*66 = 80.0 -> 0x50
  static const double keyBarOverlay = 0.095;'''),

    ('''  /// 把主题背景按 [overlay] 混入白色，得到实际渲染色。
  static Color blendWithWhite(int index, double overlay) {''',
     '''  /// 把主题背景按 [overlay] 混入该方案的**前景色**（快捷键栏用这一档）。
  static Color blendWithForeground(int index, double overlay) {
    final palette = paletteAt(index);
    return Color.alphaBlend(
      _color(palette, 256).withValues(alpha: overlay),
      _color(palette, 257),
    );
  }

  /// 把主题背景按 [overlay] 混入白色（终端画布用这一档）。
  static Color blendWithWhite(int index, double overlay) {'''),
]

SESSION_EDITS = [
    ('  Color get keyBarBackground => JuiceTerminalThemes.blendWithWhite(',
     '  Color get keyBarBackground => JuiceTerminalThemes.blendWithForeground('),
]

TEST_EDITS = [
    ('''  test('快捷键栏底色 = 主题背景叠白 9%', () {
    expect(
      JuiceTerminalThemes.blendWithWhite(2, JuiceTerminalThemes.keyBarOverlay)
          .toARGB32(),
      0xFF1D4853,
    );
  });''',
     '''  test('快捷键栏底色 = 主题背景叠前景色 9.5%（原版实测 #1D4750）', () {
    expect(
      JuiceTerminalThemes.blendWithForeground(
        2,
        JuiceTerminalThemes.keyBarOverlay,
      ).toARGB32(),
      0xFF1D4750,
    );
  });'''),
]


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
patch(TEST, TEST_EDITS)
print('补丁 v3 完成')
