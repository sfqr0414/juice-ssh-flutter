// 主页面巡屏测试（第 347 轮加入）。
//
// 目的：heroTag 那类缺陷（第 341 轮）不是功能错误，而是**框架层断言** ——
// 只有真的把相关页面走一遍才暴露。这个测试因此不检查业务数据，
// 而是逐个访问主页面/标签页，并在每步显式检查 `tester.takeException()`。
//
// 覆盖：首页 → 设置 → 返回 → 连接管理（Connections / Port Forwards / Identities 三个标签）。
//
// 运行：flutter test integration_test -d emulator-5554

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
  if (f.evaluate().isNotEmpty) return f;
  try {
    f = find.bySemanticsLabel(label);
    if (f.evaluate().isNotEmpty) return f;
  } catch (_) {}
  f = find.text(label);
  if (f.evaluate().isNotEmpty) return f;
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
    debugPrint('SWEEP 找不到: $label');
    return false;
  }
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 900));
  return true;
}

/// 每访问一个页面就检查一次框架异常（heroTag / overflow / assertion 都走这里）。
void checkNoException(WidgetTester tester, String where) {
  final ex = tester.takeException();
  debugPrint('SWEEP $where: exception=${ex == null ? 'none' : ex.toString().split('\n').first}');
  expect(ex, isNull, reason: '$where 出现了框架异常');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('巡屏：首页/设置/连接管理三个标签均无框架异常', (tester) async {
    app.main();
    await waitForHome(tester);
    checkNoException(tester, '首页');

    // 设置页
    debugPrint('SWEEP 进设置 = ${await tapLabel(tester, 'Settings')}');
    checkNoException(tester, '设置页');
    await tapLabel(tester, 'Back');
    await tester.pump(const Duration(seconds: 1));
    checkNoException(tester, '返回首页');

    // 连接管理三个标签
    debugPrint('SWEEP 进连接管理 = ${await tapLabel(tester, 'Manage Connections')}');
    checkNoException(tester, '连接管理-Connections');
    for (final tab in ['Port Forwards', 'Identities', 'Connections']) {
      final ok = await tapLabel(tester, tab);
      debugPrint('SWEEP 切到 $tab = $ok');
      checkNoException(tester, '标签-$tab');
    }
  });
}
