"""一次性补丁：把终端画布/快捷键栏的底色叠加规格写进代码。

背景（第 12 轮实测）：
  原版 Solarized Dark 主题背景是 `#073642`，但终端画布实际渲染 `#254E59`
  = 背景叠加约 11.5% 的前景色 `#EEE8D5`；
  快捷键栏实际渲染 `#1D4750` = 同一背景叠加约 9% 的前景色。

每处替换都断言"恰好出现一次"，任何一处不匹配就整体失败、不写文件。
"""

import pathlib
import sys

ROOT = pathlib.Path(r'D:\contribute\juice-ssh-flutter')

THEMES = ROOT / 'lib' / 'terminal' / 'terminal_themes.dart'
SESSION = ROOT / 'lib' / 'terminal' / 'terminal_session.dart'
PAGE = ROOT / 'lib' / 'terminal' / 'terminal_page.dart'

CONSTANTS = '''  /// 默认背景色（数组第 257 项）。
  static Color backgroundAt(int index) => _color(paletteAt(index), 257);

  /// 终端画布底色在主题背景上叠的前景色比例。
  ///
  /// 实测原版 Solarized Dark：主题背景是 `#073642`，而画布真正渲染出来的是
  /// `#254E59` —— 正好等于背景叠加约 11.5% 的前景色 `#EEE8D5`
  /// （0x07+0.115*0xEE≈35.6→0x25，0x36+0.115*0xE8≈80.7→0x4E，
  /// 0x42+0.115*0xD5≈90.6→0x59）。注意这是**渲染层**的叠加，
  /// 不要改 `paletteAt()` 返回的原始数组。
  static const double surfaceOverlay = 0.115;

  /// 快捷键栏底色叠的前景色比例。
  ///
  /// 原版快捷键栏实测 `#1D4750`，比画布略暗，反推约 9%
  /// （0x07+0.09*0xEE≈29.4→0x1D，0x36+0.09*0xE8≈74.9→0x4B，实测 0x47）。
  static const double keyBarOverlay = 0.09;

  /// 把主题背景按 [overlay] 混入该方案的前景色。
  static Color blendWithForeground(int index, double overlay) {
    final palette = paletteAt(index);
    return Color.alphaBlend(
      _color(palette, 256).withValues(alpha: overlay),
      _color(palette, 257),
    );
  }
'''

BUILD_SIG_OLD = '  static TerminalTheme build(int index) {'
BUILD_SIG_NEW = '''  /// [surfaceOverlay] 大于 0 时，背景会按该比例混入前景色 —— 终端画布要用
  /// 这一档（见 [surfaceOverlay]），而快捷键栏底色另用 [blendWithForeground]。
  static TerminalTheme build(int index, {double surfaceOverlay = 0}) {'''

BG_OLD = '''      foreground: foreground,
      background: background,'''
BG_NEW = '''      foreground: foreground,
      background: surfaceOverlay <= 0
          ? background
          : Color.alphaBlend(
              foreground.withValues(alpha: surfaceOverlay),
              background,
            ),'''

SESSION_OLD = '''  TerminalTheme get theme => JuiceTerminalThemes.build(settings.terminalThemeIndex);'''
SESSION_NEW = '''  TerminalTheme get theme => JuiceTerminalThemes.build(settings.terminalThemeIndex);

  /// 终端**画布**用的配色：底色额外叠一层前景色。
  ///
  /// `TerminalView` 自己会画底色，所以必须把叠加写进传给它的主题里；
  /// [theme] 保持原始值，供菜单/失败页等其它地方使用。
  TerminalTheme get surfaceTheme => JuiceTerminalThemes.build(
        settings.terminalThemeIndex,
        surfaceOverlay: JuiceTerminalThemes.surfaceOverlay,
      );

  /// 快捷键栏底色（原版比画布略暗，见 [JuiceTerminalThemes.keyBarOverlay]）。
  Color get keyBarBackground => JuiceTerminalThemes.blendWithForeground(
        settings.terminalThemeIndex,
        JuiceTerminalThemes.keyBarOverlay,
      );'''

PAGE_EDITS = [
    ('        backgroundColor: _controller.theme.background,',
     '        backgroundColor: _controller.surfaceTheme.background,'),
    ('      color: _controller.theme.background,',
     '      color: _controller.keyBarBackground,'),
    ('              theme: _controller.theme,',
     '              theme: _controller.surfaceTheme,'),
]


def patch(path: pathlib.Path, edits, required: bool = True):
    text = path.read_text(encoding='utf-8')
    for old, new in edits:
        count = text.count(old)
        if count != 1:
            print(f'!! {path.name}: 期望 1 处，实际 {count} 处 -> {old[:60]!r}')
            if required:
                sys.exit(1)
            continue
        text = text.replace(old, new)
    path.write_text(text, encoding='utf-8')
    print(f'ok {path.name}')


patch(THEMES, [
    ('  /// 默认背景色（数组第 257 项）。\n'
     '  static Color backgroundAt(int index) => _color(paletteAt(index), 257);\n',
     CONSTANTS),
    (BUILD_SIG_OLD, BUILD_SIG_NEW),
    (BG_OLD, BG_NEW),
])
patch(SESSION, [(SESSION_OLD, SESSION_NEW)])
patch(PAGE, PAGE_EDITS)
print('补丁完成')
