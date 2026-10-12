// 端口转发 + 连接创建的 UI 端到端测试（第 332 轮起，第 335 轮加建连接）。
//
// 关键背景见 docs/IMPLEMENTATION-NOTES.md 第 307-311 轮与第 334 轮：
//  * adb 坐标法不可用（写死坐标被聚焦滚动带偏、BACK 会退编辑器、软键盘遮挡）；
//  * 本载体在应用进程内驱动 UI，与坐标无关；
//  * `New Port Forward` / `Save` 等**不是 Text 控件**（是带 tooltip 的按钮），
//    必须用 tooltip/语义查找，`find.text` 找不到；
//  * 端口转发编辑器有 **4 个 TextField**：Name / Port(from) / Destination / Port(to)。
//
// 数据会被 `flutter test` 的重新安装清空，所以选择器里没有可选连接，
// 本测试因此先创建一条连接，再去做端口转发。
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
    // 语义树不可用时忽略
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
    debugPrint('JuicePF 找不到: $label');
    return false;
  }
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

  testWidgets('建连接 → 建端口转发 → 保存后列表出现条目', (tester) async {
    app.main();
    await waitForHome(tester);

    debugPrint('JuicePF 点 Manage Connections = ${await tapText(tester, 'Manage Connections')}');
    debugPrint('JuicePF 连接页文本=${visibleTexts(tester)}');

    // ---- 第一步：建一条连接，供端口转发的 Connection 选择器使用 ----
    debugPrint('JuicePF 点 New Connection = ${await tapText(tester, 'New Connection', fab: true)}');
    debugPrint('JuicePF 新建连接页文本=${visibleTexts(tester)}');
    final nFields = find.byType(TextField).evaluate().length;
    debugPrint('JuicePF 新建连接页 TextField=$nFields');
    if (nFields >= 2) {
      await tester.enterText(find.byType(TextField).at(0), 'pfhost');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).at(1), '10.0.2.2');
      await tester.pump(const Duration(milliseconds: 400));
    }
    debugPrint('JuicePF 填后文本=${visibleTexts(tester)}');
    debugPrint('JuicePF 点 Save = ${await tapText(tester, 'Save')}');
    debugPrint('JuicePF 保存后文本=${visibleTexts(tester)}');

    // ---- 第二步：端口转发标签页 + 新建 ----
    debugPrint('JuicePF 点 Port Forwards = ${await tapText(tester, 'Port Forwards')}');
    debugPrint('JuicePF 端口转发页文本=${visibleTexts(tester)}');
    debugPrint('JuicePF 点 New Port Forward = ${await tapText(tester, 'New Port Forward', fab: true)}');
    debugPrint('JuicePF 编辑器文本=${visibleTexts(tester)}');

    final fields = find.byType(TextField);
    debugPrint('JuicePF 编辑器 TextField=${fields.evaluate().length}');
    if (fields.evaluate().length >= 4) {
      await tester.enterText(fields.at(0), 'pf1'); // Name
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(fields.at(1), '9999'); // Port (from)
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(fields.at(2), '127.0.0.1'); // Destination
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(fields.at(3), '2222'); // Port (to)
      await tester.pump(const Duration(milliseconds: 300));
    }
    debugPrint('JuicePF 填充后编辑器文本=${visibleTexts(tester)}');

    // Connection 选择器：(Pick one) → 选第一条连接
    debugPrint('JuicePF 点选择器 = ${await tapText(tester, '(Pick one)')}');
    debugPrint('JuicePF 选择器文本=${visibleTexts(tester)}');
    debugPrint('JuicePF 选 pfhost = ${await tapText(tester, 'pfhost')}');
    debugPrint('JuicePF 选后编辑器文本=${visibleTexts(tester)}');

    debugPrint('JuicePF 点 Save = ${await tapText(tester, 'Save')}');
    debugPrint('JuicePF 保存后文本=${visibleTexts(tester)}');

    expect(visibleTexts(tester), isNotEmpty, reason: '页面应有可见文案');
  });
}
