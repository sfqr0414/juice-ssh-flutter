import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../ssh/ssh_service.dart';
import 'juice_alert_dialog.dart';

/// 应用里的通用对话框。
///
/// 文案全部取自原版 `res/values/strings.xml`，不另写一套，
/// 因此中英文表现都与原版一致。
///
/// 外观统一走 [JuiceAlertDialog]（AppCompat `AlertDialog` 的度量还原）
/// 与 [JuiceDialogAction]（按钮全大写、64dp×54.1dp），
/// 不再直接用 Flutter 的 `AlertDialog` 默认样式 —— 默认样式的窗口宽度、
/// 标题行高、按钮尺寸都与原版差得很远。
class JuiceDialogs {
  const JuiceDialogs._();

  /// 主机密钥确认框。
  ///
  /// 对应原版两条文案：
  /// * 首次连接 —— `this_is_the_first_time_youve_connected`
  /// * 密钥变更 —— `host_key_changed`
  ///
  /// 两者标题都是 `host_verification`（Host Verification），
  /// 按钮都是 Accept / Reject。
  static Future<HostKeyVerdict> confirmHostKey(
    BuildContext context,
    HostKeyChallenge challenge,
  ) async {
    final s = context.s;
    final body = challenge.changed
        ? s.format('host_key_changed', [
            challenge.hostname,
            challenge.fingerprint,
          ])
        : s.format('this_is_the_first_time_youve_connected', [
            challenge.hostname,
            challenge.fingerprint,
          ]);

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) {
        final colors = JuiceDialogColors.of(context);
        return JuiceAlertDialog(
          title: s('host_verification'),
          contentPadding: JuiceAlertDialog.messageContentPadding,
          content: SingleChildScrollView(
            child: SelectableText(body, style: colors.bodyStyle),
          ),
          actions: <Widget>[
            JuiceDialogAction(
              label: s('reject'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            JuiceDialogAction(
              label: s('accept'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    return accepted == true ? HostKeyVerdict.accepted : HostKeyVerdict.rejected;
  }

  /// 询问密码 / 私钥口令 / 两步验证码。
  ///
  /// [echo] 为 false 时输入框隐藏字符，对应原版
  /// `please_enter_your_private_key_passphrase` 这类提示。
  static Future<String?> promptForSecret(
    BuildContext context, {
    required String prompt,
    required bool echo,
  }) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => _TextPromptDialog(
        title: prompt,
        obscure: !echo,
      ),
    );
  }

  /// 通用「确认 / 取消」框。返回 true 表示用户确认。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
  }) async {
    final s = context.s;
    final result = await showDialog<bool>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) {
        final colors = JuiceDialogColors.of(context);
        return JuiceAlertDialog(
          title: title,
          contentPadding: JuiceAlertDialog.messageContentPadding,
          content: Text(message, style: colors.bodyStyle),
          actions: <Widget>[
            JuiceDialogAction(
              label: s('cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            JuiceDialogAction(
              label: confirmLabel ?? s('ok'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  /// 「本复刻没做这个功能」的统一提示。
  ///
  /// 原版里这些入口背后是内购、账号云同步、EC2、第三方插件、图书等
  /// 本复刻没有实现的能力。宁可明确说一句，也不要让用户点了没反应，
  /// 更不要借用 `an_error_has_occurred` 之类的键假装是原版的错误路径。
  static Future<void> notInThisBuild(
    BuildContext context, {
    required String title,
  }) =>
      message(
        context,
        title: title,
        message: 'Not available in this build.',
      );

  /// 通用提示框。
  static Future<void> message(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final s = context.s;
    await showDialog<void>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) {
        final colors = JuiceDialogColors.of(context);
        return JuiceAlertDialog(
          title: title,
          contentPadding: JuiceAlertDialog.messageContentPadding,
          content: Text(message, style: colors.bodyStyle),
          actions: <Widget>[
            JuiceDialogAction(
              label: s('ok'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  /// 单行文本输入框。用于「新建分组」这类简单命名操作。
  static Future<String?> promptForText(
    BuildContext context, {
    required String title,
    String? hint,
    String? initialValue,
  }) async {
    return showDialog<String>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => _TextPromptDialog(
        title: title,
        hint: hint,
        initialValue: initialValue,
        selectAll: true,
      ),
    );
  }

  /// 粘贴私钥用的多行输入框。
  ///
  /// 原版标题 `@string/private_key`、提示 `@string/paste`，输入框
  /// 7~12 行且关闭自动纠错联想（`private_key_prompt_pastepage.xml`）。
  static Future<String?> promptForPrivateKey(
    BuildContext context, {
    required String title,
    required String hint,
    String? initialValue,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => _TextPromptDialog(
        title: title,
        hint: hint,
        initialValue: initialValue,
        minLines: 7,
        maxLines: 12,
        disableSuggestions: true,
      ),
    );
  }
}

/// 单行输入对话框（密码 / 口令 / 分组名）。
///
/// `TextEditingController` 必须由对话框**自己**持有并在自己的 `dispose()`
/// 里释放。曾经写成在调用方 `await showDialog(...)` 之后立刻 `dispose()`，
/// 结果是：`showDialog` 的 Future 在路由 pop 的那一刻就完成了，而退出动画
/// 期间对话框仍在树上重建，`TextField` 于是拿到已释放的 controller，抛出
///
///     A TextEditingController was used after being disposed.
///
/// 这个异常会把整个 Overlay 换成 `ErrorWidget`（红底黄字），终端页因此
/// 表现为整屏红色、连快捷键栏都看不见。第 11 轮定位、第 12 轮修复。
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    this.hint,
    this.initialValue,
    this.obscure = false,
    this.selectAll = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.disableSuggestions = false,
  });

  final String title;
  final String? hint;
  final String? initialValue;
  final bool obscure;
  final bool selectAll;
  final int minLines;
  final int maxLines;

  /// 私钥这类内容要关掉自动纠错与联想
  /// （原版 `private_key_prompt_pastepage.xml` 用的是
  /// `textVisiblePassword|textMultiLine`）。
  final bool disableSuggestions;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.selectAll && _controller.text.isNotEmpty) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = JuiceDialogColors.of(context);
    final s = context.s;
    return JuiceAlertDialog(
      title: widget.title,
      contentPadding: JuiceAlertDialog.messageContentPadding,
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autocorrect: !widget.disableSuggestions,
        enableSuggestions: !widget.disableSuggestions,
        style: colors.bodyStyle,
        // 不给装饰时保持 `null`：密码框的实测几何
        // （`[132,749][948,875]`）是在没有 decoration 的情况下量的。
        decoration:
            widget.hint == null ? null : InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(
          label: s('ok'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}
