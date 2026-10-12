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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juice_ssh_flutter/app/settings_controller.dart';
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
      find.byType(AlertDialog).evaluate().length +
      // 自定义弹窗（`JuiceAlertDialog`）不会被 `byType(Dialog)` 命中，而主机密钥
      // 确认框里有 `SelectableText`，拿它当可靠标记 —— 第 31 轮的教训：门闩漏判
      // 会让弹窗既不被处理、也不被发现，于是连接空等到超时。
      find.byType(SelectableText).evaluate().length;
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
    // 主机密钥确认框的按钮是**大写** `ACCEPT`。`Accept` 匹配不到它（区分大小写），
    // 于是弹窗一直留在屏幕上、回调永不返回、SSH 空等到 30 秒超时 —— 第 37 轮定位。
    'ACCEPT',
    "OK - I've got it!", // 终端首次进入的教程框会压在确认框下面，先点掉它
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

    // 教程覆盖层（`ColoredBox` 黑色 70%，**整屏吸收指针**）会盖住终端：第 51-66 轮
    // 那批"探针 0 次 / 拖动无效"全部是它造成的（用户也确认它会正常出现）。
    // 这里在种数据阶段直接把"教程已看"写掉，让覆盖层根本不出现，测量通道才可用。
    await SettingsController.instance.setTerminalTutorialSeen(true);
    print('SCROLL 教程已看=${SettingsController.instance.terminalTutorialSeen}');
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
    // 教程覆盖层（`_showTutorial` → `_TerminalTutorial`，与终端**同 Stack 的兄弟**
    // `Positioned.fill`）会盖住整个终端，指针全落在它上面 —— 这正是"终端明明在页面
    // `Listener` 之下、内联探针却一次都不触发"的原因（第 61 轮定位）。
    // 这里按**匹配数量**逐个点掉，不再假设只有一个同名文案。
    final tip = find.text("OK - I've got it!");
    print('SCROLL 教程按钮匹配数 = ${tip.evaluate().length}');
    for (var guard = 0; guard < 4 && tip.evaluate().isNotEmpty; guard++) {
      // 先点按钮，再点屏幕中部：教程层多半整屏可点关闭。两者都试，只要有一处生效，
      // 覆盖层就会消失（`剩余=0`），指针才能落到终端上。
      await tester.tap(tip.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      if (tip.evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(205, 434));
        await tester.pump(const Duration(milliseconds: 300));
      }
      print('SCROLL 点掉教程层第 ${guard + 1} 次，剩余=${tip.evaluate().length}');
    }

    // 注入窗口：给宿主留出时间用 `adb shell input swipe` 注入**真实触摸**。
    // 夹具手势到不了页面 `Listener`（第 51-56 轮反复证实），所以触摸滑动的判定
    // 只能靠系统级注入；这里只推进帧、不做任何交互。
    debugPrint('SCROLL 注入窗口开始（30 秒）');
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint('SCROLL 注入窗口结束');

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
        for (final l in const [
          'ACCEPT', // 主机密钥确认框的按钮是大写 `ACCEPT`（`Accept` 匹配不到，区分大小写）
          "OK - I've got it!", // 终端首次进入的教程框，会压在确认框下面
          'OK',
          'Connect',
          'Save',
          '连接',
          '确定',
          'Continue',
          'Accept',
        ]) {
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
      if (i % 5 == 0) {
        // 不再截断文案：主机密钥确认框的文字很可能排在第 8 条之后（终端页的
        // 快捷键栏就有十几条），上一版 `take(8)` 把关键证据藏掉了。
        final all = visibleTexts(tester);
        debugPrint('SCROLL 等待#$i 仍无历史 文案共${all.length}条=$all '
            'SelectableText=${find.byType(SelectableText).evaluate().length} '
            'TextButton=${find.byType(TextButton).evaluate().length}');
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

    // 手指上滑 = 看历史。**分帧读取**：如果是"先移动、随后被拉回底部"，
    // 中间这几帧就能把回弹抓个正着（第 40 轮的决定性实验）。
    // 拖动目标必须是**终端自己的 `Scrollable`**（`terminalScrollable` 选的就是
    // `maxScrollExtent` 最大的那个 = index 0）。此前用 `find.byType(TerminalView).last`
    // 拖了个空 —— 命中警告被过滤掉，于是"拖不动"这个假象骗了好几轮。
    // 用**矩形重合**锁定终端那个 `Scrollable`：按 `maxScrollExtent` 猜会把底部键位条
    // （横向滚动，范围恰好也是几百像素）当成终端 —— 第 54 轮就是这么被绕住的。
    final tvRect = tester.getRect(find.byType(TerminalView));
    final scAll = find.byType(Scrollable);
    ScrollableState? terminalState;
    for (var i = 0; i < scAll.evaluate().length; i++) {
      final s = tester.state<ScrollableState>(scAll.at(i));
      final rect = tester.getRect(scAll.at(i));
      final pos = s.position;
      debugPrint('SCROLL  SC#$i axis=${pos.axis} rect=$rect '
          'max=${pos.maxScrollExtent.toStringAsFixed(1)} '
          'px=${pos.pixels.toStringAsFixed(1)}');
      if (pos.axis == Axis.vertical &&
          rect.top >= tvRect.top - 1 &&
          rect.bottom <= tvRect.bottom + 1) {
        terminalState = s;
      }
    }
    if (terminalState == null) {
      fail('没找到与 TerminalView 重合的纵向 Scrollable');
    }
    final beforeT = terminalState.position.pixels;
    final maxT = terminalState.position.maxScrollExtent;
    debugPrint('SCROLL 终端视口: px=${beforeT.toStringAsFixed(1)} '
        'max=${maxT.toStringAsFixed(1)}');

    // 必须拖**我实测的那一个** `Scrollable`：此前写死 `find.byType(Scrollable).at(0)`
    // 是树序第一个（多半是底部键位条那个 `max=0` 的），与测量对象不是同一个 ——
    // 于是"拖动无效"是个纯夹具错误（第 54 轮用它解释了"按下事件 0 行"）。
    // 屏幕上那份终端是否真在页面 `Listener` 的子树里？用 key 判定 ——
    // 数 `find.byType(Listener)` 会被 Flutter 内部的 Listener 骗到（第 59 轮的教训）。
    final underPageListener = find
        .ancestor(
          of: find.byType(TerminalView),
          matching: find.byKey(const ValueKey<String>('juice-terminal-listener')),
        )
        .evaluate()
        .length;
    debugPrint('SCROLL 终端在页面 Listener 之下 = ${underPageListener > 0}');

    // 直接读出"终端中心这个点被谁接收"（第 65 轮）：不再靠推断定位拦截层。
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      tester.getCenter(find.byType(TerminalView)),
      tester.view.viewId,
    );
    for (final entry in hit.path) {
      print('SCROLL HIT ${entry.target.runtimeType}');
    }

    final terminalFinder = find.byWidget(terminalState.widget);
    // 手工指针序列：`tester.drag` 是**单步**位移，而拖动识别器需要一串越过
    // `kTouchSlop` 的 move 事件。用接近真手指的节奏复测，排除夹具假象
    // （本 session 已被 .last 拖空 / "Accept" 大小写 / take(8) 截断坑过三次）。
    final gesture = await tester.startGesture(tester.getCenter(terminalFinder));
    await tester.pump(const Duration(milliseconds: 20));
    for (var k = 0; k < 12; k++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    final afterDrag = st.position.pixels;
    await tester.pump(const Duration(milliseconds: 16));
    final after1 = st.position.pixels;
    await tester.pump(const Duration(milliseconds: 200));
    final after2 = st.position.pixels;
    await tester.pump(const Duration(milliseconds: 800));
    final afterUp = st.position.pixels;
    debugPrint('SCROLL 上滑: $before → 拖动结束=$afterDrag → +16ms=$after1 '
        '→ +200ms=$after2 → +1s=$afterUp (max=$max) 有变化=${(afterUp - before).abs() > 1}');

    await tester.drag(terminalFinder, const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 1000));
    debugPrint('SCROLL 下滑: $afterUp → ${st.position.pixels}');

    // 注意：这里**不能**再做程序化 `jumpTo` 实验。第 50 轮它被放在断言之前，
    // 把"离底距离"直接推成整个 `max`，于是测试以错误的理由变绿 —— 假阳性。
    // 程序化可滚这一事实已在第 42 轮验证并记录，无需每次运行重复。
    // 判据必须用"离底距离"，不能用 `pixels` 的绝对差：贴底时键盘/教程层改变布局
    // 会把 `maxScrollExtent` 抬高，`pixels` 跟着涨 —— 那是"仍然贴底"，不是滚动，
    // 第 46/47 轮就是被这个假阳性骗过（读到 695.8 > max=384.5）。
    final beforeFromBottom = maxT - beforeT;
    final afterFromBottom =
        terminalState.position.maxScrollExtent - terminalState.position.pixels;
    debugPrint('SCROLL 离底距离: $beforeFromBottom → $afterFromBottom '
        '(越大说明越早的历史可见)');

    expect(afterFromBottom > beforeFromBottom + 1, isTrue,
        reason: '普通模式下拖动终端没有增加可见历史 —— 就是用户报的滑不动');
  });
}
