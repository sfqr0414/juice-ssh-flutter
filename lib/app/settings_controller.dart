import 'package:flutter/foundation.dart';

import '../data/juice_database.dart';
import 'app_resources.dart';
import 'juice_colors.dart';

/// @brief 应用设置。
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
  /// @brief 私有构造：只允许经 [load] 建实例。
  SettingsController._(this._db, this._cache);

  /// @brief 落库用的数据库连接。
  final JuiceDatabase _db;
  /// @brief `config` 表的内存缓存：读走它，写同步落库。
  final Map<String, String?> _cache;

  /// @brief 进程内单例，由 [load] 赋值。
  static SettingsController? _instance;

  /// @brief 取已初始化的单例；未初始化时抛错。
  static SettingsController get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('SettingsController 尚未初始化');
    }
    return value;
  }

  /// @brief 读入整张 `config` 表并建立单例。
  static Future<SettingsController> load(JuiceDatabase db) async {
    final cache = await db.allConfig();
    final controller = SettingsController._(db, cache);
    _instance = controller;
    return controller;
  }

  // ------------------------------------------------------------ 键名清单 --

  /// @brief `theme:dark` —— 应用主题（自动/亮/暗）
  static const keyDarkTheme = 'theme:dark';

  /// @brief `terminal:theme` —— 终端配色方案索引 0..8
  static const keyTerminalTheme = 'terminal:theme';

  /// @brief `terminal:font` —— 终端字体显示名
  static const keyTerminalFont = 'terminal:font';

  /// @brief `terminal:font_size` —— 终端字号
  static const keyTerminalFontSize = 'terminal:font_size';

  /// @brief `terminal:margin` —— 终端边距（像素）
  static const keyTerminalMargin = 'terminal:margin';

  /// @brief `terminal:margin_selection` —— 选择文本时的边距
  static const keyTerminalMarginSelection = 'terminal:margin_selection';

  /// @brief `terminal:horizontal_swipe_mode` —— 水平滑动模式 0..4
  static const keyTerminalSwipeMode = 'terminal:horizontal_swipe_mode';

  /// @brief `terminal:utf8`
  static const keyTerminalUtf8 = 'terminal:utf8';

  /// @brief `terminal:type` —— 终端类型
  static const keyTerminalType = 'terminal:type';

  /// @brief `terminal:bell_mode` —— 响铃方式 0..2
  static const keyTerminalBellMode = 'terminal:bell_mode';

  /// @brief `terminal:keyboard_position` —— 弹出键盘位置 0..2
  static const keyTerminalKeyboardPosition = 'terminal:keyboard_position';

  /// @brief `terminal:autocomplete` —— 终端输入自动补全
  static const keyTerminalAutocomplete = 'terminal:autocomplete';

  /// @brief `ssh:agent` —— SSH Agent 转发
  static const keySshAgent = 'ssh:agent';

  /// @brief `pinlock:enabled`
  static const keyPinlockEnabled = 'pinlock:enabled';

  /// @brief `pinlock:pin`
  static const keyPinlockPin = 'pinlock:pin';

  /// @brief `pinlock:timeout` —— 空闲多少秒后自动锁定
  static const keyPinlockTimeout = 'pinlock:timeout';

  /// @brief `pinlock:attempts` —— 连续失败次数
  static const keyPinlockAttempts = 'pinlock:attempts';

  /// @brief `mosh:mosh-server` —— 远端 mosh-server 路径
  static const keyMoshServerCommand = 'mosh:mosh-server';

  /// @brief `notifications:enabled`
  static const keyNotificationsEnabled = 'notifications:enabled';

  /// @brief `session:timeout` —— 后台保持会话的时长
  static const keySessionTimeout = 'session:timeout';

  /// @brief `tutorial:terminal` —— 是否已看过终端引导
  static const keyTutorialTerminal = 'tutorial:terminal';

  // -------------------------------------------------------------- 读取器 --

  /// @brief 读原始字符串值；缺失时返回 null。
  String? raw(String key) => _cache[key];

  /// @brief 写一个键：null 表示删除，写完通知监听者。
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

  /// @brief 读布尔值，兼容 `true` 与 `1` 两种写法。
  bool boolOf(String key, {required bool fallback}) {
    final value = _cache[key];
    if (value == null) return fallback;
    // 原版写的是字符串 `true`/`false`（`Config.h(key, "true"|"false", ctx)`，
    // 见 `TerminalEmulatorActivity$k.onClick` 写 `tutorial:terminal`）；早期版本
    // 这里写的是 `'1'`/`'0'`，两种取值都继续认，避免设备上已有配置失效。
    return value == '1' || value.toLowerCase() == 'true';
  }

  /// @brief 布尔值按原版落库：字符串 `true` / `false`。
  Future<void> setBool(String key, bool value) =>
      set(key, value ? 'true' : 'false');

  /// @brief 读整数值；缺失或非法时用 fallback。
  int intOf(String key, {required int fallback}) {
    final value = _cache[key];
    if (value == null) return fallback;
    return int.tryParse(value) ?? fallback;
  }

  /// @brief 写整数值。
  Future<void> setInt(String key, int value) => set(key, '$value');

  // ---------------------------------------------------------- 应用主题 --

  /// @brief `theme:dark`。
  ///
  /// 默认「自动」。
  AppThemeMode get themeMode => AppThemeMode.fromValue(_cache[keyDarkTheme]);

  /// @brief 写主题模式。
  Future<void> setThemeMode(AppThemeMode mode) => setInt(keyDarkTheme, mode.value);

  // -------------------------------------------------------- 终端外观 --

  /// @brief `terminal:theme` —— 默认 **2**（Solarized Dark）。
  ///
  /// 依据：`TerminalEmulatorActivity` 读取 `terminal:theme` 时对缺失值取 "2"，
  /// 再交给 `com.sonelli.ni0.a(int)` 映射到 `ni0` 里的第 6 个数组。
  int get terminalThemeIndex {
    final count = AppResources.instance.terminalThemeNames.length;
    final index = intOf(keyTerminalTheme, fallback: 2);
    if (index < 0 || index >= count) return 2;
    return index;
  }

  /// @brief 写终端配色方案索引。
  Future<void> setTerminalThemeIndex(int index) => setInt(keyTerminalTheme, index);

  /// @brief `terminal:font` —— 默认 Cascadia Code Mono。
  ///
  /// 依据：`com/sonelli/aj0.smali` 的 `aj0.a` 静态字段指向枚举 `aj0$a.Q`，
  /// 也就是列表里的第一项。
  String get terminalFont =>
      _cache[keyTerminalFont] ?? AppResources.instance.defaultFontName;

  /// @brief 写终端字体显示名。
  Future<void> setTerminalFont(String name) => set(keyTerminalFont, name);

  /// @brief `terminal:font_size` —— 默认 8。
  ///
  /// 依据：`TerminalEmulatorActivity` 的 `NumberFormatException` 兜底值 `0x8`。
  int get terminalFontSize =>
      intOf(keyTerminalFontSize, fallback: AppResources.instance.defaultFontSize);

  /// @brief 写终端字号。
  Future<void> setTerminalFontSize(int size) => setInt(keyTerminalFontSize, size);

  /// @brief `terminal:margin` —— 单位像素，设置页范围 0..128。
  int get terminalMargin => intOf(keyTerminalMargin, fallback: 0);

  /// @brief 写终端边距。
  Future<void> setTerminalMargin(int value) => setInt(keyTerminalMargin, value);

  /// @brief `terminal:margin_selection` —— 选择文本时额外放宽的边距，
  /// 便于选到边缘字符。
  int get terminalMarginSelection => intOf(keyTerminalMarginSelection, fallback: 0);

  /// @brief 写选择文本时的边距。
  Future<void> setTerminalMarginSelection(int value) =>
      setInt(keyTerminalMarginSelection, value);

  /// @brief `terminal:horizontal_swipe_mode` —— 0..4，对应
  /// Irssi / WeeChat / tmux / screen / Disabled。
  int get terminalSwipeMode => intOf(keyTerminalSwipeMode, fallback: 0);

  /// @brief 写水平滑动模式。
  Future<void> setTerminalSwipeMode(int value) => setInt(keyTerminalSwipeMode, value);

  /// @brief `terminal:utf8` —— 默认开启。
  ///
  /// 原版以 UTF-8 为默认行为，UTF-8 支持是主要卖点之一。
  bool get terminalUtf8 => boolOf(keyTerminalUtf8, fallback: true);

  /// @brief 写 UTF-8 开关。
  Future<void> setTerminalUtf8(bool value) => setBool(keyTerminalUtf8, value);

  /// @brief `terminal:type` —— 默认 `linux`。
  ///
  /// 依据：`TerminalEmulatorActivity` 对缺失值取 "linux"，
  /// 这也是 `com.sonelli.ti0`（EscapeCharacters）里的第一个分支。
  /// 注意包内 `terminfo.zip` 还带有 `ansi` 和 `screen` 两种类型，
  /// 但设置页的 `terminal_typeTitles` 只列了 5 项，与这里的 5 个分支一致。
  String get terminalType => _cache[keyTerminalType] ?? 'linux';

  /// @brief 写终端类型。
  Future<void> setTerminalType(String value) => set(keyTerminalType, value);

  /// @brief `terminal:bell_mode` —— 0 关闭 / 1 震动 / 2 通知。
  ///
  /// 默认关闭。
  int get terminalBellMode => intOf(keyTerminalBellMode, fallback: 0);

  /// @brief 写响铃方式。
  Future<void> setTerminalBellMode(int value) => setInt(keyTerminalBellMode, value);

  /// @brief `terminal:keyboard_position` —— 0 终端上方 / 1 终端下方 /
  /// 2 关闭。
  ///
  /// 依据：原版对缺失值取 "1"，即**默认把额外键行放在终端下方**。
  int get terminalKeyboardPosition =>
      intOf(keyTerminalKeyboardPosition, fallback: 1);

  /// @brief 写键盘位置。
  Future<void> setTerminalKeyboardPosition(int value) =>
      setInt(keyTerminalKeyboardPosition, value);

  /// @brief `terminal:autocomplete` —— **原版从不读取这个键**。
  ///
  /// 反编译结果显示 `setAutocomplete(false)` 是硬编码的，这个设置项
  /// 在 `res/xml/settings.xml` 里也没有入口，属于「留了键但没接线」。
  /// 这里保留读写能力以便与原有配置互通，但界面不会用到，终端也始终关闭。
  bool get terminalAutocomplete => boolOf(keyTerminalAutocomplete, fallback: false);

  /// @brief 写自动补全开关（原版不使用）。
  Future<void> setTerminalAutocomplete(bool value) =>
      setBool(keyTerminalAutocomplete, value);

  // ------------------------------------------------------------ 安全 --

  /// @brief `ssh:agent` —— 默认关闭。
  bool get sshAgentForwarding => boolOf(keySshAgent, fallback: false);

  /// @brief 写 SSH Agent 转发开关。
  Future<void> setSshAgentForwarding(bool value) => setBool(keySshAgent, value);

  /// @brief `pinlock:enabled`
  bool get pinLockEnabled => boolOf(keyPinlockEnabled, fallback: false);

  /// @brief 写应用锁开关。
  Future<void> setPinLockEnabled(bool value) => setBool(keyPinlockEnabled, value);

  /// @brief `pinlock:timeout` —— 空闲秒数，超过后重新锁定。
  ///
  /// 默认 5 分钟。
  int get pinLockTimeoutSeconds => intOf(keyPinlockTimeout, fallback: 300);

  /// @brief 写空闲超时秒数。
  Future<void> setPinLockTimeoutSeconds(int value) => setInt(keyPinlockTimeout, value);

  /// @brief `pinlock:attempts` —— 已连续失败的次数。
  int get pinLockFailedAttempts => intOf(keyPinlockAttempts, fallback: 0);

  /// @brief 写连续失败次数。
  Future<void> setPinLockFailedAttempts(int value) => setInt(keyPinlockAttempts, value);

  /// @brief 与 PIN 一起存储。
  ///
  /// 真实存放位置由 `PinLockService` 决定，这里只暴露键名。
  String? get pinLockPinHash => _cache[keyPinlockPin];

  /// @brief 写 PIN 哈希。
  Future<void> setPinLockPinHash(String? value) => set(keyPinlockPin, value);

  // ------------------------------------------------------------ 其他 --

  /// @brief `mosh:mosh-server` —— 远端命令路径。
  String get moshServerCommand => _cache[keyMoshServerCommand] ?? 'mosh-server';

  /// @brief 写 mosh-server 路径。
  Future<void> setMoshServerCommand(String value) => set(keyMoshServerCommand, value);

  /// @brief `notifications:enabled`
  bool get notificationsEnabled => boolOf(keyNotificationsEnabled, fallback: true);

  /// @brief 写通知开关。
  Future<void> setNotificationsEnabled(bool value) =>
      setBool(keyNotificationsEnabled, value);

  /// @brief `session:timeout` —— 会话保活秒数。
  ///
  /// 默认 0（不自动断开）。
  int get sessionTimeoutSeconds => intOf(keySessionTimeout, fallback: 0);

  /// @brief 写会话保活秒数。
  Future<void> setSessionTimeoutSeconds(int value) => setInt(keySessionTimeout, value);

  /// @brief `tutorial:terminal` —— 是否已展示过终端引导。
  bool get terminalTutorialSeen => boolOf(keyTutorialTerminal, fallback: false);

  /// @brief 写终端引导是否已展示。
  Future<void> setTerminalTutorialSeen(bool value) =>
      setBool(keyTutorialTerminal, value);
}
