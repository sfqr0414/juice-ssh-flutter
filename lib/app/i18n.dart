import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 界面文案。
///
/// 数据来自反编译出的原始资源：`assets/i18n/strings_en.json` 对应
/// `res/values/strings.xml`，`strings_zh.json` 对应 `res/values-zh-rCN/strings.xml`。
/// 因此这里的每一条文案都与原版 JuiceSSH 3.2.2 逐字一致，而不是重新翻译的。
class JuiceStrings {
  const JuiceStrings(this._strings, this._fallback);

  final Map<String, String> _strings;
  final Map<String, String> _fallback;

  static const _enAsset = 'assets/i18n/strings_en.json';
  static const _zhAsset = 'assets/i18n/strings_zh.json';

  /// 当前语言的键数量，便于自检。
  int get length => _strings.length;

  /// 取一条文案；缺失时回退到英文，再缺失则回退到键名本身
  /// （键名可见可以让漏翻/漏提取立刻暴露出来，而不是悄悄显示空白）。
  String call(String key) => _strings[key] ?? _fallback[key] ?? key;

  /// 取一条文案并按 Java/Android 的格式串填充参数。
  ///
  /// 支持 `%s`、`%d`、`%f`、`%1$s` 这类位置参数以及 `%%`。
  String format(String key, List<Object?> args) {
    final template = call(key);
    var autoIndex = 0;
    return template.replaceAllMapped(
      RegExp(r'%(?:(\d+)\$)?([sdfx])|%%'),
      (match) {
        if (match.group(0) == '%%') return '%';
        final explicit = match.group(1);
        final index = explicit != null ? int.parse(explicit) - 1 : autoIndex++;
        if (index < 0 || index >= args.length) return match.group(0)!;
        final value = args[index];
        return switch (match.group(2)) {
          'd' => value is num ? value.toInt().toString() : '$value',
          'f' => value is num ? value.toString() : '$value',
          'x' => value is num ? value.toInt().toRadixString(16) : '$value',
          _ => '$value',
        };
      },
    );
  }

  static Future<JuiceStrings> load(Locale locale) async {
    final english = await _readAsset(_enAsset);
    final language = locale.languageCode.toLowerCase();
    if (language == 'zh') {
      // 原版有 zh-rCN / zh-rHK / zh-rTW 三份，这里只提取了 zh-rCN。
      final chinese = await _readAsset(_zhAsset);
      return JuiceStrings(chinese, english);
    }
    return JuiceStrings(english, english);
  }

  static Future<Map<String, String>> _readAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = json.decode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, '$value'));
  }
}

/// 把 [JuiceStrings] 挂到 widget 树上。
class JuiceI18n extends InheritedWidget {
  const JuiceI18n({required this.strings, required super.child, super.key});

  final JuiceStrings strings;

  static JuiceStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<JuiceI18n>();
    assert(scope != null, 'JuiceI18n 未挂载：请检查 main.dart 的根 widget');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(JuiceI18n oldWidget) =>
      oldWidget.strings != strings;
}

extension JuiceStringsContext on BuildContext {
  /// `context.s('connection_new')` 取文案；`context.sf('x', [a])` 带参数。
  JuiceStrings get s => JuiceI18n.of(this);
}
