import 'dart:convert';

import 'package:flutter/services.dart';

/// @brief 反编译出的原始资源表，用于驱动设置页里的列表项。
///
/// 对应原版：
/// * `res/values/arrays.xml` —— 字体列表、终端类型、配色方案名、各种枚举
/// * `res/values/colors.xml` —— 全部颜色（引用已解析成 `#AARRGGBB`）
/// * `res/values/dimens.xml` —— 全部尺寸
/// * `assets/data/apk_manifest.json` —— 版本号等元信息
class AppResources {
  /// @brief 私有构造，只允许经 [load] 建实例。
  AppResources._({
    required this.arrays,
    required this.colors,
    required this.dimens,
    required this.manifest,
  });

  /// @brief 原始字符串数组（对应 `arrays.xml`）。
  final Map<String, List<String>> arrays;
  /// @brief 颜色名 -> `#AARRGGBB`（对应 `colors.xml`）。
  final Map<String, String> colors;
  /// @brief 尺寸名 -> 原始值（对应 `dimens.xml`）。
  final Map<String, String> dimens;
  /// @brief `apk_manifest.json`：版本号、默认字体等元信息。
  final Map<String, dynamic> manifest;

  /// @brief 进程内单例，由 [load] 赋值。
  static AppResources? _instance;

  /// @brief 在 `main()` 里先 await 一次，之后即可同步访问。
  static AppResources get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('AppResources 尚未加载，请先在 main() 里 await AppResources.load()');
    }
    return value;
  }

  /// @brief 从 assets 读取四份资源表，并缓存为单例。
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

  /// @brief 按名字取字符串数组；缺失时返回空列表。
  List<String> array(String name) => arrays[name] ?? const <String>[];

  /// @brief 按名字取颜色并解析成 ARGB 整数；缺失时返回 null。
  int? colorValue(String name) {
    final raw = colors[name];
    if (raw == null || raw.isEmpty || !raw.startsWith('#')) return null;
    final hex = raw.substring(1);
    return int.tryParse(hex, radix: 16);
  }

  // --- 常用列表，名字与原版 arrays.xml 保持一致 ---

  /// @brief `font_names` —— 设置页里字体列表的显示顺序
  List<String> get fontNames => array('font_names');

  /// @brief `terminal_theme_names` —— 终端配色方案名
  List<String> get terminalThemeNames => array('terminal_theme_names');

  /// @brief `terminal_typeTitles` —— 终端类型显示名
  ///
  /// （linux / xterm / xterm-color / xterm-256color / vt100）
  List<String> get terminalTypeTitles => array('terminal_typeTitles');

  /// @brief `terminal_typeValues` —— 终端类型取值
  List<String> get terminalTypeValues => array('terminal_typeValues');

  /// @brief `terminal_bell_mode_names` —— 响铃方式显示名
  List<String> get bellModeNames => array('terminal_bell_mode_names');

  /// @brief `terminal_bell_mode_values` —— 响铃方式取值
  List<String> get bellModeValues => array('terminal_bell_mode_values');

  /// @brief `terminal_horizontal_swipe_mode_names` —— 水平滑动模式显示名
  List<String> get swipeModeNames => array('terminal_horizontal_swipe_mode_names');

  /// @brief `terminal_horizontal_swipe_mode_values` —— 水平滑动模式取值
  List<String> get swipeModeValues => array('terminal_horizontal_swipe_mode_values');

  /// @brief `terminal_keyboard_position_names` —— 键盘位置显示名
  List<String> get keyboardPositionNames => array('terminal_keyboard_position_names');

  /// @brief `terminal_keyboard_position_values` —— 键盘位置取值
  List<String> get keyboardPositionValues => array('terminal_keyboard_position_values');

  /// @brief `dark_theme_names` —— 主题模式显示名
  List<String> get darkThemeNames => array('dark_theme_names');

  /// @brief `dark_theme_values` —— 主题模式取值
  List<String> get darkThemeValues => array('dark_theme_values');

  /// @brief `terminal_alt_behaviour_names` —— Alt 键行为显示名
  List<String> get altBehaviourNames => array('terminal_alt_behaviour_names');

  /// @brief `terminal_alt_behaviour_values` —— Alt 键行为取值
  List<String> get altBehaviourValues => array('terminal_alt_behaviour_values');

  // --- 版本信息 ---

  /// @brief 原版版本名。
  String get versionName => '${manifest['versionName'] ?? ''}';

  /// @brief 原版 versionCode。
  int get versionCode => (manifest['versionCode'] as num?)?.toInt() ?? 0;

  /// @brief 原版包名（`apk_manifest.json` 的 `package`）。
  String get originalPackage => '${manifest['package'] ?? ''}';

  /// @brief 默认终端字体名（原版 `com/sonelli/aj0` 的 `aj0$a.Q`）
  String get defaultFontName => '${manifest['defaultFont'] ?? 'Cascadia Code Mono'}';

  /// @brief 字体显示名 -> 打进包里的 asset 文件名
  Map<String, String> get fontAssets =>
      (manifest['fontAssets'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, '$value'));

  /// @brief 原版 `TerminalEmulatorActivity` 在字号解析失败时的兜底值
  int get defaultFontSize => (manifest['defaultFontSize'] as num?)?.toInt() ?? 8;

  /// @brief 读取并解析「字符串 -> 字符串」的 JSON 资源表。
  static Future<Map<String, String>> _readStringMap(String path) async {
    final decoded = json.decode(await rootBundle.loadString(path));
    return (decoded as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, '$value'),
    );
  }

  /// @brief 读取并解析「字符串 -> 字符串数组」的 JSON 资源表。
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
