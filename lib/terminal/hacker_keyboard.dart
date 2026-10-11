import 'dart:async';

import 'package:flutter/material.dart';

import '../app/i18n.dart';
import 'escape_characters.dart';

/// 终端下方的「黑客键盘」额外键行。
///
/// 完全按原版 `res/layout/hacker_keyboard.xml`、
/// `hacker_keyboard_function_keys.xml` 与 `hacker_keyboard_pager.xml` 复刻：
///
/// * 整条键行高度 **恰好 70dp**，内部两行各 35dp；
/// * 主键页是 8 列等宽网格（`stretchColumns="*"`），`/`、`|`、`-` 三键
///   合占 2 列；
/// * 功能键页是 7 列网格，两行 F1–F12 加两个图标键；
/// * 键背景常态**完全透明**（`#00FFFFFF`），按下为 `#57FFFFFF`，
///   无描边、无圆角（`@drawable/keyboard`）；
/// * 字样：Esc/Home/End/PgUp/PgDn/Tab/Ctrl/Alt/Fn/F1–F12 为 14sp，
///   `/` `|` `-` 与四个方向键为 18sp，方向键额外加粗；
/// * `AutoRepeatButton` 的连发参数为**首次延迟 500ms、之后每 50ms 一次**。
///
/// 按键只往外抛原始 tag（[KeyTag]），语义由终端页统一解释 ——
/// 与原版「布局只写 tag、逻辑集中在 `keyboardPress`」的结构一致。
class HackerKeyboard extends StatelessWidget {
  const HackerKeyboard({
    super.key,
    required this.onKeyTag,
    required this.showingFunctionKeys,
    required this.ctrlArmed,
    required this.altArmed,
    required this.foreground,
    this.onToggleFunctionKeys,
  });

  /// 抛出被按下按键的 tag。
  final ValueChanged<int> onKeyTag;

  /// 当前是否停在功能键页。
  final bool showingFunctionKeys;

  /// Ctrl 是否处于待生效状态（原版按下后按钮保持高亮）。
  final bool ctrlArmed;

  /// Alt 是否处于待生效状态。
  final bool altArmed;

  /// 键面颜色。原版是 `TerminalThemedButton`，字色跟随终端前景色。
  final Color foreground;

  /// 切换主键页 / 功能键页；不传则 Fn 键不响应。
  final VoidCallback? onToggleFunctionKeys;

  /// 键行总高度，取自 `hacker_keyboard_pager.xml` 的 `70.0dp`。
  static const double height = 70;

  /// 单行高度，`TableRow` 内每个键的 `35.0dp`。
  static const double rowHeight = 35;

