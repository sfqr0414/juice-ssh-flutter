"""补丁 v4：把最后 4 处原生 AlertDialog 迁移到 JuiceAlertDialog。

1. connection_editor_screen.dart:1035「选择身份（含排序）」列表对话框
2. connection_editor_screen.dart:1123「分组多选」列表对话框
3. terminal_page.dart:468「后台运行会话」三按钮对话框
4. identity_editor_screen.dart:246「粘贴私钥」多行输入框 —— 这处同时还带着
   与第 12 轮同一个隐患：`.whenComplete(controller.dispose)` 会在路由 pop
   的那一刻释放 controller，而退出动画期间 TextField 仍会重建。

顺带给 `_TextPromptDialog` 增加 minLines/maxLines/disableSuggestions，
并加一个 `JuiceDialogs.promptForPrivateKey()`。

所有锚点先统一校验，全部命中才写文件。
"""

import pathlib
import sys

ROOT = pathlib.Path(r'D:\contribute\juice-ssh-flutter')
LIB = ROOT / 'lib'
DIALOGS = LIB / 'widgets' / 'juice_dialogs.dart'
IDENTITY = LIB / 'screens' / 'identity_editor_screen.dart'
CONNECTION = LIB / 'screens' / 'connection_editor_screen.dart'
PAGE = LIB / 'terminal' / 'terminal_page.dart'

# ---------------------------------------------------------------- dialogs --

DIALOG_EDITS = [
    # 构造参数
    ('''  const _TextPromptDialog({
    required this.title,
    this.hint,
    this.initialValue,
    this.obscure = false,
    this.selectAll = false,
  });

  final String title;
  final String? hint;
  final String? initialValue;
  final bool obscure;
  final bool selectAll;''',
     '''  const _TextPromptDialog({
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
  final bool disableSuggestions;'''),

    # TextField
    ('''      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        style: colors.bodyStyle,''',
     '''      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autocorrect: !widget.disableSuggestions,
        enableSuggestions: !widget.disableSuggestions,
        style: colors.bodyStyle,'''),

    # 新增 promptForPrivateKey（插在 promptForText 之后、类结束之前）
    ('''        selectAll: true,
      ),
    );
  }
}''',
     '''        selectAll: true,
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
}'''),
]

# --------------------------------------------------------------- identity --

IDENTITY_EDITS = [
    ('''  Future<String?> _promptPastePrivateKey() {
    final s = context.s;
    final controller = TextEditingController(text: _identity.privateKey ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s('private_key')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 7,
          maxLines: 12,
          // 与 `private_key_prompt_pastepage.xml` 的
          // `inputType=textVisiblePassword|textMultiLine` 对应：不启用自动纠错/联想。
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: s('paste')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(s('ok')),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }''',
     '''  Future<String?> _promptPastePrivateKey() {
    final s = context.s;
    // 交给 JuiceDialogs：controller 由对话框自己持有并在自己的 dispose 里
    // 释放。这里曾经写成 `.whenComplete(controller.dispose)`，会在路由 pop
    // 那一刻就释放，而退出动画期间 TextField 仍会重建（第 12 轮那个
    // "used after being disposed" 的同类问题）。
    return JuiceDialogs.promptForPrivateKey(
      context,
      title: s('private_key'),
      hint: s('paste'),
      initialValue: _identity.privateKey,
    );
  }'''),
]

# ------------------------------------------------------------- connection --

CONNECTION_EDITS = [
    # 导入
    ("import '../widgets/juice_form.dart';",
     "import '../widgets/juice_alert_dialog.dart';\nimport '../widgets/juice_form.dart';"),

    # 1) 选择身份
    ('    return AlertDialog(\n      title: Text(s(\'choose_an_identity\')),',
     '    return JuiceAlertDialog(\n      title: s(\'choose_an_identity\'),'),
    ('''      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(List<int>.of(_order)),
          child: Text(s('ok')),
        ),
      ],''',
     '''      actions: <Widget>[
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(
          label: s('ok'),
          onPressed: () => Navigator.of(context).pop(List<int>.of(_order)),
        ),
      ],'''),

    # 2) 分组多选
    ('    return AlertDialog(\n      title: Text(s(\'groups\')),',
     '    return JuiceAlertDialog(\n      title: s(\'groups\'),'),
    ('''      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s('cancel')),
        ),
        TextButton(
          // 保持与 `_groups` 的原始顺序，避免每次保存都打乱分组顺序。
          onPressed: () => Navigator.of(context).pop([
            for (final group in widget.groups)
              if (_selected.contains(group.id)) group.id,
          ]),
          child: Text(s('ok')),
        ),
      ],''',
     '''      actions: <Widget>[
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(
          label: s('ok'),
          // 保持与 `_groups` 的原始顺序，避免每次保存都打乱分组顺序。
          onPressed: () => Navigator.of(context).pop([
            for (final group in widget.groups)
              if (_selected.contains(group.id)) group.id,
          ]),
        ),
      ],'''),
]

# ------------------------------------------------------------------- page --

PAGE_EDITS = [
    ("import '../widgets/juice_dialogs.dart';",
     "import '../widgets/juice_alert_dialog.dart';\nimport '../widgets/juice_dialogs.dart';"),
    ('''      builder: (dialogContext) => AlertDialog(
        title: Text(s('background_session')),
        content: Text(s('background_session_battery_warning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: Text(s('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('no'),
            child: Text(s('no')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('yes'),
            child: Text(s('yes')),
          ),
        ],
      ),''',
     '''      barrierColor: JuiceDialogColors.barrier,
      builder: (dialogContext) => JuiceAlertDialog(
        title: s('background_session'),
        content: Text(s('background_session_battery_warning')),
        actions: <Widget>[
          JuiceDialogAction(
            label: s('cancel'),
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
          ),
          JuiceDialogAction(
            label: s('no'),
            onPressed: () => Navigator.of(dialogContext).pop('no'),
          ),
          JuiceDialogAction(
            label: s('yes'),
            onPressed: () => Navigator.of(dialogContext).pop('yes'),
          ),
        ],
      ),'''),
]

FILES = [
    (DIALOGS, DIALOG_EDITS),
    (IDENTITY, IDENTITY_EDITS),
    (CONNECTION, CONNECTION_EDITS),
    (PAGE, PAGE_EDITS),
]

# 先全部校验
texts = {}
for path, edits in FILES:
    text = path.read_text(encoding='utf-8')
    for old, new in edits:
        count = text.count(old)
        if count != 1:
            print(f'!! {path.name}: 期望 1 处，实际 {count} 处 -> {old[:60]!r}')
            sys.exit(1)
        text = text.replace(old, new)
    texts[path] = text
print('全部锚点校验通过')

for path, _ in FILES:
    path.write_text(texts[path], encoding='utf-8')
    print('ok', path.name)
print('补丁 v4 完成')
