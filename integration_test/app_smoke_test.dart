// UI 端到端冒烟测试（第 329 轮加入）。
//
// 为什么需要它：端口转发"填表 → 保存 → 运行"这一类的验证此前用 adb 坐标点击，
// 已被证明不可靠 —— 写死坐标会因"聚焦时表单自动滚动"而失效，乱发 BACK 会把编辑器
// 退掉，软键盘还会盖住下半屏（见 docs/IMPLEMENTATION-NOTES.md 第 307-311 轮）。
// 这里改为在应用进程内驱动 UI：用 WidgetTester 直接定位控件并点击，与坐标无关。
//
// 运行方式（需要设备或模拟器）：
//   flutter test integration_test/app_smoke_test.dart -d <device-id>
//
// 断言刻意写得宽松：文案随语言/主题变化，这里只确认"界面真的起来了、
// 关键可点击入口存在、组件树不是空的"，避免脆弱的字符串断言。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juice_ssh_flutter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('冷启动：首页可渲染且关键入口存在', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 8));

    final scaffolds = find.byType(Scaffold);
    final inks = find.byType(InkWell);
    debugPrint(
      'JuiceSmoke: Scaffold=${scaffolds.evaluate().length} '
      'InkWell=${inks.evaluate().length} '
      'widgets=${tester.allWidgets.length}',
    );

    expect(scaffolds, findsWidgets, reason: '至少应有一个 Scaffold');
    expect(
      inks.evaluate().length,
      greaterThan(3),
      reason: '首页应有多张可点击卡片（快捷连接/常用/管理连接/设置…）',
    );
    expect(
      tester.allWidgets.length,
      greaterThan(60),
      reason: '组件数量明显偏少，首页可能是空屏',
    );
  });
}
