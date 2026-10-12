// 端口转发流程的 UI 端到端测试（第 332 轮起）。
//
// 背景：这条链路此前用 adb 坐标点击，反复失败且失败原因全在手法上
// （写入坐标被聚焦自动滚动带偏、误发 BACK 退出编辑器、软键盘盖住下半屏，
// 见 docs/IMPLEMENTATION-NOTES.md 第 307-311 轮）。现在改在进程内驱动。
//
// 本轮先做到"进入编辑器 + 打印全部文本与输入框数量"，
// 用真实结构定位控件，而不是靠猜坐标或猜 widget 顺序。
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

Future<bool> tapText(WidgetTester tester, String label) async {
  final f = find.text(label);
  if (f.evaluate().isEmpty) {
    debugPrint('JuicePF 找不到文本: $label');
    return false;
  }
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 800));
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

    debugPrint('JuicePF 首页点击 Manage Connections = ${await tapText(tester, 'Manage Connections')}');
    debugPrint('JuicePF 连接页文本=${visibleTexts(tester)}');

    debugPrint('JuicePF 点 Port Forwards 标签 = ${await tapText(tester, 'Port Forwards')}');
    debugPrint('JuicePF 端口转发页文本=${visibleTexts(tester)}');

    debugPrint('JuicePF 点 New Port Forward = ${await tapText(tester, 'New Port Forward')}');

    final labels = visibleTexts(tester);
    final tff = find.byType(TextFormField).evaluate().length;
    final tf = find.byType(TextField).evaluate().length;
    debugPrint('JuicePF 编辑器文本=$labels');
    debugPrint('JuicePF 编辑器 TextFormField=$tff TextField=$tf');
    debugPrint('JuicePF 有 Save = ${find.text('Save').evaluate().isNotEmpty}');

    expect(labels, isNotEmpty, reason: '编辑器应有可见文案');
  });
}
