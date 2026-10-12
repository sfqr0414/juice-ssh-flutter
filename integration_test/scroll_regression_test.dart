// 普通模式"能否滑屏滚动"的回归验证（第 348 轮加入，第 351-357 轮持续加固）。
//
// 背景：用户报告"普通模式下不能滑屏滚动了"（此前几轮为了让 htop/vim 这类交互式命令
// 在重绘期间禁止滑动，动过拖动设备集合）。代码层逐条排查（clamp / 监听 /
// simulateScroll / dragDevices / Listener / 提示条 GestureDetector）都没能定案，
// 所以这里直接在**进程内量滚动偏移**：拖动前后 `pixels` 变不变，是唯一硬证据。
//
// 为什么最终绕过 UI 建连接：连接编辑器强制先选身份（`You must select an identity`），
// 而 `Identity: Select one...` 的弹层在进程内点不开；首页卡片标题点击也不触发导航。
// 应用的数据层是公开的（`JuiceDatabase.instance` / `saveIdentity` / `saveConnection` /
// `setConnectionIdentities`），所以直接种数据 —— 路径上不再有任何"猜能不能点到"的控件。
//
// 一路踩过的假阳性（本文件存在的意义之一，务必别再犯）：
//   1. `find.textContaining('schost')` 找列表行 → 撞上编辑器里的昵称输入框；
//   2. 拿不到数据时 `return` → 测试空过还报 All tests passed；
//   3. `tap(..., warnIfMissed: false)` → 点空不报错，伪装成成功；
//   4. 拿"能看到 scid"当"弹层已打开" → 匹配页面上任何可见文本，判据无效；
//   5. 点卡片标题 `Text` 不等于点了卡片（首页卡片点击在进程内不导航）；
//   6. 拿"文案集合变了"当"页面变了" → 点击时弹出的 tooltip 就会造成假变化。
//
// 依赖：`python tools/_sshd.py 2222 --many-lines`（连接后吐 60 行，制造可滚历史）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juice_ssh_flutter/data/juice_database.dart';
import 'package:juice_ssh_flutter/data/models.dart';
import 'package:juice_ssh_flutter/main.dart' as app;
import 'package:juice_ssh_flutter/ssh/password_vault.dart';
import 'package:xterm/xterm.dart';

Future<void> waitForHome(WidgetTester tester) async {
  final inks = find.byType(InkWell);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(Scaffold).evaluate().isNotEmpty &&
        inks.evaluate().length > 3) {
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

List<String> visibleTexts(WidgetTester tester) => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .where((s) => s.trim().isNotEmpty)
    .toList();

/// 点可点击祖先（`InkWell`）；没有则点自己。只用于确实会切换页面的控件。
Future<bool> tapTappable(WidgetTester tester, String label, {bool fab = false}) async {
  var f = finderFor(label, fab: fab);
  for (var i = 0; i < 20; i++) {
    if (f.evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 500));
    f = finderFor(label, fab: fab);
  }
  if (f.evaluate().isEmpty) {
    debugPrint('SCROLL 找不到: $label');
    return false;
  }
  final ink = find.ancestor(of: f.first, matching: find.byType(InkWell));
  final target = ink.evaluate().isNotEmpty ? ink.first : f.first;
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 1200));
  return true;
}

/// 只点**列表行**，避开输入框。
Future<bool> tapRow(WidgetTester tester, String label) async {
  var f = find.widgetWithText(ListTile, label);
  for (var i = 0; i < 20; i++) {
    if (f.evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 500));
    f = find.widgetWithText(ListTile, label);
  }
  if (f.evaluate().isEmpty) {
    debugPrint('SCROLL 没有这一行: $label 文案=${visibleTexts(tester).take(20).toList()}');
    return false;
  }
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 900));
  return true;
}

