/// @brief F1–F12 的功能键转义序列。
///
/// 严格照搬 `com/sonelli/ti0`（原始类名 `EscapeCharacters`）。
/// 原版不是硬编码一套序列，而是按当前终端类型（`terminal:type`）查表，
/// 因为不同 terminfo 对功能键的定义确实不同 —— 例如 `linux` 下 F1 是
/// `ESC[[A`，而 `xterm` 下 F1 是 `ESCOP`。这里保留同样的分型。
///
/// 序列内容逐条取自反编译出的 5 个分支：
/// * `LINUX`           → `ti0$a.a[0] == 1`
/// * `XTERM`           → `2`
/// * `XTERM_COLOR`     → `3`
/// * `XTERM_256COLOR`  → `4`
/// * `VT100`           → `5`
class EscapeCharacters {
  /// @brief 按终端类型构造一份功能键序列表。
  const EscapeCharacters(this.terminalType);

  /// @brief 终端类型，取值与设置页 `terminal_type_values` 一致。
  final String terminalType;

  /// @brief ANSI 里的 ESC。
  static const String esc = '\u001b';

  /// @brief 归一化终端类型，无法识别时退回 LINUX。
  ///
  /// 原版 `ti0.<init>` 对无法识别的类型会退化成 LINUX（`ti0.b(null)` 分支）。
  String get _normalized {
    switch (terminalType) {
      case 'linux':
      case 'xterm':
      case 'xterm-color':
      case 'xterm-256color':
      case 'vt100':
        return terminalType;
      default:
        return 'linux';
    }
  }

  /// @brief 返回 12 条序列，下标 0 对应 F1。
  ///
  /// 注意两点原版行为，这里原样保留：
  /// * `xterm` 与 `xterm-256color` 的序列在本版本里完全相同；
  /// * `vt100` 的 F11/F12 是**空串**，按下不发送任何内容。
  /// 返回 12 条序列，下标 0 对应 F1。
  ///
  /// 序列用 `\u001b` 直接写成字面量，与反编译出的 smali 字符串常量
  /// （形如 `"\u001bOP"`）逐字对应，避免任何拼接歧义。
  ///
  /// 注意两点原版行为，这里原样保留：
  /// * `xterm` 与 `xterm-256color` 的序列在本版本里完全相同；
  /// * `vt100` 的 F11/F12 是**空串**，按下不发送任何内容。
  List<String> get functionKeys {
    switch (_normalized) {
      case 'xterm':
      case 'xterm-256color':
        return const [
          '\u001bOP', '\u001bOQ', '\u001bOR', '\u001bOS',
          '\u001b[15~', '\u001b[17~', '\u001b[18~', '\u001b[19~',
          '\u001b[20~', '\u001b[21~', '\u001b[23~', '\u001b[24~',
        ];
      case 'xterm-color':
        return const [
          '\u001b[11~', '\u001b[12~', '\u001b[13~', '\u001b[14~',
          '\u001b[15~', '\u001b[17~', '\u001b[18~', '\u001b[19~',
          '\u001b[20~', '\u001b[21~', '\u001b[23~', '\u001b[24~',
        ];
      case 'vt100':
        return const [
          '\u001bOP', '\u001bOQ', '\u001bOR', '\u001bOS',
          // 注意这里是 `ESC O t` 三个字符，中间**没有空格**。
          // 逐字核对过 `com/sonelli/ti0.smali` 第 188–212 行的 const-string。
          '\u001bOt', '\u001bOu', '\u001bOv', '\u001bOl',
          '\u001bOw', '\u001bOx', '', '',
        ];
      case 'linux':
      default:
        return const [
          '\u001b[[A', '\u001b[[B', '\u001b[[C', '\u001b[[D', '\u001b[[E',
          '\u001b[17~', '\u001b[18~', '\u001b[19~', '\u001b[20~',
          '\u001b[21~', '\u001b[23~', '\u001b[24~',
        ];
    }
  }

  /// @brief 取第 [number] 个功能键的序列（1 起算）。越界返回空串。
  String functionKey(int number) {
    if (number < 1 || number > 12) return '';
    return functionKeys[number - 1];
  }
}

/// @brief 额外键行里每个按键的标识。
///
/// 取值**逐字对应**原版布局文件里 `android:tag` 的数字，
/// 这样 `keyboardPress` 的语义可以一一对照：
///
/// * 正数 = Android `KeyEvent` 键码，原版据此构造 `KeyEvent(0, keyCode)`
///   并交给系统分发，由终端模拟器生成转义序列；
/// * 负数 = 内部伪码，对应 `TerminalEmulatorActivity` 里
///   `packed-switch -0x16` 的各分支。
class KeyTag {
  /// @brief 私有构造：本类只是常量集合。
  const KeyTag._();

  /// @brief `|` —— 原版直接写字符串 `"|"`（而不是走按键分发）
  static const int pipe = -1;

  /// @brief Ctrl，一次性的控制键（按下后高亮，作用于下一个按键）
  static const int ctrl = -2;

  /// @brief Fn，切换到功能键页
  static const int fn = -3;

  /// @brief Alt，立刻发送一个 ESC 作为前缀
  static const int alt = -4;

  /// @brief 显示 / 隐藏软键盘
  static const int toggleKeyboard = -5;

  /// @brief 从功能键页返回主键页
  static const int backToMain = -7;

  /// @brief F1..F12 对应 -11..-22
  static const int firstFunctionKey = -11;
  /// @brief F12 的 tag 值。
  static const int lastFunctionKey = -22;

  /// @brief 由功能键序号（1..12）算出它的 tag。
  static int functionKey(int number) => -10 - number;

  /// @brief 判断一个 tag 是否落在功能键区间内。
  static bool isFunctionKey(int tag) =>
      tag >= lastFunctionKey && tag <= firstFunctionKey;

  /// @brief 由负数 tag 反推功能键序号（1..12）；不是功能键则返回 0。
  static int functionKeyNumber(int tag) =>
      isFunctionKey(tag) ? -tag - 10 : 0;

  // ---- 正数：Android KeyEvent 键码（原版 android:tag 的原值） ----

  /// @brief KEYCODE_DPAD_UP，键面 ↑
  static const int dpadUp = 19;

  /// @brief KEYCODE_DPAD_DOWN，键面 ↓
  static const int dpadDown = 20;

  /// @brief KEYCODE_DPAD_LEFT，键面 ←
  static const int dpadLeft = 21;

  /// @brief KEYCODE_DPAD_RIGHT，键面 →
  static const int dpadRight = 22;

  /// @brief KEYCODE_TAB
  static const int tab = 61;

  /// @brief KEYCODE_MINUS，键面 `-`
  static const int minus = 69;

  /// @brief KEYCODE_SLASH，键面 `/`
  static const int slash = 76;

  /// @brief KEYCODE_PAGE_UP
  static const int pageUp = 92;

  /// @brief KEYCODE_PAGE_DOWN
  static const int pageDown = 93;

  /// @brief KEYCODE_ESCAPE
  static const int escape = 111;

  /// @brief KEYCODE_MOVE_HOME
  static const int moveHome = 122;

  /// @brief KEYCODE_MOVE_END
  static const int moveEnd = 123;
}
