import 'package:flutter/foundation.dart';

import '../data/juice_database.dart';
import 'app_resources.dart';
import 'juice_colors.dart';

/// 应用设置。
///
/// 键名与原版 JuiceSSH 的 `config` 键**完全一致**（依据反编译出的
/// `res/xml/settings.xml` 与 DEX 中的 config 键清单），这样从原版迁移过来的
/// 配置可以直接套用，也方便对着原版逐项核对。
///
/// 默认值的来源分三类，代码里都标注了：
/// * **已确认**：能从反编译代码或资源里读出确切值；
/// * **推断**：由控件范围（如 min/max）或行为反推；
/// * **未确认**：原版默认值在运行时由 Dalvik 代码种下，静态读不到，
///   这里给一个合理值并标注，便于日后用真机对照修正。
class SettingsController extends ChangeNotifier {
  SettingsController._(this._db, this._cache);

  final JuiceDatabase _db;
  final Map<String, String?> _cache;

  static SettingsController? _instance;

  static SettingsController get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('SettingsController 尚未初始化');
    }
    return value;
  }

  static Future<SettingsController> load(JuiceDatabase db) async {
    final cache = await db.allConfig();
    final controller = SettingsController._(db, cache);
    _instance = controller;
    return controller;
  }

  // ------------------------------------------------------------ 键名清单 --

  /// `theme:dark` —— 应用主题（自动/亮/暗）
  static const keyDarkTheme = 'theme:dark';

  /// `terminal:theme` —— 终端配色方案索引 0..8
  static const keyTerminalTheme = 'terminal:theme';

  /// `terminal:font` —— 终端字体显示名
  static const keyTerminalFont = 'terminal:font';

  /// `terminal:font_size` —— 终端字号
  static const keyTerminalFontSize = 'terminal:font_size';

  /// `terminal:margin` —— 终端边距（像素）
  static const keyTerminalMargin = 'terminal:margin';

  /// `terminal:margin_selection` —— 选择文本时的边距
  static const keyTerminalMarginSelection = 'terminal:margin_selection';

  /// `terminal:horizontal_swipe_mode` —— 水平滑动模式 0..4
  static const keyTerminalSwipeMode = 'terminal:horizontal_swipe_mode';

  /// `terminal:utf8`
  static const keyTerminalUtf8 = 'terminal:utf8';

  /// `terminal:type` —— 终端类型
  static const keyTerminalType = 'terminal:type';

  /// `terminal:bell_mode` —— 响铃方式 0..2
  static const keyTerminalBellMode = 'terminal:bell_mode';

  /// `terminal:keyboard_position` —— 弹出键盘位置 0..2
  static const keyTerminalKeyboardPosition = 'terminal:keyboard_position';

  /// `terminal:autocomplete` —— 终端输入自动补全
  static const keyTerminalAutocomplete = 'terminal:autocomplete';

  /// `ssh:agent` —— SSH Agent 转发
  static const keySshAgent = 'ssh:agent';

  /// `pinlock:enabled`
  static const keyPinlockEnabled = 'pinlock:enabled';

  /// `pinlock:pin`
  static const keyPinlockPin = 'pinlock:pin';

  /// `pinlock:timeout` —— 空闲多少秒后自动锁定
  static const keyPinlockTimeout = 'pinlock:timeout';

  /// `pinlock:attempts` —— 连续失败次数
  static const keyPinlockAttempts = 'pinlock:attempts';

  /// `mosh:mosh-server` —— 远端 mosh-server 路径
  static const keyMoshServerCommand = 'mosh:mosh-server';

  /// `notifications:enabled`
  static const keyNotificationsEnabled = 'notifications:enabled';

  /// `session:timeout` —— 后台保持会话的时长
  static const keySessionTimeout = 'session:timeout';

  /// `tutorial:terminal` —— 是否已看过终端引导
  static const keyTutorialTerminal = 'tutorial:terminal';

  // -------------------------------------------------------------- 读取器 --

  String? raw(String key) => _cache[key];

  Future<void> set(String key, String? value) async {
    if (value == null) {
      _cache.remove(key);
      await _db.removeConfig(key);
    } else {
      _cache[key] = value;
      await _db.setConfig(key, value);
    }
    notifyListeners();
  }

  bool boolOf(String key, {required bool fallback}) {
    final value = _cache[key];
    if (value == null) return fallback;
    // 原版写的是字符串 `true`/`false`（`Config.h(key, "true"|"false", ctx)`，
    // 见 `TerminalEmulatorActivity$k.onClick` 写 `tutorial:terminal`）；早期版本
    // 这里写的是 `'1'`/`'0'`，两种取值都继续认，避免设备上已有配置失效。
    return value == '1' || value.toLowerCase() == 'true';
  }

  /// 布尔值按原版落库：字符串 `true` / `false`。
  Future<void> setBool(String key, bool value) =>
      set(key, value ? 'true' : 'false');

  int intOf(String key, {required int fallback}) {
    final value = _cache[key];
    if (value == null) return fallback;
    return int.tryParse(value) ?? fallback;
  }

  Future<void> setInt(String key, int value) => set(key, '$value');

  // ---------------------------------------------------------- 应用主题 --

  /// `theme:dark`。默认「自动」。
  AppThemeMode get themeMode => AppThemeMode.fromValue(_cache[keyDarkTheme]);

  Future<void> setThemeMode(AppThemeMode mode) => setInt(keyDarkTheme, mode.value);

  // -------------------------------------------------------- 终端外观 --

  /// `terminal:theme` —— 默认 **2**（Solarized Dark）。
  ///
  /// 依据：`TerminalEmulatorActivity` 读取 `terminal:theme` 时对缺失值取 "2"，
  /// 再交给 `com.sonelli.ni0.a(int)` 映射到 `ni0` 里的第 6 个数组。
  int get terminalThemeIndex {
    final count = AppResources.instance.terminalThemeNames.length;
    final index = intOf(keyTerminalTheme, fallback: 2);
    if (index < 0 || index >= count) return 2;
    return index;
  }

  Future<void> setTerminalThemeIndex(int index) => setInt(keyTerminalTheme, index);

  /// `terminal:font` —— 默认 Cascadia Code Mono。
  ///
  /// 依据：`com/sonelli/aj0.smali` 的 `aj0.a` 静态字段指向枚举 `aj0$a.Q`，
  /// 也就是列表里的第一项。
  String get terminalFont =>
      _cache[keyTerminalFont] ?? AppResources.instance.defaultFontName;

  Future<void> setTerminalFont(String name) => set(keyTerminalFont, name);

  /// `terminal:font_size` —— 默认 8。
  ///
  /// 依据：`TerminalEmulatorActivity` 的 `NumberFormatException` 兜底值 `0x8`。
  int get terminalFontSize =>
      intOf(keyTerminalFontSize, fallback: AppResources.instance.defaultFontSize);

  Future<void> setTerminalFontSize(int size) => setInt(keyTerminalFontSize, size);

  /// `terminal:margin` —— 单位像素，设置页范围 0..128。
  int get terminalMargin => intOf(keyTerminalMargin, fallback: 0);

  Future<void> setTerminalMargin(int value) => setInt(keyTerminalMargin, value);

  /// `terminal:margin_selection` —— 选择文本时额外放宽的边距，便于选到边缘字符。
  int get terminalMarginSelection => intOf(keyTerminalMarginSelection, fallback: 0);

  Future<void> setTerminalMarginSelection(int value) =>
      setInt(keyTerminalMarginSelection, value);

  /// `terminal:horizontal_swipe_mode` —— 0..4，对应
  /// Irssi / WeeChat / tmux / screen / Disabled。
  int get terminalSwipeMode => intOf(keyTerminalSwipeMode, fallback: 0);

  Future<void> setTerminalSwipeMode(int value) => setInt(keyTerminalSwipeMode, value);

  /// `terminal:utf8` —— 默认开启。原版以 UTF-8 为默认行为，UTF-8 支持是主要卖点之一。
  bool get terminalUtf8 => boolOf(keyTerminalUtf8, fallback: true);

  Future<void> setTerminalUtf8(bool value) => setBool(keyTerminalUtf8, value);

  /// `terminal:type` —— 默认 `linux`。
  ///
  /// 依据：`TerminalEmulatorActivity` 对缺失值取 "linux"，
  /// 这也是 `com.sonelli.ti0`（EscapeCharacters）里的第一个分支。
  /// 注意包内 `terminfo.zip` 还带有 `ansi` 和 `screen` 两种类型，
  /// 但设置页的 `terminal_typeTitles` 只列了 5 项，与这里的 5 个分支一致。
  String get terminalType => _cache[keyTerminalType] ?? 'linux';

  Future<void> setTerminalType(String value) => set(keyTerminalType, value);

  /// `terminal:bell_mode` —— 0 关闭 / 1 震动 / 2 通知。默认关闭。
  int get terminalBellMode => intOf(keyTerminalBellMode, fallback: 0);

  Future<void> setTerminalBellMode(int value) => setInt(keyTerminalBellMode, value);

  /// `terminal:keyboard_position` —— 0 终端上方 / 1 终端下方 / 2 关闭。
  ///
  /// 依据：原版对缺失值取 "1"，即**默认把额外键行放在终端下方**。
  int get terminalKeyboardPosition =>
      intOf(keyTerminalKeyboardPosition, fallback: 1);

  Future<void> setTerminalKeyboardPosition(int value) =>
      setInt(keyTerminalKeyboardPosition, value);

  /// `terminal:autocomplete` —— **原版从不读取这个键**。
  ///
  /// 反编译结果显示 `setAutocomplete(false)` 是硬编码的，这个设置项
  /// 在 `res/xml/settings.xml` 里也没有入口，属于「留了键但没接线」。
  /// 这里保留读写能力以便与原有配置互通，但界面不会用到，终端也始终关闭。
  bool get terminalAutocomplete => boolOf(keyTerminalAutocomplete, fallback: false);

  Future<void> setTerminalAutocomplete(bool value) =>
      setBool(keyTerminalAutocomplete, value);

  // ------------------------------------------------------------ 安全 --

  /// `ssh:agent` —— 默认关闭。
  bool get sshAgentForwarding => boolOf(keySshAgent, fallback: false);

  Future<void> setSshAgentForwarding(bool value) => setBool(keySshAgent, value);

  /// `pinlock:enabled`
  bool get pinLockEnabled => boolOf(keyPinlockEnabled, fallback: false);

  Future<void> setPinLockEnabled(bool value) => setBool(keyPinlockEnabled, value);

  /// `pinlock:timeout` —— 空闲秒数，超过后重新锁定。默认 5 分钟。
  int get pinLockTimeoutSeconds => intOf(keyPinlockTimeout, fallback: 300);

  Future<void> setPinLockTimeoutSeconds(int value) => setInt(keyPinlockTimeout, value);

  /// `pinlock:attempts` —— 已连续失败的次数。
  int get pinLockFailedAttempts => intOf(keyPinlockAttempts, fallback: 0);

  Future<void> setPinLockFailedAttempts(int value) => setInt(keyPinlockAttempts, value);

  /// 与 PIN 一起存储。真实存放位置由 `PinLockService` 决定，这里只暴露键名。
  String? get pinLockPinHash => _cache[keyPinlockPin];

  Future<void> setPinLockPinHash(String? value) => set(keyPinlockPin, value);

  // ------------------------------------------------------------ 其他 --

  /// `mosh:mosh-server` —— 远端命令路径。
  String get moshServerCommand => _cache[keyMoshServerCommand] ?? 'mosh-server';

  Future<void> setMoshServerCommand(String value) => set(keyMoshServerCommand, value);

  /// `notifications:enabled`
  bool get notificationsEnabled => boolOf(keyNotificationsEnabled, fallback: true);

  Future<void> setNotificationsEnabled(bool value) =>
      setBool(keyNotificationsEnabled, value);

  /// `session:timeout` —— 会话保活秒数。默认 0（不自动断开）。
  int get sessionTimeoutSeconds => intOf(keySessionTimeout, fallback: 0);

  Future<void> setSessionTimeoutSeconds(int value) => setInt(keySessionTimeout, value);

  /// `tutorial:terminal` —— 是否已展示过终端引导。
  bool get terminalTutorialSeen => boolOf(keyTutorialTerminal, fallback: false);

  Future<void> setTerminalTutorialSeen(bool value) =>
      setBool(keyTutorialTerminal, value);
}
