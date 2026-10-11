import 'dart:convert';

import 'package:flutter/services.dart';

/// 反编译出的原始资源表，用于驱动设置页里的列表项。
///
/// 对应原版：
/// * `res/values/arrays.xml` —— 字体列表、终端类型、配色方案名、各种枚举
/// * `res/values/colors.xml` —— 全部颜色（引用已解析成 `#AARRGGBB`）
/// * `res/values/dimens.xml` —— 全部尺寸
/// * `assets/data/apk_manifest.json` —— 版本号等元信息
class AppResources {
  AppResources._({
    required this.arrays,
    required this.colors,
    required this.dimens,
    required this.manifest,
  });

  final Map<String, List<String>> arrays;
  final Map<String, String> colors;
  final Map<String, String> dimens;
  final Map<String, dynamic> manifest;

  static AppResources? _instance;

  /// 在 `main()` 里先 await 一次，之后即可同步访问。
  static AppResources get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('AppResources 尚未加载，请先在 main() 里 await AppResources.load()');
    }
    return value;
  }

  static Future<AppResources> load() async {
    final arrays = await _readStringListMap('assets/data/arrays.json');
    final colors = await _readStringMap('assets/data/colors.json');
    final dimens = await _readStringMap('assets/data/dimens.json');
    final manifest = json.decode(
      await rootBundle.loadString('assets/data/apk_manifest.json'),
    ) as Map<String, dynamic>;
    final resources = AppResources._(
      arrays: arrays,
      colors: colors,
      dimens: dimens,
      manifest: manifest,
    );
    _instance = resources;
    return resources;
  }

  List<String> array(String name) => arrays[name] ?? const <String>[];

  /// 按名字取颜色并解析成 ARGB 整数；缺失时返回 null。
  int? colorValue(String name) {
    final raw = colors[name];
    if (raw == null || raw.isEmpty || !raw.startsWith('#')) return null;
    final hex = raw.substring(1);
    return int.tryParse(hex, radix: 16);
  }

  // --- 常用列表，名字与原版 arrays.xml 保持一致 ---

  /// `font_names` —— 设置页里字体列表的显示顺序
  List<String> get fontNames => array('font_names');

  /// `terminal_theme_names`
  List<String> get terminalThemeNames => array('terminal_theme_names');

  /// `terminal_typeTitles`（linux / xterm / xterm-color / xterm-256color / vt100）
  List<String> get terminalTypeTitles => array('terminal_typeTitles');

  List<String> get terminalTypeValues => array('terminal_typeValues');

  List<String> get bellModeNames => array('terminal_bell_mode_names');

  List<String> get bellModeValues => array('terminal_bell_mode_values');

  List<String> get swipeModeNames => array('terminal_horizontal_swipe_mode_names');

  List<String> get swipeModeValues => array('terminal_horizontal_swipe_mode_values');

  List<String> get keyboardPositionNames => array('terminal_keyboard_position_names');

  List<String> get keyboardPositionValues => array('terminal_keyboard_position_values');

  List<String> get darkThemeNames => array('dark_theme_names');

  List<String> get darkThemeValues => array('dark_theme_values');

  List<String> get altBehaviourNames => array('terminal_alt_behaviour_names');

  List<String> get altBehaviourValues => array('terminal_alt_behaviour_values');

  // --- 版本信息 ---

  String get versionName => '${manifest['versionName'] ?? ''}';

  int get versionCode => (manifest['versionCode'] as num?)?.toInt() ?? 0;

  String get originalPackage => '${manifest['package'] ?? ''}';

  /// 默认终端字体名（原版 `com/sonelli/aj0` 的 `aj0$a.Q`）
  String get defaultFontName => '${manifest['defaultFont'] ?? 'Cascadia Code Mono'}';

  /// 字体显示名 -> 打进包里的 asset 文件名
  Map<String, String> get fontAssets =>
      (manifest['fontAssets'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, '$value'));

  /// 原版 `TerminalEmulatorActivity` 在字号解析失败时的兜底值
  int get defaultFontSize => (manifest['defaultFontSize'] as num?)?.toInt() ?? 8;

  static Future<Map<String, String>> _readStringMap(String path) async {
    final decoded = json.decode(await rootBundle.loadString(path));
    return (decoded as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, '$value'),
    );
  }

  static Future<Map<String, List<String>>> _readStringListMap(String path) async {
    final decoded = json.decode(await rootBundle.loadString(path));
    return (decoded as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        (value as List<dynamic>).map((item) => '$item').toList(),
      ),
    );
  }
}
