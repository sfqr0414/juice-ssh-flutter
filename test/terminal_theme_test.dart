import 'package:flutter_test/flutter_test.dart';
import 'package:juice_ssh_flutter/terminal/terminal_themes.dart';

/// 终端配色查表的回归测试。
///
/// 背景：模拟器上实测复刻连上样本 SSH 服务端后，整屏底色是 `#870000`
/// （xterm 调色板的索引 1 = ANSI 红），而 Solarized Dark 的背景槽应该是
/// `#073642`。这里把「设置值 → 调色板槽位 → Color」这条链路直接钉住，
/// 以便区分是**查表错了**还是**渲染用错了**。
void main() {
  test('kPaletteLength 与原始 260 项数组一致', () {
    // 每个方案都必须是 260 项：0..255 是 256 色表，
    // 256 = 默认前景，257 = 默认背景，258/259 = 光标前景/背景。
    for (var i = 0; i < JuiceTerminalThemes.count; i++) {
      expect(JuiceTerminalThemes.paletteAt(i).length, 260, reason: '方案 $i');
    }
  });

  test('Solarized Dark 的前景/背景取的是 256/257 槽', () {
    const solarizedDark = 2;
    expect(
      JuiceTerminalThemes.foregroundAt(solarizedDark).toARGB32(),
      0xFFEEE8D5,
    );
    expect(
      JuiceTerminalThemes.backgroundAt(solarizedDark).toARGB32(),
      0xFF073642,
    );
  });

  test('build() 把槽位映射到 xterm 的 TerminalTheme', () {
    final palette = JuiceTerminalThemes.paletteAt(2);
    final theme = JuiceTerminalThemes.build(2);
    expect(theme.background.toARGB32(), 0xFF073642);
    expect(theme.foreground.toARGB32(), 0xFFEEE8D5);
    expect(theme.black.toARGB32(), palette[0]);
    expect(theme.red.toARGB32(), palette[1]);
    expect(theme.brightWhite.toARGB32(), palette[15]);
    // 模拟器上实测到的那片 `#870000` 是 256 色立方体里的条目（索引 0x58），
    // **不是**任何方案的 256/257 槽 —— 九个方案的背景槽分别是
    // #000000 / #FFFFFF / #073642 / #EEE8D5 / #000000 / #272822 /
    // #D44E00 / #000000 / #000000，没有一个是它。
    for (var i = 0; i < JuiceTerminalThemes.count; i++) {
      expect(
        JuiceTerminalThemes.backgroundAt(i).toARGB32(),
        isNot(0xFF870000),
        reason: '方案 $i',
      );
    }
  });
}
