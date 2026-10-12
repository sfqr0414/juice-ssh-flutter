// 端口转发流程的 UI 端到端测试（第 332 轮起，第 334 轮修正查找方式）。
//
// 背景：这条链路此前用 adb 坐标点击，反复失败且失败原因全在手法上
// （写死坐标被聚焦自动滚动带偏、误发 BACK 退出编辑器、软键盘盖住下半屏，
// 见 docs/IMPLEMENTATION-NOTES.md 第 307-311 轮）。现在改在进程内驱动。
//
// 第 334 轮的关键发现：`New Port Forward` 在**语义树**里存在（uiautomator 转储能看到，
// 早期用坐标点它也能打开编辑器），但在**控件树里不是 Text 控件** —— 它是带 tooltip 的
// 按钮，所以 find.text 永远找不到。查找顺序因此改为：
//   tooltip → 语义标签 → 文本 → （可选）FloatingActionButton 类型兜底。
//
// 运行：flutter test integration_test/port_forward_test.dart -d emulator-5554

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juice_ssh_flutter/main.dart' as app;

Future<void> waitForHome(WidgetTester tester) async {
  final inks = find.byType(InkWell);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(Scaffold).evaluate().isNotEmpty && inks.evaluate().length > 3) {
      return;
    }
  }
  fail('首页 30 秒内未就绪');
}

/// 按"tooltip → 语义标签 → 文本 → 类型兜底"的顺序找控件。
Finder finderFor(String label, {bool fab = false}) {
  var f = find.byTooltip(label);
  if (f.evaluate().isNotEmpty) {
    return f;
  }
  try {
    f = find.bySemanticsLabel(label);
    if (f.evaluate().isNotEmpty) {
      return f;
    }
  } catch (_) {
    // 语义树未启用时忽略
  }
  f = find.text(label);
  if (f.evaluate().isNotEmpty) {
    return f;
  }
  if (fab) {
    return find.byType(FloatingActionButton);
  }
  return f;
}

Future<bool> tapText(WidgetTester tester, String label, {bool fab = false}) async {
  var f = finderFor(label, fab: fab);
  for (var i = 0; i < 20; i++) {
    if (f.evaluate().isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 500));
    f = finderFor(label, fab: fab);
  }
  if (f.evaluate().isEmpty) {
    debugPrint('JuicePF 找不到: $label（等待 10 秒后仍未出现）');
    return false;
  }
  debugPrint('JuicePF 命中 $label -> 匹配 ${f.evaluate().length} 个');
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 900));
  return true;
}

List<String> visibleTexts(WidgetTester tester) {
  return find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('端口转发：进入编辑器并打印字段结构', (tester) async {
    app.main();
    await waitForHome(tester);

    debugPrint('JuicePF 点 Manage Connections = ${await tapText(tester, 'Manage Connections')}');
    debugPrint('JuicePF 连接页文本=${visibleTexts(tester)}');

    debugPrint('JuicePF 点 Port Forwards = ${await tapText(tester, 'Port Forwards')}');
    debugPrint('JuicePF 端口转发页文本=${visibleTexts(tester)}');

    debugPrint('JuicePF 点 New Port Forward = ${await tapText(tester, 'New Port Forward', fab: true)}');

    final labels = visibleTexts(tester);
    debugPrint('JuicePF 当前页文本=$labels');
    debugPrint(
      'JuicePF TextFormField=${find.byType(TextFormField).evaluate().length} '
      'TextField=${find.byType(TextField).evaluate().length} '
      'FAB=${find.byType(FloatingActionButton).evaluate().length}',
    );
    debugPrint('JuicePF 有 Save = ${find.text('Save').evaluate().isNotEmpty}');

    expect(labels, isNotEmpty, reason: '页面应有可见文案');
  });
}
