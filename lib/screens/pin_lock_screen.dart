import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../app/i18n.dart';
import '../app/juice_colors.dart';
import '../app/settings_controller.dart';

/// PIN 锁的存取与校验。
///
/// 原版把 PIN 放在 `pinlock:pin` 配置里（`Config` 的默认值表里能看到这个键），
/// 明文与加密两种形态都由 `User.v()/User.E()` 负责；连续失败次数放在
/// `pinlock:attempts`，锁定时戳放在 `pinlock:timeout`（都在 `LruSessionCache`）。
///
/// 本复刻版做了两点改动，都是为了不把明文 PIN 落到库里：
///
/// * **只存加盐 SHA-256**：值形如 `"<saltHex>:<hashHex>"`，盐是 16 字节
///   `Random.secure()` 随机数，哈希是把 `salt || UTF-8(pin)` 交给
///   pointycastle 的 `SHA256Digest`；
/// * **锁定时戳另存键** `pinlock:lockout_until`（毫秒时间戳）。原版把它塞在
///   会话缓存里，而本项目的 `SettingsController.pinLockTimeoutSeconds`
///   已经把 `pinlock:timeout` 定义为「空闲秒数」了，复用它会把语义撞车。
///
/// 阈值与时长取自反编译代码 `PinManager.b()`：
/// `const/4 v1, 0x5`（上限 5 次）与 `const-wide/32 v4, 0x493e0`
/// （300000ms = 5 分钟）。
class PinLockService {
  PinLockService._();

  static final PinLockService instance = PinLockService._();

  /// 连续失败次数上限，对应 `PinManager.b()` 里的 `const/4 v1, 0x5`。
  static const int maxAttempts = 5;

  /// 锁定时长，对应 `PinManager.b()` 里的 `0x493e0`（5 分钟）。
  static const Duration lockoutDuration = Duration(minutes: 5);

  /// 盐长度（字节）。原版没有可参照的值，这里按常见做法取 16。
  static const int _saltLength = 16;

  /// 锁定截止时间的存放键（毫秒时间戳）。
  static const String keyLockoutUntil = 'pinlock:lockout_until';

  SettingsController get _settings => SettingsController.instance;

  /// 是否已经设置过 PIN。
  bool get hasPin {
    final stored = _settings.pinLockPinHash;
    return stored != null && stored.isNotEmpty;
  }

  /// 剩余可尝试次数；0 表示已经用满。
  int get remainingAttempts =>
      max(0, maxAttempts - _settings.pinLockFailedAttempts);

  /// 锁定截止时间；不在锁定中返回 null。
  DateTime? get lockoutUntil {
    final raw = _settings.intOf(keyLockoutUntil, fallback: 0);
    if (raw <= 0) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(raw);
    return at.isAfter(DateTime.now()) ? at : null;
  }

  /// 距离解锁还剩多久；不在锁定中返回 [Duration.zero]。
  Duration get lockoutRemaining {
    final at = lockoutUntil;
    if (at == null) return Duration.zero;
    return at.difference(DateTime.now());
  }

  /// 是否处于锁定状态。
  bool get isLockedOut => lockoutUntil != null;

  /// 校验 PIN。**成功时会清零失败次数**（对应 `PinManager$a.d()` 里的
  /// `zk0.i(context, 0, 0)`）。
  Future<bool> verify(String pin) async {
    final stored = _settings.pinLockPinHash;
    if (stored == null || stored.isEmpty || pin.isEmpty) return false;
    final ok = _matches(pin, stored);
    if (ok) await resetFailures();
    return ok;
  }

