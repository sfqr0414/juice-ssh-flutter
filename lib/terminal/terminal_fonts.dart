/// @brief 终端字体映射。
///
/// 原版内置 8 款 Nerd Font Complete，设置项 `terminal:font` 存的是**显示名**。
/// 这些字体文件已经由 `tools/extract_from_apk.py` 从 APK 里原样取出，
/// 并在 `pubspec.yaml` 里按下面的 family 名注册，所以在 Flutter 里能 1:1
/// 复现原版的字形（包括 Nerd Font 的图标区）。
///
/// 字体族名与原版 `assets/fonts/` 下文件名的对应关系取自
/// `com/sonelli/aj0$a.smali`。
class TerminalFonts {
  /// @brief 私有构造：本类只是映射表。
  const TerminalFonts._();

  /// @brief 显示名 → Flutter 里注册的字体族名。
  ///
  /// 键名与 `arrays.xml` 的 `font_names` 完全一致，同时也是
  /// `terminal:font` 的取值，因此不需要额外的转换表。
  static const Map<String, String> familyByDisplayName = <String, String>{
    'Cascadia Code Mono': 'JuiceTerminalCascadiaCode',
    'Sauce Code Pro': 'JuiceTerminalSauceCodePro',
    'Inconsolata': 'JuiceTerminalInconsolata',
    'Roboto Mono': 'JuiceTerminalRobotoMono',
    'JetBrains Mono': 'JuiceTerminalJetBrainsMono',
    'Fira Code': 'JuiceTerminalFiraCode',
    'Open Dyslexic': 'JuiceTerminalOpenDyslexic',
    'Droid Sans Mono': 'JuiceTerminalDroidSansMono',
  };

  /// @brief 原版 `arrays.xml` 里 `font_names` 的显示顺序。
  ///
  /// 注意这个顺序**不是**按字母排的，而是原版界面上的展示顺序，
  /// 所以设置页必须照这个顺序列出来。
  static const List<String> displayOrder = <String>[
    'Cascadia Code Mono',
    'Sauce Code Pro',
    'Roboto Mono',
    'JetBrains Mono',
    'Fira Code',
    'Open Dyslexic',
    'Inconsolata',
    'Droid Sans Mono',
  ];

  /// @brief 原版默认字体：`aj0$a.Q`，即列表第一项 Cascadia Code Mono。
  static const String defaultDisplayName = 'Cascadia Code Mono';

  /// @brief 取字体族名；未知名称回退到默认字体。
  static String familyOf(String displayName) =>
      familyByDisplayName[displayName] ??
      familyByDisplayName[defaultDisplayName]!;

  /// @brief 回退链：字体本身缺失某个字形（例如中文）时依次尝试这些族。
  ///
  /// 原版依赖 Android 的字体回退（Droid Sans / Noto），这里显式列出，
  /// 免得中文或 emoji 显示成方框。
  static const List<String> fallback = <String>[
    'Droid Sans Mono',
    'monospace',
    'Noto Sans Mono CJK SC',
    'Noto Color Emoji',
  ];
}
