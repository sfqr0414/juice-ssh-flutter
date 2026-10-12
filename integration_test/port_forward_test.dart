// 完整创建链路的 UI 端到端测试（第 336 轮）。
//
// 依赖顺序（第 335 轮实测得出）：连接保存强制要求 Identity，
// 所以必须先建身份 → 再建连接 → 才能建端口转发。
//
// 三个关键经验（见 docs/IMPLEMENTATION-NOTES.md 第 307-335 轮）：
//  1. `New Port Forward` / `New Connection` / `Save` 等不是 Text 控件，必须用 tooltip/语义查找；
//  2. 字段值由 EditableText 渲染，`Text` 遍历看不到 —— 断言要用 `find.text()`（也匹配 EditableText）；
//  3. 端口转发编辑器有 4 个 TextField：Name / Port(from) / Destination / Port(to)。
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

/// 从任意位置回到"连接管理"页，再切到指定标签。
/// 第 336 轮实测：保存连接后应用会退回首页，直接找 Port Forwards 标签必然失败。
Future<void> gotoManageTab(WidgetTester tester, String tab) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    if (await tapLabel(tester, tab)) {
      debugPrint('PF 已切到 $tab');
      return;
    }
    // 还没到连接管理页：回首页再进去
    if (!await tapLabel(tester, 'Manage Connections')) {
      await tapLabel(tester, 'Back');
    }
    await tester.pump(const Duration(seconds: 1));
  }
  debugPrint('PF 未能切到 $tab');
}

Finder finderFor(String label, {bool fab = false}) {
  var f = find.byTooltip(label);
  if (f.evaluate().isNotEmpty) return f;
  try {
    f = find.bySemanticsLabel(label);
    if (f.evaluate().isNotEmpty) return f;
  } catch (_) {}
  f = find.text(label);
  if (f.evaluate().isNotEmpty) return f;
  // 第 336 轮教训：选择器里的选项常是复合文案（标题 + 地址副标题），
  // 精确 find.text 匹配不到，这里加一层包含匹配兜底。
  f = find.textContaining(label);
  if (f.evaluate().isNotEmpty) return f;
  if (fab) return find.byType(FloatingActionButton);
  return f;
}

Future<bool> tapLabel(WidgetTester tester, String label, {bool fab = false}) async {
  var f = finderFor(label, fab: fab);
  for (var i = 0; i < 20; i++) {
    if (f.evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 500));
    f = finderFor(label, fab: fab);
  }
  if (f.evaluate().isEmpty) {
    debugPrint('PF 找不到: $label');
    return false;
  }
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 900));
  return true;
}

Future<void> fill(WidgetTester tester, int index, String text) async {
  final fields = find.byType(TextField);
  if (fields.evaluate().length <= index) {
    debugPrint('PF 字段不足: 需要 index=$index 实际=${fields.evaluate().length}');
    return;
  }
  await tester.enterText(fields.at(index), text);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('身份 → 连接 → 端口转发：保存后列表出现新条目', (tester) async {
    app.main();
    await waitForHome(tester);
    await tapLabel(tester, 'Manage Connections');

    // ---- 1. 身份 ----
    debugPrint('PF 点 Identities = ${await tapLabel(tester, 'Identities')}');
    debugPrint('PF 点 New Identity = ${await tapLabel(tester, 'New Identity', fab: true)}');
    debugPrint('PF 身份编辑器 TextField=${find.byType(TextField).evaluate().length}');
    await fill(tester, 0, 'pfid');
    await fill(tester, 1, 'pfuser');
    await fill(tester, 2, 'pfpass');
    debugPrint('PF 点 Save(身份) = ${await tapLabel(tester, 'Save')}');
    debugPrint('PF 身份保存后 = ${find.text('pfid').evaluate().isNotEmpty}');

    // ---- 2. 连接 ----
    debugPrint('PF 点 Connections = ${await tapLabel(tester, 'Connections')}');
    debugPrint('PF 点 New Connection = ${await tapLabel(tester, 'New Connection', fab: true)}');
    debugPrint('PF 连接编辑器 TextField=${find.byType(TextField).evaluate().length}');
    await fill(tester, 0, 'pfhost');
    await fill(tester, 1, '10.0.2.2');
    debugPrint('PF 点 Identity 选择器 = ${await tapLabel(tester, 'Select one...')}');
    debugPrint('PF 选 pfid = ${await tapLabel(tester, 'pfid')}');
    debugPrint('PF 点 Save(连接) = ${await tapLabel(tester, 'Save')}');
    await tester.pump(const Duration(seconds: 2));
    debugPrint('PF 连接列表含 pfhost = ${find.text('pfhost').evaluate().isNotEmpty}');

    // ---- 3. 端口转发 ----
    await gotoManageTab(tester, 'Port Forwards');
    debugPrint('PF 点 New Port Forward = ${await tapLabel(tester, 'New Port Forward', fab: true)}');
    debugPrint('PF 端口转发编辑器 TextField=${find.byType(TextField).evaluate().length}');
    await fill(tester, 0, 'pf1');
    await fill(tester, 1, '9999');
    await fill(tester, 2, '127.0.0.1');
    await fill(tester, 3, '2222');
    debugPrint('PF 点 Connection 选择器 = ${await tapLabel(tester, '(Pick one)')}');
    debugPrint('PF 选 pfhost = ${await tapLabel(tester, 'pfhost')}');
    debugPrint('PF 点 Save(端口转发) = ${await tapLabel(tester, 'Save')}');
    await tester.pump(const Duration(seconds: 2));

    final inList = find.text('pf1').evaluate().isNotEmpty;
    debugPrint('PF 端口转发列表含 pf1 = $inList');
    expect(inList, isTrue, reason: '保存后端口转发列表应出现 pf1');
  });
}