Future<void> dismissDialogs(WidgetTester tester) async {
  // 只在**真的有模态窗**时才动手。
  //
  // 这里是第 17 轮才找到的真凶：等待循环每 500ms 调一次本函数，而下面用的是
  // `finderFor`（最后会退回 `find.textContaining`），标签表里又有 'Connect' ——
  // 终端页连接失败时显示的 `Reconnect`、首页的 `Quick Connect` 全都会被"包含匹配"
  // 命中，于是连接刚建立就被我反复点掉，服务端只看到"客户端自己关了"。
  final modal = find.byType(Dialog).evaluate().length +
      find.byType(AlertDialog).evaluate().length;
  if (modal == 0) return;
  for (final l in const [
    // 首次启动的"允许通知"授权模态窗 —— 它盖在一切之上，会吃掉后续所有点击。
    // 这是前面十几轮"点了没反应"的根因，标签必须放最前面。
    'Allow',
    'ALLOW',
    'Allow notifications',
    '允许',
    '允许通知',
    'Got it',
    '知道了',
    'Agree',
    'Yes',
    'Accept',
    'Connect',
    'OK',
    'Continue',
    'Save',
    '是',
    '接受',
    '连接',
    '确定',
    '继续',
  ]) {
    final f = finderFor(l);
    if (f.evaluate().isEmpty) continue;
    await tester.tap(f.first);
    await tester.pump(const Duration(milliseconds: 600));
    return;
  }
}

