import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../app/i18n.dart';
import '../app/juice_colors.dart';
import '../app/settings_controller.dart';
import '../app/system_ui.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../ssh/ssh_service.dart';
import '../widgets/juice_alert_dialog.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_popup_menu.dart';
import 'bell_notifications.dart';
import 'hardware_keys.dart';
import 'escape_characters.dart';
import 'hacker_keyboard.dart';
import 'terminal_pickers.dart';
import 'session_host.dart';
import 'terminal_session.dart';

/// SSH 终端会话页面。
///
/// 对应原版 `TerminalEmulatorActivity`。还原了：
/// * 黄色 ActionBar，标题为连接昵称（远端用转义序列设置过标题则优先用它）；
/// * 建连期间显示 `@drawable/loading_screen` 的径向渐变加进度提示；
/// * 终端主体 + **70dp** 额外键行，位置由 `terminal:keyboard_position` 决定
///   （0 上方 / 1 下方 / 2 不显示，默认 1）；
/// * **长按终端**弹出标题为 `terminal`（Terminal）的上下文菜单，
///   条目与原版 `registerForContextMenu` 注册的一致；
/// * 按返回键弹出 `background_session` 三选提示（是 / 否 / 取消），
///   对应原版 `BackgroundPrompt`；
/// * 文本选择提示条，背景分别用原版的
///   `copy_instructions_start_selection_background`（红 #F44336）与
///   `copy_instructions_end_selection_background`（绿 #4CAF50）。
///
/// **一处已实测确认的偏差**：原版终端页只有长按上下文菜单、没有 ActionBar 溢出菜单，
/// 这里额外保留了一个溢出按钮。
///
/// 第 28 轮在模拟器上实测：对终端中部做 900ms 长按
/// （`input swipe 540 900 540 900 900`）之后 `dumpsys input_method` 报
/// `mInputShown=true`，画面变化是系统键盘（浅色面板自 y≈1500 起、含 8 行按键文字），
/// **没有**弹出上下文菜单 —— 长按被 `TerminalView` 自身的手势识别吃掉了
/// （点按聚焦 → 弹键盘）。原版是 `registerForContextMenu(terminalView)`
/// （`TerminalEmulatorActivity.smali:2761`），长按能正常弹菜单，所以这是真实的行为差异。
/// 结论：这个溢出按钮目前是**承重**的，不能按原计划删除；要恢复 1:1，先得让长按
/// 真正可达（例如用裸指针按下计时，在 xterm 之前抢到长按）。
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.connection,
    required this.identities,
    this.snippet,
    this.portForwards = const <PortForward>[],
  });

  final Connection connection;

  /// 该连接配置的身份，按尝试顺序。
  final List<Identity> identities;

  /// 连接成功后自动执行的片段（来自 `connection.snippetId`）。
  final Snippet? snippet;

  /// 挂在 `portforward.connection` 上的端口转发，会话建立后自动启动。
  final List<PortForward> portForwards;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final TerminalSessionController _controller;

  /// 终端页自己的状态栏底色（当前终端配色的 ANSI 0），以及离开时要交还的
  /// 应用配色底色。
  ///
  /// **为什么不用 `systemOverlayStyle` 设底色**：设备实测（模拟器 API 36 +
  /// Flutter 3.47.7）里 Flutter 侧 `statusBarColor` 不生效 —— 颜色探针（主题级设
  /// 纯红、终端页设纯绿）截图后，主界面/通讯录/终端三个页面状态栏全是 Android
  /// 主题里的黄色 `(240,210,53)`，红与绿都没出现；原因是 Flutter 默认使用
  /// `SystemUiMode.edgeToEdge`。而直接设窗口属性有效：原版终端页实测 y0..127 =
  /// `(7,54,66)` = 终端配色的 ANSI 0。详见 `lib/app/system_ui.dart`。
  Color? _terminalStatusBarColor;
  Color? _appStatusBarColor;

  /// 把状态栏切成当前终端配色的 ANSI 0；颜色没变时不重复过通道。
  void _syncStatusBar() {
    if (!mounted) return;
    _appStatusBarColor = Theme.of(context).primaryColor;
    // 状态栏底色取**终端配色自己的背景色**（就是 `TerminalView` 画出来的那块画布色），
    // 于是状态栏与终端连成一片（用户要的"沉浸"）。
    // 此前取的是 ANSI 0（`surfaceTheme.black`，比画布深一档 = `#073642` vs `#254E59`），
    // 用户实测："状态栏就是比终端颜色深，要状态栏颜色和终端一致，沉浸"。
    final target = _controller.surfaceTheme.background;
    if (_terminalStatusBarColor == target) return;
    _terminalStatusBarColor = target;
    // 底色深时用白色图标（原版该带内非底色像素只有 `(255,255,255)`）。
    JuiceSystemUi.setStatusBar(
      target,
      lightIcons: target.computeLuminance() > 0.5,
    );
  }
  final TerminalController _terminalController = TerminalController();
  final FocusNode _terminalFocus = FocusNode();

  /// `Toggle Keyboard` 键维护的软键盘显隐状态（理由见 `_toggleSoftKeyboard`）。
  bool _softKeyboardVisible = false;

  /// 上一次看到的会话状态，用来识别"刚连上"这个瞬间（原版连上就自动弹输入法）。
  TerminalSessionState? _lastSessionState;

  /// 终端内层 `Scrollable` 的控制器（传给 `TerminalView.scrollController`）。
  /// 用来在**视口尺寸变化**后把位置重新贴底：xterm 的 `_stickToBottom` 只用
  /// `correctBy(_maxScrollExtent - _scrollOffset)` 修正，实测会残留几个像素的
  /// 分数偏移 —— 旋转屏幕后首行墨迹从 135 掉到 128（= 内容整体上移、被状态栏切掉），
  /// 用户报的"终端屏幕旋转内容显示不正常"就有这一份。直接 `jumpTo(maxScrollExtent)`
  /// 才能对齐。
  final ScrollController _terminalScroll = ScrollController();

  /// 用户当前是否贴在底部（没在翻历史）。只有贴底时才在尺寸变化后重新贴底。
  bool _terminalStuckToBottom = true;

  /// 弹窗键盘（原版 `hacker_keyboard.xml` 那两行键位）是否可见。
  ///
  /// 原版语义有内置教程为证：中文「点击终端以显示弹出键盘，该键盘拥有常用的特殊按键
  /// (比如 Ctrl、方向键等)」/ 英文 "Tap the terminal to bring up a popup keyboard
  /// with all the normally hard to find characters (ctrl, arrows etc)" ——
  /// 也就是说**点终端**才是弹窗键盘的开关。此前键位条常显、点终端毫无反应，
  /// 就是用户实测的第 2 条「终端点击没有切换黑客键盘弹出/隐藏状态」。
  bool _popupKeyboardVisible = true;

  /// 本次按压的起始时刻：只有"短按"才算轻点（用户实测第 2 条要求
  /// 点终端切换弹出键盘，但长按是弹上下文菜单，绝不能同时切换键盘）。
  DateTime? _pressStartedAt;

  /// 上下文菜单是否正开着（用于屏蔽菜单期间那次抬手被当成轻点）。
  bool _contextMenuOpen = false;

  /// 上一次打出的几何诊断行，用来只在数值变化时输出（定位终端顶部偏移用）。
  String? _lastGeometry;

  /// 额外键行是否停在功能键页。
  bool _showingFunctionKeys = false;

  /// 是否处于「选择起点 / 终点」的两段式复制流程。
  bool _selectingStart = false;
  bool _selectingEnd = false;

  /// 两段式选择时自己维护的选区锚点。
  ///
  /// 本来指望 `TerminalView` 自己的长按拖动扩选，但 xterm 4.0.0 的
  /// `TerminalView` **没有任何触摸选区手势**（`_onTapDown` 只清选区/弹键盘），
  /// 所以"拖到起点/终点"必须由本页把像素换算成单元格后调用
  /// `TerminalController.setSelection()`。
  CellOffset? _copyAnchor;

  /// 终端控件最近一次布局的逻辑尺寸，用于像素 → 单元格换算。
  Size? _terminalLayoutSize;

  /// 终端控件左上角在屏幕上的逻辑 y（构建时刷新），用于和首行墨迹对账。
  double? _terminalBoxTop;

  /// Scaffold 之外读到的真实状态栏高度（构建时刷新），诊断用。
  double? _outerTopInset;

  /// 首次进终端时叠在最前面的教程层。
  ///
  /// 原版 `TerminalEmulatorActivity.j(Bundle)` 里读 `tutorial:terminal`：值存在且
  /// `parseBoolean` 为 false 时把 `tutorial_terminal.xml` 这一层挂到根布局最前；
  /// 点 `@id/tutorial_button` 先写回字符串 "true" 再移除这一层
  /// （`TerminalEmulatorActivity$k.onClick`）。该键的默认值由 `Config` 播种为 false，
  /// 所以**首次打开终端一定会看到教程**，点过之后不再出现。
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    _showTutorial = !SettingsController.instance.terminalTutorialSeen;
    // 会话归 SessionHost 所有，页面只**附着**。已经有活动会话时直接接上
    // （原版从通知栏回到终端也是这个语义），不再重复建连。
    final acquired = SessionHost.instance.acquire(widget.connection.id, () {
      return TerminalSessionController(
        connection: widget.connection,
        identities: widget.identities,
        hostKeyStore: DatabaseHostKeyStore(JuiceDatabase.instance),
        settings: SettingsController.instance,
        portForwards: widget.portForwards,
      );
    });
    _controller = acquired.controller;
    // 交互式回调只能由「当前附着的页面」提供；脱离时置空，
    // 后台会话遇到主机密钥/密码质询一律按拒绝处理。
    _controller.onHostKeyChallenge = (challenge) async {
      // 诊断（第 33 轮）：区分"回调没进来/未 mounted"与"卡在弹窗里"。
      debugPrint('JuiceSshHandler: 页面回调进入 mounted=$mounted');
      if (!mounted) return HostKeyVerdict.rejected;
      // ignore: avoid_print
      final verdict = await JuiceDialogs.confirmHostKey(context, challenge);
      debugPrint('JuiceSshHandler: 弹窗返回 $verdict');
      return verdict;
    };
    _controller.onPasswordPrompt = (prompt, echo) async {
      if (!mounted) return null;
      return JuiceDialogs.promptForSecret(context, prompt: prompt, echo: echo);
    };
    // 只有 `terminal:bell_mode = 2`（show_notification）才会走到这里；
    // 0（关闭）/ 1（震动）在 TerminalSessionController._handleBell 里就分派完了。
    _controller.onBell = () {
      BellNotifications.show(
        title: context.s('terminal_bell'),
        single: context.s('terminal_bell_received'),
        multiple: context.s('x_terminal_bells'),
      );
    };
    _controller.addListener(_onSessionChanged);
    // 记录用户是否贴在底部：只有贴底时才在视口尺寸变化后重新贴底，
    // 用户在翻历史时不要被打断。
    _terminalScroll.addListener(() {
      if (!_terminalScroll.hasClients) return;
      final position = _terminalScroll.position;
      _terminalStuckToBottom = position.pixels >= position.maxScrollExtent - 1;
    });
    // 原版音量键改字号（`dispatchKeyEvent` keycode 24/25）需要原生侧拦截，
    // 只在终端页声明「当前在前台」时才拦截。重新附着到已有会话时也要声明，
    // 所以放在这里而不是下面的 `acquired.created` 分支里。
    HardwareKeys.handleVolumeKey(_controller.adjustFontSize);
    HardwareKeys.setVolumeKeysActive(true);
    // 终端几何采样：首帧时终端往往还是 xterm 的默认 80×24（此时服务端横幅
    // 可能已经写进来了 —— logcat 里 `JuiceSshBell` 就早于首帧两毫秒），
    // 所以只在首帧采样会看不到 resize 之后的真实行列数。这里再补一次延迟采样。
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final terminal = _controller.terminal;
      debugPrint(
        'JuiceSshGeom(delayed): box=${_terminalLayoutSize?.width.toInt()}x'
        '${_terminalLayoutSize?.height.round()} '
        'boxTop=${_terminalBoxTop?.toStringAsFixed(1)} '
        'cols=${terminal.viewWidth} rows=${terminal.viewHeight} '
        'lines=${terminal.buffer.lines.length} '
        'cursorY=${terminal.buffer.absoluteCursorY} '
        'fontSize=${_controller.textStyle.fontSize} '
        'popupKeys=$_popupKeyboardVisible '
        'scrollback=${terminal.buffer.lines.length - terminal.viewHeight}',
      );
    });
    if (acquired.created) {
      // 建连过程可能弹对话框，等首帧渲染完再开始，避免在 initState 期间弹窗。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 通知文案要本地化，只能在这里（有 BuildContext）取。
        _controller.disconnectLabel = context.s('disconnect');
        // 响铃计数是「这次连接」的概念，新会话开始时清零。
        BellNotifications.reset();
        _start();
      });
    }
  }

  /// 点教程底部按钮 "OK - I've got it!"：先写 `tutorial:terminal = true`，
  /// 再移除这一层，顺序与原版 `TerminalEmulatorActivity$k.onClick` 一致。
  Future<void> _dismissTutorial() async {
    await SettingsController.instance.setTerminalTutorialSeen(true);
    if (!mounted) return;
    setState(() => _showTutorial = false);
  }

  Future<void> _start() async {
    await _controller.connect();
    if (!mounted) return;
    if (_controller.state == TerminalSessionState.connected) {
      // 使用次数 +1。
      //
      // 时机与原版一致：原版把计数写在传输链建立成功之后 ——
      // `ConnectionCounter;->s(Connection, Context)`（模型里就是"有行则 count+1，
      // 无行则新建 count=1"），调用点是 `TransportChain`（反编译为 `ai0`）里
      // `r()` 派发的 Runnable。失败的尝试不计入，这样首页「常用连接」与
      // `connected_once` / `connected_twice` / `connected_x_times` 才有意义的来源；
      // 计数器一直没人写的话，列表会永远显示 `not_used`。
      await JuiceDatabase.instance
          .incrementConnectionCounter(widget.connection.id);
      final snippet = widget.snippet;
      if (snippet != null && snippet.content.isNotEmpty) {
        _controller.runSnippet(snippet.content);
      }
    }
  }

  void _onSessionChanged() {
    // 会话中也能改终端配色（长按菜单），状态栏要跟着走。
    _syncStatusBar();
    // 原版连上终端就自动把输入法顶出来（用户实测："连接成功进终端页面会自动弹出
    // 输入键盘，表示用户可以输入命令了"）。只在 `connecting → connected` 这个
    // 跃迁上做：从通知栏回到一个**已经在跑**的会话（首次通知时状态就是 connected）
    // 不该平白弹出键盘。
    final state = _controller.state;
    final previous = _lastSessionState;
    _lastSessionState = state;
    if (previous == TerminalSessionState.connecting &&
        state == TerminalSessionState.connected) {
      unawaited(_showSoftKeyboard());
      // 连上之后**再补一次重绘**：远端常在 shell 刚起来时立刻切备用屏（vi/vim/htop），
      // 那段内容可能落在布局/尺寸变化的窗口里丢掉重绘（第 268 轮实测备用屏整片空白）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _clampTerminalScroll();
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    // 只「脱离」，不销毁会话 —— 会话由 SessionHost 持有。
    // 返回键选「保持后台」时界面销毁而会话（含端口转发）继续跑，
    // 这也正是通讯录里那个转发开关能跨页面生效的前提。
    _controller.removeListener(_onSessionChanged);
    _controller.onHostKeyChallenge = null;
    _controller.onPasswordPrompt = null;
    _controller.onBell = null;
    HardwareKeys.handleVolumeKey(null);
    HardwareKeys.setVolumeKeysActive(false);
    _terminalController.dispose();
    _terminalFocus.dispose();
    _terminalScroll.dispose();
    // 状态栏交还给应用配色：终端自己的底色只属于这个页面。
    final restore = _appStatusBarColor;
    if (restore != null) {
      JuiceSystemUi.setStatusBar(restore);
    }
    super.dispose();
  }

  // ---------------------------------------------------------- 复制 --

  /// "Copy (whole session)" —— 整段回滚缓冲（10000 行）。
  String get _wholeSession => _controller.bufferText;

  /// "Copy (from screen)" —— 有选区就复制选区，否则复制当前可见区。
  String get _fromScreen {
    final selection = _terminalController.selection;
    final buffer = _controller.terminal.buffer;
    if (selection != null) {
      return buffer.getText(selection);
    }
    final height = buffer.height;
    final viewHeight = _controller.terminal.viewHeight;
    final top = (height - viewHeight).clamp(0, height);
    if (top >= height) return buffer.getText();
    final range = BufferRangeLine(
      CellOffset(0, top),
      CellOffset(_controller.terminal.viewWidth - 1, height - 1),
    );
    return buffer.getText(range);
  }

  Future<void> _copyToClipboard(String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    // 原版复制成功用 Toast，文案 `text_copied_to_clipboard`。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.s('text_copied_to_clipboard'))),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.paste(text);
  }

  /// 终端内边距（逻辑像素）：选择态用 `terminal:margin_selection`（原版行为）。
  double get _terminalMargin {
    final settings = SettingsController.instance;
    final selecting = _selectingStart || _selectingEnd;
    final value = selecting && settings.terminalMarginSelection > 0
        ? settings.terminalMarginSelection
        : settings.terminalMargin;
    return value.toDouble();
  }

  /// 把终端控件内的本地像素坐标换算成终端单元格。
  ///
  /// 口径与 xterm 一致：可视高度 = 控件高度 - 上下 padding，
  /// 行高 = 可视高度 / `viewHeight`；贴底显示时可视区第一行是
  /// `lines.length - viewHeight`。
  CellOffset? _cellAt(Offset local) {
    final size = _terminalLayoutSize;
    if (size == null) return null;
    final terminal = _controller.terminal;
    final buffer = terminal.buffer;
    if (terminal.viewWidth <= 0 || terminal.viewHeight <= 0) return null;
    final lineCount = buffer.lines.length;
    if (lineCount <= 0) return null;
    final margin = _terminalMargin;
    final cellWidth = (size.width - margin * 2) / terminal.viewWidth;
    final cellHeight = (size.height - margin * 2) / terminal.viewHeight;
    if (cellWidth <= 0 || cellHeight <= 0) return null;
    final firstVisible =
        lineCount > terminal.viewHeight ? lineCount - terminal.viewHeight : 0;
    final column = ((local.dx - margin) / cellWidth)
        .floor()
        .clamp(0, terminal.viewWidth - 1);
    final row = (firstVisible + ((local.dy - margin) / cellHeight).floor())
        .clamp(0, lineCount - 1);
    return CellOffset(column, row);
  }

  /// 按当前锚点 + 手指所在单元格刷新选区。
  ///
  /// 颜色由主题的 `selection` 决定，已经改成原版的红色（`#FFF44336`）。
  void _applyCopySelection(CellOffset? cell) {
    if (cell == null) return;
    final anchor = _copyAnchor ?? cell;
    _copyAnchor = anchor;
    final buffer = _controller.terminal.buffer;
    _terminalController.setSelection(
      buffer.createAnchorFromOffset(anchor),
      buffer.createAnchorFromOffset(cell),
    );
  }

  /// "Copy (from screen)" 的两段式选择流程。
  ///
  /// 原版先进入选择模式并提示「拖到选区起点」，再提示「拖到选区终点」，
  /// 期间终端边距会放宽到 `terminal:margin_selection` 以便选到边缘字符。
  void _beginScreenCopy() {
    setState(() {
      _selectingStart = true;
      _selectingEnd = false;
    });
    _copyAnchor = null;
    _terminalController.clearSelection();
  }

  void _advanceScreenCopy() {
    if (_selectingStart) {
      setState(() {
        _selectingStart = false;
        _selectingEnd = true;
      });
      return;
    }
    if (_selectingEnd) {
      // 先取出文本，再**收起选区**：原版复制完成后即退出选择模式，选区高亮消失
      // （用户实测"选择完成应该重置选择状态，完成复制"）。
      final text = _fromScreen;
      setState(() {
        _selectingStart = false;
        _selectingEnd = false;
      });
      _terminalController.clearSelection();
      _copyAnchor = null;
      _copyToClipboard(text);
    }
  }

  void _cancelScreenCopy() {
    setState(() {
      _selectingStart = false;
      _selectingEnd = false;
    });
    _copyAnchor = null;
    _terminalController.clearSelection();
  }

  // ---------------------------------------------------------- 键盘 --

  Future<void> _toggleSoftKeyboard() async {
    // 真实状态**从原生侧查**（`WindowInsets.isVisible(ime())`）。
    //
    // 之前两种 Dart 侧判断都不可靠，用户实测"点了没反应"：
    //   * 看 `_terminalFocus.hasFocus` —— 那个隐藏输入框长期持有焦点，于是永远走
    //     "收起"分支，弹不出来；
    //   * 看 `MediaQuery.viewInsetsOf(context).bottom > 0` —— 实测在终端页这个
    //     context 下恒为 0（`dumpsys input_method` 的 `mInputShown` 已经是 true），
    //     于是永远走"显示"分支，收不回去；
    //   * 纯 Dart 记账 `_softKeyboardVisible` —— 用户用系统手势把键盘划下去之后
    //     两边就失配了，第一次点击等于白点。
    // 原生查询不可用时才退回记账值。
    final visible = await JuiceSystemUi.isImeVisible() ?? _softKeyboardVisible;
    if (visible) {
      _softKeyboardVisible = false;
      _terminalFocus.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } else {
      await _showSoftKeyboard();
    }
  }

  /// 布局结束后量真实几何 + 缓冲内容（`JuiceSshGeom3`）。
  ///
  /// 构建期的 `JuiceSshGeom` 读到的行列数是**旧值**（xterm 在布局里才 resize），
  /// 所以旋转问题必须看这一行。`text` 是整块缓冲的开头（`/` 代表换行）：
  /// 屏幕空白时用它区分"缓冲被清空了"和"只是没画出来"。
  void _afterLayout(String tag) {
    if (!mounted) return;
    final terminal = _controller.terminal;
    final trimmed = _trimTrailingBlankLines(terminal);
    _clampTerminalScroll(extraShift: trimmed);
    final position =
        _terminalScroll.hasClients ? _terminalScroll.position : null;
    var head = terminal.buffer.getText().toString().replaceAll('\n', '/').trim();
    if (head.length > 44) head = head.substring(0, 44);
    debugPrint(
      'JuiceSshGeom3($tag): cols=${terminal.viewWidth} '
      'rows=${terminal.viewHeight} lines=${terminal.buffer.lines.length} '
      'cursorY=${terminal.buffer.absoluteCursorY} trimmed=$trimmed '
      'viewport=${position?.viewportDimension.toStringAsFixed(1)} '
      'max=${position?.maxScrollExtent.toStringAsFixed(1)} '
      'pixels=${position?.pixels.toStringAsFixed(1)} text=$head',
    );
  }

  /// 裁掉缓冲区**末尾的空行**，让长度回到正好一屏；返回裁掉的行数。
  ///
  /// xterm 的 `Buffer.resize`（`lib/src/core/buffer/buffer.dart:437-477`）在宽度变化
  /// 触发 `reflow` 之后只做 `while (reflowResult.length < newHeight) add 空行`，
  /// **不会**在 reflow 结果比 `newHeight` 长时截断 —— 于是缓冲区比可视区多出若干行。
  /// 而 xterm 是粘底的（屏幕取最后 `viewHeight` 行、`_maxScrollExtent = 总高 − 视口高`），
  /// 多出来的行就把**第 0 行顶出屏幕**。设备实测：旋转回竖屏后
  /// `cols=50 rows=45 lines=46 max=10.5 pixels=10.5`，首行墨迹从 135 掉到 128
  /// （= 内容上移、被状态栏切掉）；第 260 轮"连上后内容被切掉、点一下键位条才恢复"
  /// 是同一份原因（当时靠那次额外 resize 偶然把偏移抹平）。
  ///
  /// 只裁**末尾且为空**的行：真正的回滚缓冲（有内容的行）一律不动，
  /// 光标上方的内容也不动。
  int _trimTrailingBlankLines(Terminal terminal) {
    final buffer = terminal.buffer;
    final viewHeight = terminal.viewHeight;
    if (viewHeight <= 0 || buffer.lines.length <= viewHeight) return 0;

    // 备用屏（htop/vim 这类交互式程序在用的屏）：**必须正好一屏**，否则 xterm 内层
    // `Scrollable` 的 `maxScrollExtent > 0`，用户就能上下拖。用户实测：
    // "htop 不能滑动（很好），但一旋转到横屏又能滑了，返回竖屏还能滑"。
    // 根因在 `Buffer.resize`（buffer.dart:437-477）的**缩容**分支：游标高于新高度时
    // 它先 `_cursorY--` 而不是 `lines.pop()`，行数缩不到位 —— 而 `_cursorY` 的 clamp
    // 发生在**之后**，救不回行数。备用屏里的多余行是上一尺寸的残留，直接全裁掉。
    if (buffer.isAltBuffer) {
      var popped = 0;
      while (buffer.lines.length > viewHeight) {
        buffer.lines.pop();
        popped++;
      }
      return popped;
    }

    var removable = 0;
    for (var y = buffer.lines.length - 1; y >= viewHeight; y--) {
      if (buffer.lines[y].getText().trim().isNotEmpty) break;
      removable++;
    }
    for (var i = 0; i < removable; i++) {
      buffer.lines.pop();
    }
    return removable;
  }

  /// 视口尺寸变化后把滚动位置重新贴底（丢掉 xterm 残留的分数偏移）。
  ///
  /// 只在用户本来就贴在底部时做：正在翻历史的人不该被拽回来。旋转屏幕、
  /// 软键盘起落、键位条切换都会走到这里 —— 用户报的"终端屏幕旋转内容显示不正常"
  /// 就是旋转后残留了几个像素的偏移（实测首行墨迹 135 → 128，被状态栏切掉）。
  void _clampTerminalScroll({int extraShift = 0}) {
    if (!mounted || !_terminalScroll.hasClients) return;
    if (!_terminalStuckToBottom) return;
    final position = _terminalScroll.position;
    final terminal = _controller.terminal;
    var target = position.maxScrollExtent;
    // 刚裁掉末尾空行时，`maxScrollExtent` 要等下一次布局才会变小，所以先把目标
    // 偏移按裁掉的行数下移，画面立刻就对。
    if (extraShift > 0 && terminal.viewHeight > 0) {
      final cellHeight = position.viewportDimension / terminal.viewHeight;
      target = (target - extraShift * cellHeight)
          .clamp(0.0, position.maxScrollExtent);
    }
    // 无条件 `jumpTo`：值相同也会走 `forcePixels` → 位置通知 → xterm 的
    // `_TerminalView` 重绘。备用屏（vi/vim/htop）内容到达时正好撞在"连接/resize
    // 尚未稳定"的窗口里，第 268 轮实测画面会**整片空白**（同内容多写一段就又画出来
    // 了），根因就是这一帧丢了重绘；这里借尺寸变化后的这次调用把它补上。
    position.jumpTo(target);
    _terminalStuckToBottom = true;
  }

  /// 把输入法顶出来（`_toggleSoftKeyboard` 的显示分支；连上终端时也用它）。
  Future<void> _showSoftKeyboard() async {    _softKeyboardVisible = true;
    _terminalFocus.requestFocus();
    // 等一小段时间让焦点真正落到输入框上再要求显示：紧接着 requestFocus()
    // 调用 `TextInput.show` 在部分机型上会被忽略（点了不弹）。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // 用户实测："终端里用 Android 键盘打什么都输入不了"（键盘弹着但文本进不去）。
    // 只 `requestFocus()` 不够：`TerminalView` 在连接期刚重建过，焦点节点可能仍是
    // "已聚焦"状态，于是引擎不会重新 attach 文本输入客户端 —— 键盘显示着、打字没反应。
    // 所以先 `unfocus()` 再 `requestFocus()`，强制走一次 attach，然后才要求显示输入法。
    _terminalFocus.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    _terminalFocus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    // 用户实测：连上后键盘自动弹出，但这时**打字没反应**，点一下屏幕（重新触发焦点）
    // 就能打字了 —— 说明"弹出输入法"与"文本输入客户端真正挂上"之间存在时序差。
    // 这里在弹出之后再补一次 focus + show，等价于用户那一下点击，用户就不必再点。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _terminalFocus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _onKeyTag(int tag) {
    switch (tag) {
      case KeyTag.fn:
      case KeyTag.backToMain:
        setState(() => _showingFunctionKeys = !_showingFunctionKeys);
        return;
      case KeyTag.toggleKeyboard:
        unawaited(_toggleSoftKeyboard());
        return;
    }
    _controller.handleKeyTag(tag);
    setState(() {});
  }

  // ---------------------------------------------------------- 菜单 --

  /// 原版 `onCreateContextMenu`（`TerminalEmulatorActivity.smali:2108`）的浮层
  /// 上下文菜单，条目逐项对应（数字是它在 `ContextMenu;->add(..)` 里的 id）：
  ///
  ///   标题 terminal（`@string/terminal` 0x7f1103ce）
  ///   0 `copy_from_screen`   (0x7f1100a8)
  ///   1 `copy_whole_session` (0x7f1100ad)
  ///   2 `paste`              (0x7f11032b)
  ///   3 `snippets`           (0x7f1103ad) —— 原版是 `addSubMenu`，带条件
  ///                          `kj0.a().x()`；子项是 `create_snippet`(0x7f1100bb)
  ///                          加用户自己的片段列表
  ///   4 `save_transcript`    (0x7f11037f)
  ///   5 `share_transcript`   (0x7f11039b)
  ///   8 `keep_screen_on`     (0x7f1102a8) —— 原版带条件 `!Z`
  ///   9 `clear`              (0x7f110068)
  ///
  /// 注意末四项是在 `:cond_3` 之后对 `p1` 调用的，属于**顶层**项，不是子菜单项。
  /// 原版菜单里**没有** `theme_slash_colors` / `popup_keyboard_position`
  /// （这两个字符串在整个 smali 树里只有 `R$string` 引用，它们是设置页的标签，
  /// 对应偏好键 `terminal:theme` 与 `terminal:keyboard_position`），克隆此前把它们
  /// 混进了终端菜单，第 31 轮已去掉。
  Future<String?> _showContextMenu(Offset? at) async {
    final s = context.s;
    // 原版这一屏与其它列表页用的是**同一套** AppCompat 浮动菜单
    // （`MenuPopupWindow`，见第 58/59/60 轮实测）：底色 #FAFAFA、行高 48dp、
    // 宽度 = 最宽条目 + 32dp（下限 196dp）、无 scrim，底色框左上角 = **触点**坐标。
    // 克隆此前用的是 Flutter 的 `showMenu`（Material 弹层 + 加粗 40px 表头），
    // 观感与原版差得远；第 61 轮改为与其余五个上下文菜单同一个
    // `showJuicePopupMenu`，表头也回到原版那种 48dp 常规字重。
    //
    // `snippets` 那一项在原版里会被拼上 `(Pro users only)`：
    // `TerminalEmulatorActivity.smali:2271-2323` 在 `kj0.y()` 为真时，把
    // `getItem(3)`（id 3 的 `snippets` 子菜单项）标题重设为
    // `getString(0x7f1103ad=@string/snippets) + " (" + getString(0x7f11035a) + ")"`。
    // 本复刻的片段功能是免费开放的，这里仍按原版**渲染**该后缀（1:1 优先）。
    return showJuicePopupMenu<String>(
      context: context,
      anchor: at == null
          ? juiceContextMenuAnchor(context)
          : Rect.fromLTWH(at.dx, at.dy, 0, 0),
      anchorAtTouch: true,
      title: s('terminal'),
      items: [
        for (final entry in const <(String, String)>[
          ('copy_screen', 'copy_from_screen'),
          ('copy_session', 'copy_whole_session'),
          ('paste', 'paste'),
          ('snippets', 'snippets'),
          ('save_transcript', 'save_transcript'),
          ('share_transcript', 'share_transcript'),
          ('keep_screen_on', 'keep_screen_on'),
          ('clear', 'clear'),
        ])
          JuicePopupItem<String>(
            value: entry.$1,
            label: entry.$2 == 'snippets'
                ? '${s('snippets')} (${s('pro_users_only')})'
                : s(entry.$2),
          ),
      ],
    );
  }

  /// 长按终端弹出的上下文菜单，条目与原版逐项一致（见 `_showContextMenu`）。
  ///
  /// 第 31 轮把这 8 项补齐之后，ActionBar 上那个当初作为可达性兜底的溢出按钮
  /// 已删除，终端页的 chrome 与原版一致（原版终端页只有长按菜单，没有溢出菜单）。
  Future<void> _showTerminalMenu({Offset? at}) async {
    _contextMenuOpen = true;
    final action = await _showContextMenu(at);
    _contextMenuOpen = false;

    if (!mounted || action == null) return;

    switch (action) {
      case 'copy_screen':
        _beginScreenCopy();
      case 'copy_session':
        await _copyToClipboard(_wholeSession);
      case 'paste':
        await _paste();
      case 'snippets':
        await _pickSnippet();
      case 'save_transcript':
        await _saveTranscript();
      case 'share_transcript':
        await _shareTranscript();
      case 'keep_screen_on':
        await _keepScreenOn();
      case 'clear':
        // RIS（完整复位）+ 清屏 + 清回滚缓冲 + 光标归位。
        _controller.sendText('\u001bc\u001b[2J\u001b[3J\u001b[H');
      case 'theme':
        await _pickTheme();
      case 'keyboard_position':
        await _pickKeyboardPosition();
    }
  }

  Future<void> _pickTheme() async {
    final settings = SettingsController.instance;
    final index = await TerminalPickers.pickTheme(
      context,
      settings.terminalThemeIndex,
    );
    if (index == null) return;
    await settings.setTerminalThemeIndex(index);
    if (mounted) setState(() {});
  }

  /// 切换额外键行的位置。对应原版设置项 `popup_keyboard_position`。
  Future<void> _pickKeyboardPosition() async {
    final s = context.s;
    final settings = SettingsController.instance;
    // 文案顺序与 arrays.xml 的 `terminal_keyboard_position_names` 一致：
    // 0 上方 / 1 下方 / 2 不显示。
    // 逐字核对过 arrays.xml:55-59 —— 这三项引用的字符串是
    // above_terminal / below_terminal / disabled，**不是** popup_keyboard_position_*。
    final names = [
      s('above_terminal'),
      s('below_terminal'),
      s('disabled'),
    ];
    final current = settings.terminalKeyboardPosition;
    if (!mounted) return;

    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(s('popup_keyboard_position')),
        children: [
          // 新版 Flutter 把单选状态移到了 RadioGroup 上，
          // RadioListTile 自身不再接收 groupValue / onChanged。
          RadioGroup<int>(
            groupValue: current,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < names.length; i++)
                  RadioListTile<int>(value: i, title: Text(names[i])),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await settings.setTerminalKeyboardPosition(picked);
    if (mounted) setState(() {});
  }

  /// 在会话里运行片段。对应原版上下文菜单里的 Snippets 子菜单。
  Future<void> _pickSnippet() async {
    final s = context.s;
    final snippets = await JuiceDatabase.instance.snippets();
    if (!mounted) return;
    if (snippets.isEmpty) {
      await JuiceDialogs.message(
        context,
        title: s('snippets'),
        message: s('no_snippets'),
      );
      return;
    }

    final chosen = await showDialog<Snippet>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(s('run_snippet')),
        children: [
          for (final snippet in snippets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(snippet),
              child: Text('${snippet.name}\n${snippet.content}'),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    _controller.runSnippet(chosen.content);
    // 使用次数 +1，供「常用」排序使用。
    await JuiceDatabase.instance.saveSnippet(
      chosen.copyWith(count: chosen.count + 1),
    );
  }

  /// 保存会话记录。文件名格式与原版一致：`<昵称>_yyyyMMddHHmmss.txt`。
  Future<void> _saveTranscript() async {
    final s = context.s;
    final text = _wholeSession;
    if (text.isEmpty) return;

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final safeName = widget.connection.nickname.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${safeName}_$stamp.txt');
    await file.writeAsString(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${s('transcript_saved_to')} ${file.path}')),
    );
  }

  Future<void> _shareTranscript() async {
    final s = context.s;
    final text = _wholeSession;
    if (text.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: '${s('ssh_session_transcript')} — ${widget.connection.nickname}',
      ),
    );
  }

  /// 保持屏幕常亮。原版会先弹 `screen_on_warning` 警告。
  Future<void> _keepScreenOn() async {
    final s = context.s;
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('keep_screen_on'),
      message: s('screen_on_warning'),
      confirmLabel: s('yes'),
    );
    if (!confirmed) return;
    await WakelockPlus.enable();
  }

  /// 返回键：原版弹 `background_session` 三选提示。
  ///
  /// 是 —— 保持会话在后台运行，只关闭界面；
  /// 否 —— 断开连接；
  /// 取消 —— 什么都不做。
  Future<void> _handleBackPressed() async {
    final s = context.s;
    final choice = await showDialog<String>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (dialogContext) => JuiceAlertDialog(
        title: s('background_session'),
        // 必须显式给正文内边距：`JuiceAlertDialog` 的 `contentPadding` 为空时正文会
        // 贴到面板边缘（用户报的"排版左边距没有起效"）。同一套对话框在
        // `juice_dialogs.dart` 里每一处都传了 `messageContentPadding`，只有这里漏了。
        contentPadding: JuiceAlertDialog.messageContentPadding,
        content: Text(s('background_session_battery_warning')),
        actions: <Widget>[
          JuiceDialogAction(
            label: s('cancel'),
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
          ),
          JuiceDialogAction(
            label: s('no'),
            onPressed: () => Navigator.of(dialogContext).pop('no'),
          ),
          JuiceDialogAction(
            label: s('yes'),
            onPressed: () => Navigator.of(dialogContext).pop('yes'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'cancel') return;
    if (choice == 'no') {
      // 原版 `BackgroundPrompt`：选「否」= 不保持后台 = 断连并回收会话。
      _controller.removeListener(_onSessionChanged);
      await SessionHost.instance.close(widget.connection.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------- 构建 --
  @override
  Widget build(BuildContext context) {
    final settings = SettingsController.instance;
    final position = settings.terminalKeyboardPosition;
    // **真正的状态栏高度**。必须在这里（Scaffold 之外）取：Scaffold 会给 body 的
    // MediaQuery 里再叠加一个 AppBar 高度，body 内读到的 `padding.top` 是
    // 状态栏 + 56 —— 本页实测 104.8dp（见 JuiceSshGeom 的 padTop），
    // 而真正的状态栏只有 48.8dp。
    final topInset = MediaQuery.paddingOf(context).top;
    _outerTopInset = topInset;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: _controller.surfaceTheme.background,
        // 原版终端**没有实心标题栏**：实测它的 view 从状态栏（y=128）就开始，
        // 整片底色是 `#254E59`（= 主题背景 + 12% 白），动作按钮
        // `[985,138][1080,264]` 是**浮在终端上**的。所以这里让 body 伸到
        // AppBar 后面，并把 AppBar 做成全透明。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          // 原版终端页**没有返回箭头**：退出一律靠系统导航栏 / 返回手势
          // （走 `_handleBackPressed` 的 `background_session` 三选提示）。
          // Flutter 的 AppBar 默认会自动补一个 leading 返回按钮，这里关掉。
          automaticallyImplyLeading: false,
          // 状态栏**底色**由 `_syncStatusBar()` 走平台通道直接设窗口（原因见那里）：
          // 原版终端页 y0..127 = `#073642`，正是 `terminal_themes.json` 里
          // `Solarized Dark` 的 ANSI 0 `#FF073642`；两侧 y128 起（终端画布）都是
          // `(37,78,89)`，逐像素相同 —— 差异只在状态栏这一条。
          // 这里只负责**图标明暗**，该字段在设备上确实生效。
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarIconBrightness:
                _controller.surfaceTheme.black.computeLuminance() > 0.5
                    ? Brightness.dark
                    : Brightness.light,
            statusBarBrightness:
                _controller.surfaceTheme.black.computeLuminance() > 0.5
                    ? Brightness.light
                    : Brightness.dark,
          ),
          // 原版终端上也没有标题文字：`o_term.png` 在 137..152 之后的墨迹
          // 全部属于终端自己渲染的第一行输出。
          // 原版终端页**没有** ActionBar 溢出菜单：全 smali 树里本 Activity 既没有
          // `onCreateOptionsMenu` 也没有 `onPrepareOptionsMenu`，菜单只由长按
          // 上下文菜单提供。此前这里挂了一个 36×48dp（尺寸对齐原版动作按钮
          // `[985,138][1080,264]`）的溢出按钮当可达性兜底，第 31 轮删除。
        ),
        body: Stack(
          children: [
            Column(
              children: [
                if (position == 0 && _popupKeyboardVisible)
                  // 终端页是 `extendBodyBehindAppBar: true`（body 从 y=0 开始），
                  // 键位条放到终端上方时会被状态栏盖掉上半截 —— 用户报的
                  // "Above Terminal 布局没有显示全"。这里补上**真正的状态栏高度**
                  // （`topInset`，不是 body 内被 Scaffold 加过 AppBar 高度的那个值）。
                  Padding(
                    padding: EdgeInsets.only(top: topInset),
                    child: _buildKeyRow(),
                  ),
                Expanded(
                  // 原版终端页的窗口从状态栏底边（y=128）开始，
                  // `o_term.png` 实测第一行墨迹 y=137 = 128 + 9（字形在行内的偏移）。
                  // 本复刻是 edge-to-edge（body 真的从 y=0 起），所以要自己让出状态栏，
                  // 否则第 0 行会被状态栏盖掉（实测首行墨迹落在 128）。
                  child: Padding(
                    // 键位条在**终端上方**时，它自己已经让出了状态栏高度（上面那个
                    // `Padding(top: topInset)`）；终端这里再让一次，就会在
                    // **键位条底端**多出一条和状态栏一样高的空隙 —— 用户报的
                    // "黑客键盘设置成从终端上面弹出，黑客键盘底端高度会莫名多出来一截"。
                    // 只有键位条**没在上方**（下置 / 已收起）时终端才需要自己让位。
                    padding: EdgeInsets.only(
                      top: (position == 0 && _popupKeyboardVisible)
                          ? 0
                          : topInset,
                    ),
                    // 页面级不再剥夺任何拖动设备：`dragDevices` 一旦为空，普通 shell 就
                    // 彻底滑不动，而它依赖的"交互式程序"标志会误判/滞留（普通 shell 自己
                    // 开鼠标上报模式、全屏程序退出未复位、保活会话沿用旧值、页面不重建导致
                    // 配置过期）。禁滑改为只作用在终端自身的滚动体上（见 `_buildTerminal`），
                    // 判据用实时的 `terminal.isUsingAltBuffer`。
                    child: _buildBody(),
                  ),
                ),
                if (position == 1 && _popupKeyboardVisible) _buildKeyRow(),
                // 选择提示条在**快捷键盘的底端**（屏幕最下方），与原版一致。
                // 此前它挂在 Column 最前面，跑到了屏幕顶端（用户报的第 1 条）。
                if (_selectingStart || _selectingEnd) _buildSelectionBanner(),
              ],
            ),
            // 教程层盖在终端之上（原版把它 addView 到根布局并 bringChildToFront，
            // 所以连键盘条一起盖住）；`tutorial_terminal.xml` 里整层 alpha=0.7。
            if (_showTutorial)
              Positioned.fill(
                child: _TerminalTutorial(onDismiss: _dismissTutorial),
              ),
          ],
        ),
      ),
    );
  }

  /// 两段式选择提示条。起点用红色、终点用绿色，均取原版颜色资源。
  Widget _buildSelectionBanner() {
    final s = context.s;
    return GestureDetector(
      onTap: _advanceScreenCopy,
      child: Container(
        width: double.infinity,
        color: _selectingEnd
            ? JuiceFixedColors.copyInstructionsEndSelection
            : JuiceFixedColors.copyInstructionsStartSelection,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectingEnd
                    ? s('copy_instructions_end_selection')
                    : s('copy_instructions_start_selection'),
                style: const TextStyle(
                  color: JuiceFixedColors.copyInstructionsText,
                ),
              ),
            ),
            TextButton(
              onPressed: _cancelScreenCopy,
              child: Text(
                s('cancel'),
                style: const TextStyle(
                  color: JuiceFixedColors.copyInstructionsText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow() {
    return ColoredBox(
      color: _controller.keyBarBackground,
      child: HackerKeyboard(
        onKeyTag: _onKeyTag,
        showingFunctionKeys: _showingFunctionKeys,
        ctrlArmed: _controller.ctrlArmed,
        altArmed: _controller.altArmed,
        foreground: _controller.theme.foreground,
        onToggleFunctionKeys: () =>
            setState(() => _showingFunctionKeys = !_showingFunctionKeys),
      ),
    );
  }

  // --- 长按菜单：绕开手势竞技场，用裸指针按下计时 ---

  /// 原版长按用系统默认超时（`ViewConfiguration.getLongPressTimeout()`），
  /// 这台设备上是 500ms，这里对齐；移动超过 18px 视为滑动，取消。
  static const Duration _longPressTimeout = Duration(milliseconds: 500);
  static const double _longPressSlop = 18;

  /// 自增令牌代替 `Timer`，这样不必额外引入 `dart:async`。
  int _longPressToken = 0;
  Offset? _longPressOrigin;

  /// 原版 5.2 `terminal:horizontal_swipe_mode` 的五种取值对应的输入序列
  /// （`docs/terminal-behaviour-spec.md` 5.2）。下标即设置值，每项是
  /// （手指向左 = `dx < 0` 走 `c(0)`，手指向右 = `dx > 0` 走 `c(1)`）。
  ///
  /// 原版发的是真实 `KeyEvent`，经 `TermKeyListener` 之后 Ctrl 形式落地为控制字符：
  /// Irssi 的 Ctrl+P / Ctrl+N 就是 `0x10` / `0x0E`；Tmux 与 Screen 是
  /// `Ctrl+B` / `Ctrl+A` 之后再发一个 `P` / `N`。WeeChat 的 Alt+方向键按 xterm
  /// 的修饰键编码落地为 `ESC [ 1 ; 3 D` / `ESC [ 1 ; 3 C`。
  static const List<(String, String)> _swipeSequences = [
    ('\x10', '\x0e'),
    ('\x1b[1;3D', '\x1b[1;3C'),
    ('\x02p', '\x02n'),
    ('\x01p', '\x01n'),
    ('', ''),
  ];

  /// fling 门槛：原版「非 fling 或过慢的位移不会触发 `c()`」，这里用位移 + 速度近似。
  static const double _swipeMinDistance = 60;
  static const double _swipeMinVelocity = 200;

  Offset? _swipeStart;
  Duration? _swipeStartAt;

  void _onTerminalPointerDown(PointerDownEvent event) {
    _longPressOrigin = event.position;
    _swipeStart = event.position;
    _swipeStartAt = event.timeStamp;
    _pressStartedAt = DateTime.now();
    // 两段式选择期间不弹上下文菜单：把长按/拖动让给 `TerminalView` 自己的选区识别。
    // 否则用户按提示"拖到选区起点"时只会反复弹出菜单，永远选不中（用户报的第 5 条）。
    if (_selectingStart || _selectingEnd) {
      // 只让已排队的长按回调作废，**保留** `_longPressOrigin`：抬起时要靠它区分
      // "轻点（推进选区阶段）"与"拖动（设置选区终点）"。
      _longPressToken++;
      // 按下即定锚点并先选出按下处那个单元格：原版按下时光标处就是红色。
      _applyCopySelection(_cellAt(event.localPosition));
      return;
    }
    final token = ++_longPressToken;
    Future<void>.delayed(_longPressTimeout, () {
      if (!mounted || token != _longPressToken) return;
      final at = _longPressOrigin;
      // 长按已经弹菜单了：把原点清掉，否则抬手时位移仍 ≤ slop，
      // 会被"轻点终端 = 切换弹出键盘"那条分支再吃一次（菜单背后键盘乱跳）。
      _longPressOrigin = null;
      // 长按期间别让这次按压把软键盘顶出来。
      _terminalFocus.unfocus();
      _showTerminalMenu(at: at);
    });
  }

  /// 兜底驱动上一次写入的滚动位置：用来识别"终端自己的 `Scrollable` 是否已经在滚"，
  /// 避免原生拖动 + 兜底驱动叠加成双倍速度。
  double? _lastDriverPixels;

  void _onTerminalPointerMove(PointerMoveEvent event) {
    final origin = _longPressOrigin;
    // 这里**不能**提前 `return`：下方的"主屏拖动滚动"必须在每次指针移动时执行。
    // 长按一旦因位移超阈值被取消，`_longPressOrigin` 就变 null；早期版本直接 return，
    // 于是只有最初一两帧能驱动滚动 —— 表现为"时能动、多数不动"（第 49 轮定位）。
    if (origin != null && (event.position - origin).distance > _longPressSlop) {
      _cancelLongPress();
    }
    if (_selectingStart || _selectingEnd) {
      // 拖动即扩展选区（原版提示的"拖到起点 / 终点"）。
      _applyCopySelection(_cellAt(event.localPosition));
    }
    // 直接量观测：拖动期间滚动偏移是否变化。此前两次 A/B 都用"整屏像素差异"
    // 做判据、两次都不成立（第 279 轮实验无效、第 280 轮两组 2.27% 无区别），
    // 这里改成读 `ScrollPosition` 本身 —— 交互式程序在跑时手指拖动被禁掉，
    // `pixels` 应始终等于 `maxScrollExtent`；普通 shell 拖动时会小于它。
    //
    // 用 `assert` 包住：断言在 release 包中被整段剥离，交付的 APK 不会因为
    // 每次指针移动都打印而刷爆 logcat；调试/性能分析时仍可用。
    // 触摸滚动由这里**独家**负责：终端那个 `Scrollable` 的拖动设备已被永久移除
    // （见 `_buildTerminal` 里的 `ScrollConfiguration(dragDevices: const {})`）。
    // 判据用 `terminal.isUsingAltBuffer` —— xterm 的**实时**备用屏状态
    // （`xterm-4.0.0/lib/src/terminal.dart:214`）：
    //   主屏（普通 shell）→ 驱动滚动，手指下滑回看更早历史；
    //   备用屏（htop/vim/less）→ 不驱动，满足"交互命令重绘期间禁止滑动"。
    // 之前这里与 `dragDevices` 都依赖 `interactiveProgram` 这个启发式标志，标志一旦
    // 误判或滞留，普通 shell 就彻底滑不动（用户实测「`tree -L 2` 输出超屏后无法滚屏」）。
    if (!_controller.terminal.isUsingAltBuffer &&
        !_selectingStart &&
        !_selectingEnd &&
        _terminalScroll.hasClients &&
        event.delta.dy.abs() > 0.5) {
      final pos = _terminalScroll.position;
      // 拖动期间键盘/教程层可能正在改变布局：内容尺寸未就绪、或区间非法时直接放弃，
      // 否则 `jumpTo` 会在断言里炸掉（`min > max` / 无 content dimensions）。
      if (pos.hasContentDimensions && pos.maxScrollExtent > pos.minScrollExtent) {
        // 兜底驱动：终端自己的 `Scrollable` 若已经把位置滚动过了（原生拖动生效），
        // 这里不再叠加，避免双倍速度；若它被拦下/失效，则由这里接管滚动。
        if (pos.pixels != _lastDriverPixels) {
          _lastDriverPixels = pos.pixels;
        } else {
          final target = (pos.pixels - event.delta.dy)
              .clamp(pos.minScrollExtent, pos.maxScrollExtent);
          if (target != pos.pixels) {
            pos.jumpTo(target);
            _lastDriverPixels = target;
          }
        }
      }
    }
    assert(() {
      if (_terminalScroll.hasClients) {
        final pos = _terminalScroll.position;
        debugPrint('JuiceSshScroll: pixels=${pos.pixels.toStringAsFixed(1)} '
            'max=${pos.maxScrollExtent.toStringAsFixed(1)}');
      }
      return true;
    }());
  }

  void _onTerminalPointerUp(PointerUpEvent event) {
    final origin = _longPressOrigin;
    final elapsed = _pressElapsed;
    final selecting = _selectingStart || _selectingEnd;
    _cancelLongPress();
    _pressStartedAt = null;
    if (selecting) {
      _swipeStart = null;
      _swipeStartAt = null;
      // 轻点 = 推进两段式选择（起点 → 终点 → 复制）；拖动则只更新选区终点，
      // 由用户再点一次（终端或提示条）确认。
      // 此前只有提示条本身可点，终端区域点了毫无反应 —— 这就是"怎么都选不中"的原因。
      if (origin == null || (event.position - origin).distance <= _longPressSlop) {
        _advanceScreenCopy();
      }
      return;
    }
    // 轻点终端 = 弹出键盘开关（原版教程："点击终端以显示弹出键盘"）。
    // 三个条件缺一不可：本次按压没被长按消费掉、位移在 slop 内、且按住时间
    // 没到长按阈值 —— 否则长按弹菜单时会顺带把键位条也翻掉。
    if (origin != null &&
        !_contextMenuOpen &&
        (event.position - origin).distance <= _longPressSlop &&
        elapsed <= _longPressTimeout) {
      _swipeStart = null;
      _swipeStartAt = null;
      setState(() => _popupKeyboardVisible = !_popupKeyboardVisible);
      return;
    }
    _handleHorizontalSwipe(event);
  }

  /// 原版 `TerminalGestureListener.onFling`：`dx < 0`（手指向左）走 `c(0)`，
  /// `dx > 0`（手指向右）走 `c(1)`；模式 4（Disabled）的 `c()` 立即返回，
  /// 所以这里对应空序列。
  void _handleHorizontalSwipe(PointerUpEvent event) {
    final start = _swipeStart;
    final startAt = _swipeStartAt;
    _swipeStart = null;
    _swipeStartAt = null;
    if (start == null || startAt == null) return;
    final delta = event.position - start;
    final ms = (event.timeStamp - startAt).inMilliseconds;
    if (ms <= 0) return;
    if (delta.dx.abs() < _swipeMinDistance) return;
    // 明显的斜向/纵向拖动交给终端自己滚动，不算水平 fling。
    if (delta.dx.abs() < delta.dy.abs() * 1.5) return;
    if (delta.dx.abs() / (ms / 1000) < _swipeMinVelocity) return;
    final mode = SettingsController.instance.terminalSwipeMode;
    if (mode < 0 || mode >= _swipeSequences.length) return;
    final (left, right) = _swipeSequences[mode];
    final sequence = delta.dx < 0 ? left : right;
    if (sequence.isEmpty) return;
    _controller.sendText(sequence);
  }

  void _onTerminalPointerCancel(PointerCancelEvent event) {
    _cancelLongPress();
    _pressStartedAt = null;
  }

  /// 本次按压已持续多久（没有按压时为零）。
  Duration get _pressElapsed {
    final started = _pressStartedAt;
    if (started == null) return Duration.zero;
    return DateTime.now().difference(started);
  }

  void _cancelLongPress() {
    _longPressToken++;
    _longPressOrigin = null;
  }

  Widget _buildBody() {
    switch (_controller.state) {
      case TerminalSessionState.connecting:
        // 连接期间**也要把终端摆进树里**：让它赶在服务端第一个字节到达之前
        // 完成一次布局、拿到真实行列数。否则横幅会以 xterm 默认的 80×24
        // 写进缓冲区，等控件真正布局时再 resize + reflow，缓冲区会比可视区
        // 多出一行，粘底显示又把第一行顶到状态栏之外 —— 这正是用户实测的
        // "连接成功终端显示内容不完全，被状态栏遮挡；点一次键位条
        // （触发一次布局变化）后内容显示恢复正常"。
        // 连接画面是整块不透明径向渐变（`_ConnectingView`），终端在其后看不见，
        // 观感与改动前完全一致。
        return Stack(
          children: [
            Positioned.fill(child: _buildTerminal()),
            Positioned.fill(
              child: _ConnectingView(message: _controller.progress),
            ),
          ],
        );
      case TerminalSessionState.failed:
        return _FailureView(
          failure: _controller.failure,
          onRetry: () => _controller.reconnect(),
        );
      case TerminalSessionState.connected:
      case TerminalSessionState.closed:
        return _buildTerminal();
    }
  }

  Widget _buildTerminal() {
    final settings = SettingsController.instance;
    // 选择过程中把边距放宽到 `terminal:margin_selection`，便于选到边缘字符。
    final selecting = _selectingStart || _selectingEnd;
    final margin = selecting && settings.terminalMarginSelection > 0
        ? settings.terminalMarginSelection
        : settings.terminalMargin;

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 视口尺寸变化（旋转屏幕、键位条切换、软键盘起落）后重新贴底。
              // 这里只登记"变了"，真正的修正放到布局结束之后（post-frame），
              // 那时 xterm 才算完新的行列数。
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (_terminalLayoutSize != size) {
                final first = _terminalLayoutSize == null;
                _terminalLayoutSize = size;
                // 布局**之后**再量一次：xterm 的 resize 发生在布局里，构建期读到的
                // 行列数永远落后一拍（旋转问题的诊断就卡在这里）。
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _afterLayout(first ? 'first' : 'resize'),
                );
              }
              // 一次性几何诊断：用来定位"终端内容不从顶端开始"（用户报的第 1 条）。
              // 画布确实从 y=128 起（与原版一致），但第一行内容落在 y=241/274，
              // 而且即使发过 `ESC c ESC[2J ESC[3J ESC[H` 把光标归位到 (0,0) 之后，
              // 回显仍在 y=274 —— 所以偏移发生在终端内部，需要行列数/单元格高度
              // 与控件高度对账才能判定是"缓冲区多了空行"还是"绘制原点被推低"。
              // 几何诊断：数值变化时打一行（首次构建时终端还是 xterm 的默认
              // 80×24，resize 发生在布局之后，所以要连着两次都看到才完整）。
              if (constraints.maxHeight > 0) {
                final terminal = _controller.terminal;
                if (terminal.viewHeight > 0) {
                  // 直接量控件自己在屏幕上的位置：`boxTop` 是逻辑像素，
                  // 乘 dpr 就是物理像素，用来和"首行墨迹 y=241"对账。
                  final box = context.findRenderObject() as RenderBox?;
                  // `localToGlobal` 会一路 `getTransformTo` 往上走，只要有一个祖先
                  // 还没完成布局就在 `hasSize` 上断言。这不是"理论上可能"：本段在
                  // `LayoutBuilder` 里执行（**布局期**），而祖先包含路由转场的
                  // `RenderFractionalTranslation` —— 集成测试里每次都命中，抛出的
                  // 断言会把整个 layout callback 打断（第 49 轮用堆栈定位到本行）。
                  //
                  // 布局是自上而下的：这个祖先没布局完，本控件也一定还没有尺寸，
                  // 所以用 `hasSize` 挡住即可；未就绪就沿用上一次的 `_terminalBoxTop`。
                  final global = (box == null || !box.hasSize)
                      ? Offset.zero
                      : box.localToGlobal(Offset.zero);
                  _terminalBoxTop = global.dy;
                  final mq = MediaQuery.of(context);
                  final line =
                      'JuiceSshGeom: widget=${constraints.maxWidth.toInt()}x'
                      '${constraints.maxHeight.round()} '
                      'boxTop=${global.dy.toStringAsFixed(1)} '
                      'cols=${terminal.viewWidth} rows=${terminal.viewHeight} '
                      'cellH=~${(constraints.maxHeight / terminal.viewHeight).toStringAsFixed(2)} '
                      'bufferLines=${terminal.buffer.lines.length} '
                      'cursorY=${terminal.buffer.absoluteCursorY} '
                      'scrollback=${terminal.buffer.lines.length - terminal.viewHeight} '
                      'fontSize=${_controller.textStyle.fontSize} '
                      'padTop=${mq.padding.top.toStringAsFixed(1)} '
                      'outerTop=${_outerTopInset?.toStringAsFixed(1)} '
                      'viewTop=${mq.viewPadding.top.toStringAsFixed(1)} '
                      'insetsB=${mq.viewInsets.bottom.toStringAsFixed(1)} '
                      'dpr=${mq.devicePixelRatio.toStringAsFixed(3)} '
                      'screenH=${mq.size.height.toStringAsFixed(1)}';
                  if (line != _lastGeometry) {
                    _lastGeometry = line;
                    debugPrint(line);
                  }
                }
              }
              return Listener(
                // 这个 key 是诊断用的锚点（第 60 轮）：用来在集成测试里判定
                // "屏幕上那份 TerminalView 是否真的在这段子树里"。
                // `find.byType(Listener)` 数祖先是不行的 —— Flutter 内部
                // （Scrollable / CustomTextEdit）自己也用 Listener。
                key: const ValueKey<String>('juice-terminal-listener'),
                // 长按终端弹出上下文菜单，与原版一致（原版是
                // `registerForContextMenu(terminalView)`）。注意：xterm 内部自带
                // `LongPressGestureRecognizer`（用于文本选择），外层 GestureDetector
                // 的长按会在手势竞技场里输给它 —— 所以这里绕开竞技场，用裸指针计时。
                onPointerDown: _onTerminalPointerDown,
                onPointerMove: _onTerminalPointerMove,
                onPointerUp: _onTerminalPointerUp,
                onPointerCancel: _onTerminalPointerCancel,
                child: MediaQuery.removePadding(
                  // xterm 的 `TerminalView` 把 `MediaQuery.of(context).padding`
                  // 直接当成**终端内容**的内边距（xterm 4.0.0
                  // `lib/src/terminal_view.dart:230` → `RenderTerminal.padding`）。
                  // 而 Scaffold 交给 body 的 MediaQuery 里 `padding.top` 是
                  // 状态栏 + AppBar 高度：本页实测 `padTop=104.8dp`
                  // （48.8 + 56，见 JuiceSshGeom 日志），于是整块内容被下推
                  // 104.8dp ≈ 275px —— 这就是用户报的"终端离顶端有距离"。
                  // 实测首行墨迹 241px（原版 137px），差值 104px 与之吻合。
                  // 原版终端铺满自己那块区域、本身不带系统栏内边距，这里清零。
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  removeLeft: true,
                  removeRight: true,
                  child: ListenableBuilder(
                    // 仅在**当前真的处于备用屏**时剥夺终端原生触摸拖动：判据取 xterm 的
                    // 实时状态 `terminal.isUsingAltBuffer`，而不是"有交互式程序在跑"这个
                    // 会误判/滞留的启发式标志 —— 后者一旦为真，普通 shell 就彻底滑不动
                    // （用户实测「tree -L 2 输出超屏后无法滚屏」）。
                    // 重建由"备用屏标志 + 每次终端输出"共同驱动：前者在进出序列上翻转，
                    // 后者（`outputTick`）保证 htop 这类持续重绘时配置不会过期 —— 否则
                    // 会出现"进了交互程序仍然能滑"（用户实测）。只在终端这一层生效。
                    listenable: Listenable.merge(<Listenable>[
                      _controller.interactiveProgram,
                      _controller.outputTick,
                    ]),
                    builder: (context, child) => ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: _controller.terminal.isUsingAltBuffer
                            ? const {}
                            : null,
                      ),
                      child: child!,
                    ),
                    child: TerminalView(
                    _controller.terminal,
                    controller: _terminalController,
                    scrollController: _terminalScroll,
                    theme: _controller.surfaceTheme,
                    textStyle: _controller.textStyle,
                    focusNode: _terminalFocus,
                    padding: EdgeInsets.all(margin.toDouble()),
                    deleteDetection: true,
                    keyboardType: TextInputType.text,
                    // 原版在备用屏（htop / vim / man 这类交互命令）里**不**把竖向滑动
                    // 翻译成方向键：用户实测"进入交互命令时比如 htop 仍然可以上下滑动，
                    // 和原版不一致"。xterm 4.0.0 的 `simulateScroll` 默认 true
                    // （`terminal_view.dart:138-143`："when the terminal is in alternate
                    // buffer ... the terminal will simulate scrolling by sending up/down
                    // arrow keys"），所以这里显式关掉：备用屏里竖向滑动不再产生任何输入。
                    // 主屏（普通 shell）的历史滚动不受影响，那是 `Scrollable` 自己的事。
                    // 保持 false：xterm 的 `TerminalScrollGestureHandler` 在**主屏是透明的**
                    // （`scroll_handler.dart:116-118`：`if (!isAltBuffer) return child;`），
                    // 只有备用屏（htop/vim 等）才用它把滚动翻译成滚轮/方向键。用户实测
                    // "进入交互命令时仍然可以上下滑动，和原版不一致"，所以备用屏里关掉
                    // 这个模拟 —— 它与主屏的历史滚动**无关**（第 44 轮用实验证实：改成
                    // true 数值完全不变），主屏滑不动的原因在别处。
                      simulateScroll: false,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_controller.state == TerminalSessionState.closed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DisconnectedBanner(
              onReconnect: () => _controller.reconnect(),
            ),
          ),
      ],
    );
  }
}

/// 连接中的全屏提示。
///
/// 背景是 `@drawable/loading_screen` 的径向渐变：中心 `#ff292929`、
/// 边缘 `#ff090909`，半径 600。文案用 `connecting`（Connecting…）。
class _ConnectingView extends StatelessWidget {
  const _ConnectingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 2,
          colors: [
            JuiceFixedColors.loadingScreenStart,
            JuiceFixedColors.loadingScreenEnd,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              context.s('connecting'),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 连接失败提示。文案用原版的 `connection_failed` / `unabled_to_connect_to_host`
/// （注意原版这个键名本身就少了个 e）与 `reconnect`。
class _FailureView extends StatelessWidget {
  const _FailureView({required this.failure, required this.onRetry});

  final SshFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              failure?.kind == SshFailureKind.network
                  ? s('unabled_to_connect_to_host')
                  : s('connection_failed'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              failure?.message ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextButton(onPressed: onRetry, child: Text(s('reconnect'))),
          ],
        ),
      ),
    );
  }
}

/// 远端 shell 已退出时贴在底部的提示条。
/// `res/layout/tutorial_terminal.xml` —— 首次进终端的教程层。
///
/// 整层黑底 + `android:alpha="0.7"`，盖满全屏（`fitsSystemWindows="true"`，所以
/// 这里套一层 `SafeArea`）；内部是可滚动的文字列，底部固定一个按钮。
/// 文字规格逐条照抄布局：
///
/// * `@string/tutorial` —— 18sp 加粗白字，四边 margin 5dp；
/// * `@string/font_size` —— 14sp 加粗白字，marginLeft 10dp / marginBottom 5dp；
/// * 其余三条说明 12sp 加粗白字，左右 margin 20dp / marginBottom 5dp，
///   与夹在中间的 12sp 分组行（marginLeft 10dp）交替，形成两级缩进。
///
/// 布局里 ScrollView 的 `layout_marginBottom=50dp`，正是给底部按钮
/// （30dp 高 + 上下各 10dp 外距）留出的位置。
class _TerminalTutorial extends StatelessWidget {
  const _TerminalTutorial({required this.onDismiss});

  final VoidCallback onDismiss;

  static const double _titleSize = 18;
  static const double _groupSize = 14;
  static const double _bodySize = 12;
  static const EdgeInsets _bodyMargin =
      EdgeInsets.only(left: 20, right: 20, bottom: 5);
  static const EdgeInsets _groupMargin = EdgeInsets.only(left: 10, bottom: 5);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ColoredBox(
      // 整层 70% 不透明（原版 alpha=0.7 + 黑色背景）。
      color: Colors.black.withValues(alpha: 0.7),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(s('tutorial'), _titleSize, const EdgeInsets.all(5)),
                    _line(s('font_size'), _groupSize, _groupMargin),
                    _line(s('use_the_volume'), _bodySize, _bodyMargin),
                    _line(s('popup_keyboard'), _bodySize, _groupMargin),
                    _line(s('tap_the_terminal'), _bodySize, _bodyMargin),
                    _line(s('copy_paste_share_save'), _bodySize, _groupMargin),
                    _line(s('long_press_the_terminal'), _bodySize, _bodyMargin),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _TutorialButton(
                label: s('ok_i_got_it'),
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String text, double size, EdgeInsets margin) {
    return Padding(
      padding: margin,
      child: Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// `@drawable/button_transparent` + 布局里那个 30dp 高的 Button。
///
/// 描边在布局里写的是 `3.0px`（**物理**像素，不是 dp），所以这里按设备像素比
/// 换算，保证任何密度下都是 3 个物理像素；按下时描边由 `#ffffffff` 变
/// `#33ffffff`（alpha 0.2），也就是按钮的 `state_pressed` 分支。
class _TutorialButton extends StatelessWidget {
  const _TutorialButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
          minimumSize: WidgetStateProperty.all(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(color: Colors.white, width: 3 / dpr),
            ),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }
}

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner({required this.onReconnect});

  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Material(
      color: JuiceFixedColors.copyInstructionsBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s('disconnect'),
                style: const TextStyle(
                  color: JuiceFixedColors.copyInstructionsText,
                ),
              ),
            ),
            TextButton(
              onPressed: onReconnect,
              child: Text(
                s('reconnect'),
                style: const TextStyle(
                  color: JuiceFixedColors.copyInstructionsText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
