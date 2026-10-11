import 'package:flutter_test/flutter_test.dart';
import 'package:juice_ssh_flutter/data/generated/terminal_palettes.g.dart';
import 'package:juice_ssh_flutter/terminal/escape_characters.dart';
import 'package:juice_ssh_flutter/terminal/terminal_themes.dart';

/// 这组测试用来「钉住」从原版 APK 逆出来的常量。
///
/// 这些数值全部来自 `com.sonelli.ni0`（`Colors.java`）与
/// `com.sonelli.ti0`（`EscapeCharacters.java`）的 smali，
/// 一旦将来有人改动生成脚本或手写了资源，这里会立刻报错。
void main() {
  group('终端调色板', () {
    test('共 9 套配色，每套恰好 260 个 ARGB 值', () {
      expect(kTerminalPalettes, hasLength(9));
      expect(kTerminalThemeNames, hasLength(9));
      for (final palette in kTerminalPalettes) {
        // 原版 ni0.smali 里每个数组都是 const/16 0x104 = 260。
        expect(palette, hasLength(kPaletteLength));
        expect(kPaletteLength, 260);
      }
    });

    test('配色名称与顺序与原版 arrays.xml 一致', () {
      expect(kTerminalThemeNames, <String>[
        'Dark',
        'Light',
        'Solarized Dark',
        'Solarized Light',
        "80's Hacker",
        'Monokai',
        'Tiger Orange',
        'Tiger Black',
        'Bifrost',
      ]);
      expect(JuiceTerminalThemes.names, kTerminalThemeNames);
      expect(JuiceTerminalThemes.count, 9);
    });

    test('每套配色的前景/背景落在下标 256/257', () {
      // 期望值逐套取自 smali 里的常量（见 docs/terminal-behaviour-spec.md §9.5）。
      const expected = <int, (int foreground, int background)>{
        0: (0xFFCCCCCC, 0xFF000000), // Dark
        1: (0xFF000000, 0xFFFFFFFF), // Light
        2: (0xFFEEE8D5, 0xFF073642), // Solarized Dark
        3: (0xFF002B36, 0xFFEEE8D5), // Solarized Light
        4: (0xFF33FF66, 0xFF000000), // 80's Hacker
        5: (0xFFFFFFFF, 0xFF272822), // Monokai
        6: (0xFF000000, 0xFFD44E00), // Tiger Orange
        7: (0xFFEF2D0B, 0xFF000000), // Tiger Black
        8: (0xFFFFFFFF, 0xFF000000), // Bifrost
      };

      expected.forEach((index, pair) {
        expect(
          kTerminalPalettes[index][256],
          pair.$1,
          reason: '第 $index 套配色的前景色（下标 256）不对',
        );
        expect(
          kTerminalPalettes[index][257],
          pair.$2,
          reason: '第 $index 套配色的背景色（下标 257）不对',
        );
      });
    });

    test('Dark 配色的前 16 个 ANSI 颜色准确', () {
      const ansi16 = <int>[
        0xFF000000, 0xFFCD0000, 0xFF00CD00, 0xFFCDCD00,
        0xFF0000EE, 0xFFCD00CD, 0xFF00CDCD, 0xFFE5E5E5,
        0xFF7F7F7F, 0xFFFF0000, 0xFF00FF00, 0xFFFFFF00,
        0xFF5C5CFF, 0xFFFF00FF, 0xFF00FFFF, 0xFFFFFFFF,
      ];
      expect(kTerminalPalettes[0].sublist(0, 16), ansi16);
    });

    test('下标 16..255 在九套配色里完全相同（都是标准 xterm 256 色）', () {
      // 这是原版的一个结构性事实：只有 0..15 与 256..259 因配色而异。
      final reference = kTerminalPalettes[0].sublist(16, 256);
      for (var i = 1; i < kTerminalPalettes.length; i++) {
        expect(
          kTerminalPalettes[i].sublist(16, 256),
          reference,
          reason: '第 $i 套配色的 16..255 段与 Dark 不一致',
        );
      }
    });

    test('foregroundAt / backgroundAt 与数组下标对得上', () {
      for (var i = 0; i < JuiceTerminalThemes.count; i++) {
        expect(JuiceTerminalThemes.foregroundAt(i).toARGB32(),
            kTerminalPalettes[i][256]);
        expect(JuiceTerminalThemes.backgroundAt(i).toARGB32(),
            kTerminalPalettes[i][257]);
      }
    });

    test('swatches 取前 8 个 ANSI 颜色', () {
      final swatches = JuiceTerminalThemes.swatches(0);
      expect(swatches, hasLength(8));
      for (var i = 0; i < 8; i++) {
        expect(swatches[i].toARGB32(), kTerminalPalettes[0][i]);
      }
    });
  });

  group('功能键转义序列', () {
    /// 期望表逐项取自 `ti0`（EscapeCharacters.java），下标 0 为 F1。
    const xterm = <String>[
      '\u001bOP', '\u001bOQ', '\u001bOR', '\u001bOS',
      '\u001b[15~', '\u001b[17~', '\u001b[18~', '\u001b[19~',
      '\u001b[20~', '\u001b[21~', '\u001b[23~', '\u001b[24~',
    ];
    const linux = <String>[
      '\u001b[[A', '\u001b[[B', '\u001b[[C', '\u001b[[D',
      '\u001b[[E', '\u001b[17~', '\u001b[18~', '\u001b[19~',
      '\u001b[20~', '\u001b[21~', '\u001b[23~', '\u001b[24~',
    ];
    const xtermColor = <String>[
      '\u001b[11~', '\u001b[12~', '\u001b[13~', '\u001b[14~',
      '\u001b[15~', '\u001b[17~', '\u001b[18~', '\u001b[19~',
      '\u001b[20~', '\u001b[21~', '\u001b[23~', '\u001b[24~',
    ];
    // vt100 没有 F11/F12，原版就是两个空串。
    const vt100 = <String>[
      '\u001bOP', '\u001bOQ', '\u001bOR', '\u001bOS',
      '\u001bOt', '\u001bOu', '\u001bOv', '\u001bOl',
      '\u001bOw', '\u001bOx', '', '',
    ];

    test('五种终端类型各 12 个功能键', () {
      for (final type in const [
        'linux',
        'xterm',
        'xterm-color',
        'xterm-256color',
        'vt100',
      ]) {
        expect(EscapeCharacters(type).functionKeys, hasLength(12),
            reason: '$type 的功能键个数不对');
      }
    });

    test('linux / xterm / xterm-color / vt100 的序列准确', () {
      expect(EscapeCharacters('linux').functionKeys, linux);
      expect(EscapeCharacters('xterm').functionKeys, xterm);
      // 原版把 xterm 与 xterm-256color 归为同一个分支。
      expect(EscapeCharacters('xterm-256color').functionKeys, xterm);
      expect(EscapeCharacters('xterm-color').functionKeys, xtermColor);
      expect(EscapeCharacters('vt100').functionKeys, vt100);
    });

    test('未知终端类型回退到 linux', () {
      expect(EscapeCharacters('unknown-term').functionKeys, linux);
    });

    test('functionKey(n) 与 functionKeys 一致，且 F1 编号为 1', () {
      final x = EscapeCharacters('xterm');
      for (var n = 1; n <= 12; n++) {
        expect(x.functionKey(n), x.functionKeys[n - 1]);
      }
      expect(x.functionKey(1), '\u001bOP');
    });
  });

  group('按键标签常量', () {
    test('KeyTag 的负值编码与原版 packed-switch 分支一致', () {
      expect(KeyTag.pipe, -1);
      expect(KeyTag.ctrl, -2);
      expect(KeyTag.fn, -3);
      expect(KeyTag.alt, -4);
      expect(KeyTag.toggleKeyboard, -5);
      expect(KeyTag.backToMain, -7);
      // F1..F12 对应 -11..-22。
      expect(KeyTag.firstFunctionKey, -11);
      expect(KeyTag.lastFunctionKey, -22);
      expect(KeyTag.functionKey(1), -11);
      expect(KeyTag.functionKey(12), -22);
      for (var n = 1; n <= 12; n++) {
        expect(KeyTag.isFunctionKey(KeyTag.functionKey(n)), isTrue);
        expect(KeyTag.functionKeyNumber(KeyTag.functionKey(n)), n);
      }
      expect(KeyTag.isFunctionKey(KeyTag.ctrl), isFalse);
    });

    test('Android KeyEvent 键值与原版 android:tag 一致', () {
      expect(KeyTag.dpadUp, 19);
      expect(KeyTag.dpadDown, 20);
      expect(KeyTag.dpadLeft, 21);
      expect(KeyTag.dpadRight, 22);
      expect(KeyTag.tab, 61);
      expect(KeyTag.minus, 69);
      expect(KeyTag.slash, 76);
      expect(KeyTag.pageUp, 92);
      expect(KeyTag.pageDown, 93);
      expect(KeyTag.escape, 111);
      expect(KeyTag.moveHome, 122);
      expect(KeyTag.moveEnd, 123);
    });
  });
}