  /// 设置（或重设）PIN，并清零失败计数与锁定状态。
  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    final encoded = '${_hex(salt)}:${_hash(salt, pin)}';
    await _settings.setPinLockPinHash(encoded);
    await resetFailures();
  }

  /// 清除 PIN 与失败计数。
  Future<void> clearPin() async {
    await _settings.setPinLockPinHash(null);
    await resetFailures();
  }

  /// 记录一次失败；达到上限时写入锁定截止时间。
  ///
  /// 返回记录之后**剩余**的可尝试次数。
  Future<int> recordFailure() async {
    final failed = _settings.pinLockFailedAttempts + 1;
    await _settings.setPinLockFailedAttempts(failed);
    if (failed >= maxAttempts) {
      final until = DateTime.now().add(lockoutDuration).millisecondsSinceEpoch;
      await _settings.setInt(keyLockoutUntil, until);
    }
    return max(0, maxAttempts - failed);
  }

  /// 清零失败次数与锁定截止时间。
  Future<void> resetFailures() async {
    await _settings.setPinLockFailedAttempts(0);
    await _settings.setInt(keyLockoutUntil, 0);
  }

  /// 锁定期已过则自动复位（对应 `PinManager.b()` 里
  /// 「`now - timeout >= 300000` 就把计数与时间戳清零」的逻辑）。
  Future<void> refreshLockout() async {
    final raw = _settings.intOf(keyLockoutUntil, fallback: 0);
    if (raw <= 0) return;
    if (DateTime.fromMillisecondsSinceEpoch(raw).isAfter(DateTime.now())) return;
    await resetFailures();
  }

  // ------------------------------------------------------------ 内部实现 --

  List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(_saltLength, (_) => random.nextInt(256));
  }

  String _hash(List<int> salt, String pin) {
    final input = Uint8List.fromList(<int>[...salt, ...utf8.encode(pin)]);
    return _hex(SHA256Digest().process(input));
  }

  String _hex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// 比对时不提前返回，避免按字符位置泄漏信息。
  bool _matches(String pin, String stored) {
    final separator = stored.indexOf(':');
    if (separator <= 0) return false;
    final saltHex = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    final salt = _unhex(saltHex);
    if (salt == null) return false;
    final actual = _hash(salt, pin);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  List<int>? _unhex(String hex) {
    if (hex.isEmpty || hex.length.isOdd) return null;
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
    return bytes;
  }
}