  void _press(int tag) => onKeyTag(tag);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: showingFunctionKeys ? _buildFunctionPage(context) : _buildMainPage(context),
    );
  }

  /// 主键页。
  ///
  /// 第一行：`Esc | (/ | -)span2 | Home | ↑ | End | PgUp | Fn`
  /// 第二行：`Tab | Ctrl | Alt | ← | ↓ | → | PgDn | 键盘开关`
  Widget _buildMainPage(BuildContext context) {
    final s = context.s;

    return Column(
      children: [
        SizedBox(
          height: rowHeight,
          child: Row(
            children: [
              _Key(
                label: s('esc'),
                tag: KeyTag.escape,
                fontSize: 14,
                foreground: foreground,
                onPressed: _press,
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    _Key(
                      label: s('forwardslash'),
                      tag: KeyTag.slash,
                      fontSize: 18,
                      foreground: foreground,
                      onPressed: _press,
                    ),
                    _Key(
                      label: s('pipe'),
                      tag: KeyTag.pipe,
                      fontSize: 18,
                      // 原版这个键是 AutoRepeatButton，但没有连发语义上的必要；
                      // 仍按原样开启连发以保持一致。
                      foreground: foreground,
                      onPressed: _press,
                    ),
                    _Key(
                      label: s('dash'),
                      tag: KeyTag.minus,
                      fontSize: 18,
                      foreground: foreground,
                      onPressed: _press,
                    ),
                  ],
                ),
              ),
              _Key(
                label: s('home'),
                tag: KeyTag.moveHome,
                fontSize: 14,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('up_arrow'),
                tag: KeyTag.dpadUp,
                fontSize: 18,
                bold: true,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('end'),
                tag: KeyTag.moveEnd,
                fontSize: 14,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('page_up'),
                tag: KeyTag.pageUp,
                fontSize: 14,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('fn'),
                tag: KeyTag.fn,
                fontSize: 14,
                // TerminalThemedButton：不连发
                autoRepeat: false,
                foreground: foreground,
                onPressed: (tag) {
                  onToggleFunctionKeys?.call();
                  _press(tag);
                },
              ),
            ],
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: Row(
            children: [
              _Key(
                label: s('tab'),
                tag: KeyTag.tab,
                fontSize: 14,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('ctrl'),
                tag: KeyTag.ctrl,
                fontSize: 14,
                autoRepeat: false,
                armed: ctrlArmed,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('alt'),
                tag: KeyTag.alt,
                fontSize: 14,
                autoRepeat: false,
                armed: altArmed,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('left_arrow'),
                tag: KeyTag.dpadLeft,
                fontSize: 18,
                bold: true,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('down_arrow'),
                tag: KeyTag.dpadDown,
                fontSize: 18,
                bold: true,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('right_arrow'),
                tag: KeyTag.dpadRight,
                fontSize: 18,
                bold: true,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                label: s('page_down'),
                tag: KeyTag.pageDown,
                fontSize: 14,
                foreground: foreground,
                onPressed: _press,
              ),
              _Key(
                icon: Icons.keyboard,
                tooltip: s('toggle_keyboard'),
                tag: KeyTag.toggleKeyboard,
                autoRepeat: false,
                foreground: foreground,
                onPressed: _press,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 功能键页：两行各 7 列，F1–F6 + 返回，F7–F12 + 键盘开关。
  Widget _buildFunctionPage(BuildContext context) {
    final s = context.s;

    Widget key(int number) => _Key(
          label: s('f$number'),
          tag: KeyTag.functionKey(number),
          fontSize: 14,
          foreground: foreground,
          onPressed: _press,
        );

    return Column(
      children: [
        SizedBox(
          height: rowHeight,
          child: Row(
            children: [
              for (var i = 1; i <= 6; i++) key(i),
              _Key(
                icon: Icons.undo,
                tooltip: s('toggle_keyboard'),
                tag: KeyTag.backToMain,
                autoRepeat: false,
                foreground: foreground,
                onPressed: (tag) {
                  onToggleFunctionKeys?.call();
                  _press(tag);
                },
              ),
            ],
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: Row(
            children: [
              for (var i = 7; i <= 12; i++) key(i),
              _Key(
                icon: Icons.keyboard,
                tooltip: s('toggle_keyboard'),
                tag: KeyTag.toggleKeyboard,
                autoRepeat: false,
                foreground: foreground,
                onPressed: _press,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单个键。
///
/// 对应原版的 `AutoRepeatButton` / `TerminalThemedButton` /
/// `TerminalThemedImageButton` 三种：
/// * [autoRepeat] 为 true 时按 `AutoRepeatButton` 的参数连发；
/// * [armed] 为 true 时保持按下态背景，对应 `TerminalThemedButton.d(int)`。
class _Key extends StatefulWidget {
  const _Key({
    this.label,
    this.icon,
    this.tooltip,
    required this.tag,
    this.fontSize = 14,
    this.bold = false,
    this.autoRepeat = true,
    this.armed = false,
    required this.foreground,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final int tag;
  final double fontSize;
  final bool bold;
  final bool autoRepeat;
  final bool armed;
  final Color foreground;
  final ValueChanged<int> onPressed;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  /// `@drawable/keyboard` 的按下色 `#57FFFFFF`。
  static const Color _pressedColor = Color(0x57FFFFFF);

  bool _pressed = false;
  Timer? _repeatTimer;

  /// `AutoRepeatButton` 的首次连发延迟。
  static const Duration _repeatDelay = Duration(milliseconds: 500);

  /// 连发间隔。
  static const Duration _repeatInterval = Duration(milliseconds: 50);

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _pressed = true);
    widget.onPressed(widget.tag);
    if (!widget.autoRepeat) return;
    // 长按先等 500ms 再开始以 50ms 的间隔连发。
    _repeatTimer = Timer(_repeatDelay, () {
      _repeatTimer = Timer.periodic(_repeatInterval, (_) {
        widget.onPressed(widget.tag);
      });
    });
  }

  void _stop() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _pressed || widget.armed;

    Widget child;
    if (widget.icon != null) {
      child = Icon(widget.icon, size: 18, color: widget.foreground);
    } else {
      child = Text(
        widget.label ?? '',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: widget.foreground,
          fontSize: widget.fontSize,
          fontWeight: widget.bold ? FontWeight.bold : FontWeight.normal,
        ),
      );
    }

    return Expanded(
      child: Semantics(
        button: true,
        label: widget.tooltip ?? widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _start(),
          onTapUp: (_) => _stop(),
          onTapCancel: _stop,
          child: Container(
            color: highlighted ? _pressedColor : Colors.transparent,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