/// 打印所有 Scrollable 的滚动指标；返回"有历史"的那个（maxScrollExtent 最大者）。
ScrollableState? terminalScrollable(WidgetTester tester, String tag) {
  final all = find.byType(Scrollable);
  ScrollableState? best;
  final parts = <String>[];
  for (var i = 0; i < all.evaluate().length; i++) {
    final st = tester.state<ScrollableState>(all.at(i));
    final p = st.position;
    parts.add('#$i px=${p.pixels.toStringAsFixed(1)}/max=${p.maxScrollExtent.toStringAsFixed(1)}');
    if (best == null || p.maxScrollExtent > best.position.maxScrollExtent) {
      best = st;
    }
  }
  if (!tag.startsWith('等待')) {
    debugPrint('SCROLL $tag 共${all.evaluate().length}个: ${parts.join(' | ')}');
  }  if (best == null || best.position.maxScrollExtent <= 0) return null;
  return best;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('普通模式：拖动终端应改变滚动偏移', (tester) async {
    app.main();
    // 首次启动的"允许通知"授权弹窗是**自定义 Dialog**，内部没有 Text 控件 ——
    // 所以按文案找按钮注定失败（前面几轮就是栽在这里）。改按结构关：它本质是一个
    // 路由，直接发返回事件让它出栈，并断言真的关掉了才继续。
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      final dialogs = find.byType(Dialog).evaluate().length;
      if (i < 8 || (i % 5 == 0 && dialogs > 0)) {
        debugPrint('SCROLL 启动#$i Dialog=$dialogs 文案=${visibleTexts(tester).take(8).toList()}');
      }
      if (dialogs > 0) {
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 600));
      }
      if (i > 8 &&
          find.byType(Dialog).evaluate().isEmpty &&
          find.byType(Scaffold).evaluate().isNotEmpty) {
        break;
      }
    }
    debugPrint('SCROLL 启动完成 Dialog=${find.byType(Dialog).evaluate().length}');
    if (find.byType(Dialog).evaluate().isNotEmpty) {
      fail('启动时的授权弹窗没能关掉，后续点击都会被它吃掉');
    }
    await waitForHome(tester);

    // 等数据库就绪后直接种数据（跳过编辑器的身份选择弹层）
    JuiceDatabase? db;
    for (var i = 0; i < 20; i++) {
      try {
        db = JuiceDatabase.instance;
        break;
      } catch (_) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
    if (db == null) fail('数据库没有初始化');
    final iid = await db.saveIdentity(
      const Identity(nickname: 'scid', username: 'juice', password: 'juice'),
    );
    final cid = await db.saveConnection(
      const Connection(nickname: 'schost', address: '10.0.2.2', port: 2222),
    );
    await db.setConnectionIdentities(cid, [iid]);
    // 口令必须按**应用自己的方式**存：`saveIdentity` 不落盘口令，凭据在加密口令库里
    // （键 `juicessh.pw.<user>@<host>`）。这是第 21 轮定位到的真因 —— 只种数据库时
    // 会话没有任何可用凭据，dartssh2 会在 TCP 连上后、banner 之前就关闭连接。
    await PasswordVault.write(user: 'juice', host: '10.0.2.2', password: 'juice');
    debugPrint('SCROLL 种数据: identity=$iid connection=$cid 口令已入加密库');

    // 主机密钥存储探测。宿主机探测用**内存实现**能连上，模拟器走
    // `DatabaseHostKeyStore -> _db.knownHost(...)` 却连不上 —— 这是两者唯一实质差异。
    // 如果这里抛异常，根因就是它（且说明真机上"首次连接新主机"都会失败）。
    try {
      final known = await db.knownHost('10.0.2.2');
      debugPrint('SCROLL knownHost 正常，返回=$known');
    } catch (e) {
      debugPrint('SCROLL knownHost 抛异常: $e');
    }
    await tester.pump(const Duration(seconds: 1));

    // 进连接列表（这条导航在端口转发用例里已被证明可用）
    debugPrint('SCROLL 进连接管理 = ${await tapTappable(tester, 'Manage Connections')}');
    await tester.pump(const Duration(seconds: 1));
    var listOk = false;
    for (var i = 0; i < 20; i++) {
      if (find.text('schost').evaluate().isNotEmpty) {
        listOk = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    debugPrint('SCROLL 列表里出现连接 = $listOk 文案=${visibleTexts(tester).take(12).toList()}');
    if (!listOk) {
      fail('点了连接管理但列表里没有种进去的连接（可能仍被遮盖层挡住）');
    }

    // 列表行**不是 ListTile**（本项目用自定义行控件），所以按文案点它的可点击祖先
    final rowOk = await tapTappable(tester, 'schost');
    debugPrint('SCROLL 点连接行 = $rowOk');
    if (!rowOk) fail('种进去的连接没有出现在列表里');

    // 等终端页出现
    var opened = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(TerminalView).evaluate().isNotEmpty) {
        opened = true;
        break;
      }
      await dismissDialogs(tester);
    }
    debugPrint('SCROLL 终端页打开 = $opened');
    if (!opened) {
      debugPrint('SCROLL 当前文案=${visibleTexts(tester).take(25).toList()}');
      fail('点连接后终端页没有出现');
    }

    // 等**会话真正就绪**：轮询"出现可滚历史"。TerminalView 出现只说明终端页打开了，
    // 连接是后台进行的，所以不能拿它当"连上"。
    ScrollableState? st;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      // 应用在**没有已存口令**时会先弹出口令框；不回答它，会话就会因为没有可用认证
      // 方式而被放弃 —— 服务端看到的就是"TCP 连上后客户端立刻关闭"（第 20 轮用宿主机
      // 探测证明了应用 SSH 层本身正常，问题在"没人给它口令"）。
      final promptFields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      if (promptFields.evaluate().isNotEmpty) {
        debugPrint('SCROLL 出现口令框，填入 juice');
        await tester.enterText(promptFields.first, 'juice');
        await tester.pump(const Duration(milliseconds: 300));
        for (final l in const ['OK', 'Connect', 'Save', '连接', '确定', 'Continue']) {
          final f = finderFor(l);
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first);
            debugPrint('SCROLL 口令框按下了 $l');
            break;
          }
        }
        await tester.pump(const Duration(milliseconds: 900));
      }
      await dismissDialogs(tester);
      st = terminalScrollable(tester, '等待#$i');
      if (st != null) {
        debugPrint('SCROLL 历史在第 ${i + 1} 次轮询出现（约 ${(i + 1) * 0.5} 秒）');
        break;
      }
      if (i % 10 == 0) {
        debugPrint('SCROLL 等待#$i 仍无历史');
      }
    }
    if (st == null) {
      debugPrint('SCROLL 一直没历史，当前文案=${visibleTexts(tester).take(25).toList()}');
    }
    st = terminalScrollable(tester, '拖动前');
    if (st == null) {
      fail('终端没有可滚历史（检查探测服务器是否带 --many-lines）');
    }
    final before = st!.position.pixels;
    final max = st.position.maxScrollExtent;

    // 手指上滑 = 看历史
    await tester.drag(find.byType(TerminalView).last, const Offset(0, 240));
    await tester.pump(const Duration(milliseconds: 1000));
    final afterUp = st.position.pixels;
    debugPrint('SCROLL 上滑: $before → $afterUp (max=$max) 有变化=${(afterUp - before).abs() > 1}');

    await tester.drag(find.byType(TerminalView).last, const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 1000));
    debugPrint('SCROLL 下滑: $afterUp → ${st.position.pixels}');

    expect((afterUp - before).abs() > 1, isTrue,
        reason: '普通模式下拖动终端没有改变滚动偏移 —— 就是用户报的滑不动');
  });
}