/// PIN 解锁界面。
///
/// 布局逐项对应 `res/layout/numeric_pin_prompt.xml`：
///
/// * 根布局竖直居中，背景 `@color/pinlock_background`（纯黑）；
/// * 顶部提示 56dp 高、整行居中、`@color/primary_bold`，文案
///   `enter_your_pin_to_unlock`；
/// * 中间一行是左右各一个空白 `FrameLayout`（weight 1）+ 正中的 232dp × 56dp
///   显示区：原版是 `enabled=false` 的 `EditText`，`inputType=textPassword`，
///   24sp、`primary_bold`、居中；因为它是密码框，显示的是 `•` 而不是数字；
/// * 底部 4 × 3 键盘：每格 56dp × 56dp、外边距 16dp、20sp、`primary_bold`，
///   背景 `@drawable/pin_button`（4dp 椭圆描边，常态 `@color/primary_bold`，
///   按下 `@color/primary_bold_transparent`）；第四行左边是
///   `@string/icon_eraser`（FontAwesome U+F12D），右边是 `@string/ok`。
///
/// 行为部分对应 `PinManager` / `cj0`（`NumericPinFragment`）：
///
/// * 输入长度上限 255（`cj0$d.onClick` 里的 `0xff`）；
/// * 只有按 OK 才提交（原版不会自动提交）；
/// * 输错时把剩余次数用 `incorrect_pin_attempt_x_remaining` 提示（原版是 Toast，
///   这里用 SnackBar）；
/// * 连续错满 [PinLockService.maxAttempts] 次进入锁定态：标题 `locked_out`
///   （26sp、加粗、白），副标题 `too_many_incorrect_security_lock_attempts`
///   （12sp、斜体、`@android:color/darker_gray`），倒计时归零后自动放行。
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key, this.onUnlocked});

  /// 解锁成功后的回调。调用之后界面还会把当前路由 pop(true)，
  /// 所以它必须像原版的 `NumericPinFragment` 一样以整屏路由的方式使用
  /// （见 [PinLockScreen.show]）。
  final VoidCallback? onUnlocked;

  /// 以整屏路由弹入解锁界面，返回是否解锁成功。
  static Future<bool> show(BuildContext context, {VoidCallback? onUnlocked}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PinLockScreen(onUnlocked: onUnlocked),
      ),
    );
    return result ?? false;
  }

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final PinLockService _service = PinLockService.instance;

  /// 已输入的数字。
  String _pin = '';

  /// 是否处于锁定态。
  bool _lockedOut = false;

  /// 锁定倒计时（每秒刷新一次）。
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _lockedOut = _service.isLockedOut;
    if (_lockedOut) _startCountdown();
    unawaited(_refreshLockout());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  /// 上一次锁定期已过就复位计数（`PinManager.b()` 的同一逻辑）。
  Future<void> _refreshLockout() async {
    await _service.refreshLockout();
    if (!mounted || !_lockedOut) return;
    if (_service.isLockedOut) return;
    setState(() => _lockedOut = false);
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_service.isLockedOut) {
        timer.cancel();
        setState(() {
          _lockedOut = false;
          _pin = '';
        });
        // 锁定期结束后把 `pinlock:attempts` 归零，否则下一次输错会立刻再次锁定。
        unawaited(_service.resetFailures());
        return;
      }
      setState(() {});
    });
  }

  void _append(String digit) {
    // 原版 `cj0$d` 的上限是 0xff。
    if (_pin.length >= 255) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final s = context.s;
    if (_service.isLockedOut) return;
    final entered = _pin;
    if (entered.isEmpty) return;

    final ok = await _service.verify(entered);
    if (!mounted) return;

    if (ok) {
      setState(() => _pin = '');
      // 原版是 `cj0$c` 里 dismiss 掉 DialogFragment，这里等价于弹出本路由。
      widget.onUnlocked?.call();
      Navigator.of(context).pop(true);
      return;
    }

    final remaining = await _service.recordFailure();
    if (!mounted) return;

    setState(() => _pin = '');
    if (remaining <= 0) {
      setState(() => _lockedOut = true);
      _startCountdown();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.format('incorrect_pin_attempt_x_remaining', [remaining])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JuiceFixedColors.pinlockBackground,
      body: SafeArea(
        child: _lockedOut ? _buildLockout(context) : _buildPrompt(context),
      ),
    );
  }

  /// 解锁输入界面（`numeric_pin_prompt.xml`）。
  Widget _buildPrompt(BuildContext context) {
    return _PinPromptBody(
      message: context.s('enter_your_pin_to_unlock'),
      pinLength: _pin.length,
      keypad: _PinKeypad(
        onDigit: _append,
        onBackspace: _backspace,
        onSubmit: _submit,
      ),
    );
  }

  /// 锁定界面（`lockout.xml` 的权重 1.8 / 2.0 / 1.8）。
  Widget _buildLockout(BuildContext context) {
    final s = context.s;
    final remaining = _service.lockoutRemaining;
    return Column(
      children: [
        const Expanded(flex: 18, child: SizedBox.expand()),
        Expanded(
          flex: 20,
          child: Center(
            // 原版这里是 100dp 的 `@drawable/ic_launcher`；本仓库还没把
            // 启动图标抽成 Flutter 资源，先用等价的锁形图标占位。
            child: Icon(
              Icons.lock_outline,
              size: _PinMetrics.lockoutIconSize,
              color: _PinMetrics.foreground,
            ),
          ),
        ),
        Expanded(
          flex: 18,
          child: Column(
            children: [
              Text(
                s('locked_out'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _PinMetrics.lockoutTitle,
                  fontSize: _PinMetrics.lockoutTitleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                s.format('too_many_incorrect_security_lock_attempts', [
                  _relativeTime(remaining),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _PinMetrics.lockoutSubtitle,
                  fontSize: _PinMetrics.lockoutSubtitleSize,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 近似 Android `DateUtils.getRelativeTimeSpanString(now + remaining + 60000)`：
  /// 先补足一分钟再按分钟四舍五入，得到 "In N min."。
  String _relativeTime(Duration remaining) {
    final minutes = ((remaining.inMilliseconds + 60000) / 60000).round();
    return 'In $minutes min.';
  }
}

/// 设置新 PIN 界面。
///
/// 原版这条路径就是同一个 `cj0`（`NumericPinFragment`）的 mode 1 分支：
/// 提示文案换成 `please_set_a_pin`，按 OK 直接把输入写进 `pinlock:pin`
/// （见 `cj0$c.onClick` 的 `User.E(activity, text)`），**没有二次确认步骤**。
/// 写完之后 `xk0$a.d()` 才把 `pinlock:enabled` 置为 true。
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  /// 弹出入 PIN 设置页，返回用户是否成功设置了 PIN。
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const PinSetupScreen(),
      ),
    );
    return result ?? false;
  }

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final PinLockService _service = PinLockService.instance;

  String _pin = '';

  void _append(String digit) {
    if (_pin.length >= 255) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final s = context.s;
    if (_pin.isEmpty) {
      // 原版允许存空 PIN（`User.E(context, "")`），这里按需求拒绝空值。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s('you_must_set_a_password'))),
      );
      return;
    }
    final entered = _pin;
    await _service.setPin(entered);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: JuiceFixedColors.pinlockBackground,
      body: SafeArea(
        child: Stack(
          children: [
            _PinPromptBody(
              message: s('please_set_a_pin'),
              pinLength: _pin.length,
              keypad: _PinKeypad(
                onDigit: _append,
                onBackspace: _backspace,
                onSubmit: _submit,
              ),
            ),
            // 原版靠 Android 的返回键取消（`cj0.i(true, mode)` 里 cancelable=true），
            // 桌面端没有返回键，所以补一个关闭按钮。
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: s('cancel'),
                icon: const Icon(Icons.close, color: _PinMetrics.foreground),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PIN 提示页的公共骨架（`numeric_pin_prompt.xml` 的上半部分）：
/// 顶部提示 + 中间左右留白的密码点阵 + 键盘。
///
/// 原版整页固定尺寸、不滚动；这里套一层 [SingleChildScrollView]，
/// 免得小窗口下溢出，同时用 [ConstrainedBox] 保住竖直居中。
class _PinPromptBody extends StatelessWidget {
  const _PinPromptBody({
    required this.message,
    required this.pinLength,
    required this.keypad,
  });

  /// 顶部提示文案（解锁是 `enter_your_pin_to_unlock`，设置新 PIN 是
  /// `please_set_a_pin`）。
  final String message;

  /// 已输入的位数；用 [String] 乘出对应个数的 `•`。
  final int pinLength;

  /// 数字键盘。
  final Widget keypad;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: _PinMetrics.messageHeight,
                child: Center(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _PinMetrics.foreground,
                      fontSize: _PinMetrics.promptTextSize,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  SizedBox(
                    width: _PinMetrics.displayWidth,
                    height: _PinMetrics.messageHeight,
                    child: Center(
                      child: Text(
                        '•' * pinLength,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          color: _PinMetrics.foreground,
                          fontSize: _PinMetrics.displayTextSize,
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),
              keypad,
            ],
          ),
        ),
      ),
    );
  }
}

/// `numeric_pin_prompt.xml` 里的固定尺寸与颜色。
abstract final class _PinMetrics {
  /// 顶栏提示与密码显示区的高度：`56.0dp`。
  static const double messageHeight = 56;

  /// 密码显示区宽度：`232.0dp`。
  static const double displayWidth = 232;

  /// 键盘键尺寸：`56.0dp`。
  static const double keySize = 56;

  /// 键外边距：`layout_margin="16.0dp"`。
  static const double keyMargin = 16;

  /// 提示文案字号。
  ///
  /// 原版 `@id/message` 没写 `textSize`、也没写样式，于是走主题的
  /// `?android:textAppearance`（`Theme.Material` → `TextAppearance.Material.Body1`
  /// = 14sp）。框架资源不在 APK 里，这里是按该链路推断的值。
  static const double promptTextSize = 14;

  /// 密码显示区字号：`24.0sp`。
  static const double displayTextSize = 24;

  /// 键面字号：`20.0sp`。
  static const double keyTextSize = 20;

  /// 键面颜色：`@color/primary_bold`。
  static const Color foreground = Color(0xFFFFE24C);

  /// 按下时的描边色：`@color/primary_bold_transparent`。
  static const Color pressedRing = Color(0x55FFE24C);

  /// 锁定页标题色：`@android:color/white`。
  static const Color lockoutTitle = Color(0xFFFFFFFF);

  /// 锁定页副标题色：`@android:color/darker_gray`。
  static const Color lockoutSubtitle = Color(0xFF444444);

  /// 锁定页标题字号：`26.0sp`。
  static const double lockoutTitleSize = 26;

  /// 锁定页副标题字号：`12.0sp`。
  static const double lockoutSubtitleSize = 12;

  /// 锁定页图标尺寸：`100.0dp`。
  static const double lockoutIconSize = 100;
}

/// 数字键盘：4 × 3，对应 `numeric_pin_prompt.xml` 的 `TableLayout`。
class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child) => Padding(
          padding: const EdgeInsets.all(_PinMetrics.keyMargin),
          child: SizedBox(
            width: _PinMetrics.keySize,
            height: _PinMetrics.keySize,
            child: child,
          ),
        );

    Widget digit(String value) => cell(
          _PinKey(
            semanticLabel: value,
            onPressed: () => onDigit(value),
            child: Text(
              value,
              style: const TextStyle(
                color: _PinMetrics.foreground,
                fontSize: _PinMetrics.keyTextSize,
              ),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [digit('1'), digit('2'), digit('3')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [digit('4'), digit('5'), digit('6')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [digit('7'), digit('8'), digit('9')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            cell(
              _PinKey(
                semanticLabel: context.s('back'),
                onPressed: onBackspace,
                child: Text(
                  context.s('icon_eraser'),
                  style: const TextStyle(
                    color: _PinMetrics.foreground,
                    fontSize: _PinMetrics.keyTextSize,
                    fontFamily: 'JuiceFontAwesome',
                  ),
                ),
              ),
            ),
            digit('0'),
            cell(
              _PinKey(
                semanticLabel: context.s('ok'),
                onPressed: onSubmit,
                child: Text(
                  context.s('ok'),
                  style: const TextStyle(
                    color: _PinMetrics.foreground,
                    fontSize: _PinMetrics.keyTextSize,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单个键：`@drawable/pin_button` 的 4dp 椭圆描边 + 选中/按下时的
/// `primary_bold_transparent` 描边。
class _PinKey extends StatefulWidget {
  const _PinKey({
    required this.child,
    required this.onPressed,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onPressed;
  final String? semanticLabel;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: 4,
              color: _pressed ? _PinMetrics.pressedRing : _PinMetrics.foreground,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
