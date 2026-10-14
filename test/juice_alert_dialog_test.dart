// 第 35 轮：把"主机密钥确认框弹不出来"这件事拿到秒级环境里复现。
//
// 现场证据链（模拟器侧）：质询到达 → 确认回调已挂 → 页面回调进入（mounted=true）
// → `showDialog(JuiceAlertDialog(...))` 的 future **永不完成** → SSH 层空等 30 秒
// → UI 报"连接超时"。同一次运行里框架还抓到过
// `building LayoutBuilder: RenderBox was not laid out … Failed assertion: 'hasSize'`。
//
// 这里用最小 MaterialApp 直接弹同一个控件：若断言在这里就复现，就能拿到带应用源码
// 帧的完整堆栈，省掉"改一行等 90 秒模拟器"的循环。
//
// 运行：flutter test test/juice_alert_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_ssh_flutter/app/juice_colors.dart';
import 'package:juice_ssh_flutter/app/juice_theme.dart';
import 'package:juice_ssh_flutter/widgets/juice_alert_dialog.dart';

void main() {
  testWidgets('showDialog 弹出 JuiceAlertDialog 不应抛异常且能返回', (tester) async {
    // **必须套 `JuicePaletteScope`**（第 350 轮修）：`JuiceAlertDialog` 通过
    // `JuiceDialogColors.of` → `context.palette` 取调色板，而 `JuicePaletteScope.of`
    // 有 `assert(scope != null, 'JuicePaletteScope 未挂载：请检查 app.dart 的根 widget')`。
    // 这个用例写于该依赖引入之前，只套了裸 `MaterialApp`，于是弹窗一 build 就抛断言、
    // 控件树里没有 SelectableText —— 看起来像"弹窗构建失败"，其实是**测试缺了根 widget**。
    await tester.pumpWidget(
      JuicePaletteScope(
        palette: JuicePalette.dark,
        child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => JuiceAlertDialog(
                    title: 'host_verification',
                    contentPadding: JuiceAlertDialog.messageContentPadding,
                    content: const SingleChildScrollView(
                      child: SelectableText('this is the first time'),
                    ),
                    actions: <Widget>[
                      JuiceDialogAction(
                        label: 'reject',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      JuiceDialogAction(
                        label: 'accept',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 弹窗必须真的在控件树里（主机密钥确认框里有 SelectableText）。
    expect(find.byType(SelectableText), findsOneWidget,
        reason: '弹窗构建失败时它不会出现在控件树里');
    expect(tester.takeException(), isNull, reason: '构建弹窗不应产生框架异常');

    // 按钮文案是**大写**：`JuiceDialogAction` 内部走 `label.toUpperCase()`
    // （juice_alert_dialog.dart:384），与原版 Android 对话框的按钮一致。
    await tester.tap(find.text('ACCEPT'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing, reason: '点接受后弹窗应关闭');
  });
}
