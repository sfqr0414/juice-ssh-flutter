import 'package:flutter_test/flutter_test.dart';
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

  test('快捷键栏底色 = 主题背景叠前景色 9.5%（原版实测 #1D4750）', () {
    expect(
      JuiceTerminalThemes.blendWithForeground(
        2,
        JuiceTerminalThemes.keyBarOverlay,
      ).toARGB32(),
      0xFF1D4750,
    );
  });
}
