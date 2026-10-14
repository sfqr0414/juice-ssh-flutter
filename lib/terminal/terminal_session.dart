import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../app/settings_controller.dart';
import '../data/models.dart';
import '../ssh/port_forward_registry.dart';
import '../ssh/port_forward_service.dart';
import '../ssh/ssh_service.dart';
import 'escape_characters.dart';
import 'terminal_fonts.dart';
import 'terminal_themes.dart';

/// @brief 会话所处的阶段。
///
/// 对应原版 `connecting.xml` 展示连接进度、
/// 以及连接成功后切换到终端视图的过程。
enum TerminalSessionState {
  /// @brief 正在建连 / 认证
  connecting,

  /// @brief 终端可用
  connected,

  /// @brief 远端 shell 正常退出
  closed,

  /// @brief 连接失败
  failed,
}

/// @brief 单个终端会话。
///
/// 负责三件事：
/// 1. **状态机** —— 连接中 / 已连接 / 已断开 / 失败；
/// 2. **字节泵** —— 远端输出喂给 [Terminal]，终端产生的输入写回远端；
/// 3. **修饰键语义** —— 还原原版 Ctrl / Alt 的行为。
class TerminalSessionController extends ChangeNotifier {
  /// @brief 交互式程序（htop/vim 等）是否正在跑。
  ///
  /// 判定完全来自**入站数据**里的私有模式，且**只认备用屏**：
  /// `ESC[?1049h` = 切备用屏（`ESC[?47h` 是它的旧写法），对应的 `...l` 复位。
  /// 鼠标上报模式 `1000h/1002h/1003h` **不算** —— 普通 shell 自己就会开，
  /// 详见下方 `_interactiveOn` 的说明（第 38 轮回归）。
  ///
  /// 用途（第 274/275 轮）：用户实测"进 htop 不能滑（很好），但旋转到横屏又能滑了，
  /// 转回竖屏还能滑"。根因是旋转让**视口变矮**，主屏回滚缓冲立刻出现滚动余量
  /// （`maxScrollExtent > 0`）；xterm 的 `simulateScroll` 只作用于**备用屏**，
  /// 所以只能在这里识别"有交互式程序在跑"，再由页面禁掉手指拖动滚动。
  final ValueNotifier<bool> interactiveProgram = ValueNotifier<bool>(false);

  /// @brief 每次终端输出都自增。
  ///
  /// 让终端那层的 `ScrollConfiguration`（拖动设备集合）能在
  /// **备用屏进出时立刻重算**，而不是等下一次无关的重建。
  ///
  /// 没有它会出这个错：进入 htop/vim 后没有新的重建，页面仍保留"允许拖动"的旧配置，
  /// 于是一边跑全屏程序一边还能滑动主屏回滚 —— 用户实测「交互界面又可以滑动了」。
  /// 备用屏切换序列本身就会产生一次输出，htop 之类持续重绘更是每帧都会命中。
  final ValueNotifier<int> outputTick = ValueNotifier<int>(0);

  /// @brief 入站数据的**滚动尾巴**（最近 24 个字符）。
  ///
  /// 必须要有它：实测（第 281 轮）交互式私有模式会被**分块**送达 —— 现场注入
  /// `ESC[?1000h` 时，服务端回显把 `\x1b`、`[`、`?`、`1`、`0`、`0`、`0`、`h`
  /// 拆进了不同的数据块，只看单块的 `data.contains('\x1b[?')` 永远匹配不上，
  /// 于是第 275 轮那条"识别交互式程序 → 禁手指拖动"的链路对分块序列完全失效。
  /// 拼接"尾巴 + 本块"再扫描，就能跨块命中；尾巴只保留 24 字符，不会误伤。
  String _interactiveTail = '';

  /// @brief 只有**备用屏**才算"有交互式全屏程序在跑"。
  ///
  /// 锐边（第 38 轮，用户报的回归）：早先这里把鼠标上报模式
  /// `1000/1002/1003` 也算了进来，但**普通 shell 自己就会开这些模式**
  /// （readline 的鼠标支持等），于是日常敲命令时标志为真、`dragDevices` 被置空，
  /// 手指滑动彻底失效 —— 表现就是"普通模式下不能滑屏滚动"。
  /// 备用屏 `1049`（htop/vim/less 用它）才是可靠的全屏信号；`47` 是它的旧写法。
  static final RegExp _interactiveOn = RegExp(r'\x1b\[\?(?:1049|47)h');
  /// @brief 备用屏**退出**序列的匹配式，与 `_interactiveOn` 成对使用。
  static final RegExp _interactiveOff = RegExp(r'\x1b\[\?(?:1049|47)l');

  /// @brief 入站数据的唯一入口。
  ///
  /// 先把"滚动尾巴 + 本块"拼起来扫私有模式，再交给终端渲染。
  void _writeToTerminal(String data) {
    final window = _interactiveTail + data;
    if (window.contains('\x1b[?')) {
      // 以窗口里**最后**一个匹配为准（第 282 轮记录的锐边：窗口尾巴里还留着上一个
      // `h` 时，`leaves && !enters` 会把紧随其后的 `l` 当成"又来了一个进入"，
      // 于是退出序列被漏掉、标志永远不复位）。
      final ons = _interactiveOn.allMatches(window).toList();
      final offs = _interactiveOff.allMatches(window).toList();
      final onAt = ons.isEmpty ? -1 : ons.last.start;
      final offAt = offs.isEmpty ? -1 : offs.last.start;
      final leaving = offAt > onAt;
      if (leaving) {
        if (interactiveProgram.value) interactiveProgram.value = false;
      } else if (!interactiveProgram.value) {
        interactiveProgram.value = true;
      }
    }
    _interactiveTail =
        window.length > 24 ? window.substring(window.length - 24) : window;
    terminal.write(data);
    // 写完再自增：此时 `terminal.isUsingAltBuffer` 已是新值，页面据此重算拖动设备。
    outputTick.value++;
  }

  /// @brief 构造会话控制器；连接所需的数据与交互回调全部由参数注入。
  ///
  /// 创建时不会自动连接，要由调用方显式调用 [connect]。
  TerminalSessionController({
    required this.connection,
    required this.identities,
    required this.hostKeyStore,
    required this.settings,
    this.onHostKeyChallenge,
    this.onPasswordPrompt,
    this.portForwards = const <PortForward>[],
    this.onBell,
  });

  /// @brief 本会话对应的连接配置（地址、端口、昵称等）。
  final Connection connection;
  /// @brief 认证可用的私钥/身份列表。
  final List<Identity> identities;
  /// @brief 主机密钥仓库，用于连接时的已知主机校验。
  final HostKeyStore hostKeyStore;
  /// @brief 应用设置，字号、终端类型、响铃模式等都从这里读。
  final SettingsController settings;
  /// @brief 主机密钥质询回调。
  ///
  /// 交互式回调归「当前附着在会话上的终端页」所有。
  ///
  /// 会话可能在没有界面的时候继续跑（原版靠前台 Service，本项目靠
  /// `SessionHost`），此时没有页面可以弹窗，两个回调为 null：
  /// 主机密钥校验按拒绝处理，密码提示返回 null。
  HostKeyConfirm? onHostKeyChallenge;
  /// @brief 密码/口令提示回调；没有界面附着时为 null，此时返回 null。
  CredentialPrompt? onPasswordPrompt;

  /// @brief 端口转发通知上「停止」动作的文案（原版 `@string/disconnect`）。
  ///
  /// 本地化要 `BuildContext`，所以由界面层注入，默认英文。
  String disconnectLabel = 'Disconnect';

  /// @brief 挂在 [connection] 上的端口转发。
  ///
  /// 会话建立后自动启动，断开时回收 ——
  /// 对应原版把转发绑在连接上（`portforward.connection`）的行为。
  final List<PortForward> portForwards;

  /// @brief 终端响铃回调。
  ///
  /// 原版按 `terminal:bell_mode` 决定震动 / 通知 / 忽略。
  void Function()? onBell;

  /// @brief 回滚缓冲行数。
  ///
  /// 依据：原版 `TermSession` 的 `TRANSCRIPT_ROWS = 0x2710`，即 **10000 行**。
  static const int scrollbackLines = 10000;

  /// @brief `terminal:font_size` 到 Flutter 逻辑字号的换算系数。
  ///
  /// 原版把该设置直接当作 emulator 的像素字号使用，取值范围 1..30、默认 8；
  /// 直接套用会让默认值小到看不清。这里按 **1.75** 换算（默认 8 → 14 逻辑像素），
  /// 属于**标定值**，待与真机截图比对后再微调。
  static const double fontSizeScale = 1.75;

  /// @brief 底层 xterm 终端实例，承载回滚缓冲与转义序列解析。
  late final Terminal terminal = Terminal(
    maxLines: scrollbackLines,
    platform: TerminalTargetPlatform.android,
    onOutput: _handleTerminalOutput,
    onResize: _handleTerminalResize,
    onBell: _handleBell,
    onTitleChange: _handleTitleChange,
  );

  /// @brief 底层 SSH 会话，未连接或已断开时为 null。
  JuiceSshSession? _session;
  /// @brief 远端输出流的订阅，断开时取消。
  StreamSubscription<String>? _outputSubscription;

  /// @brief 本次会话的端口转发运行时，会话建立后创建、断开时回收。
  PortForwardService? _forwardService;

  /// @brief 当前会话状态，初始为 [TerminalSessionState.connecting]。
  TerminalSessionState _state = TerminalSessionState.connecting;
  /// @brief 连接进度文案，显示在连接页上。
  String _progress = '正在连接';
  /// @brief 连接失败的原因，失败时非 null。
  SshFailure? _failure;
  /// @brief 远端通过转义序列设置的窗口标题，可能为 null。
  String? _terminalTitle;
  /// @brief 当前终端列数，随 [Terminal] 的 resize 回调更新。
  int _columns = 80;

  /// @brief 初始行数。
  ///
  /// 原版 `initializeEmulator(80, 25)`，所以是 25 行而不是常见的 24。
  int _rows = 25;

  /// @brief Ctrl 待生效标志。
  ///
  /// 原版按下 Ctrl 后按钮保持高亮，作用于**下一个字符**。
  bool _ctrlArmed = false;

  /// @brief Alt 待生效标志。原版按下 Alt 会**立刻发送一个 ESC**，并保持高亮。
  bool _altArmed = false;

  /// @brief 用户按音量键临时调整的字号；为 null 时用设置里的值。
  int? _fontSizeOverride;

  /// @brief 当前会话状态。
  ///
  /// 页面用 [ChangeNotifier] 的通知机制监听它的变化。
  TerminalSessionState get state => _state;
  /// @brief 连接进度文案，连接过程中会被不断更新。
  String get progress => _progress;
  /// @brief 失败原因，未失败时为 null。
  SshFailure? get failure => _failure;

  /// @brief 会话标题。
  ///
  /// 优先用远端通过转义序列设置的标题，否则用连接昵称。
  String get title =>
      (_terminalTitle == null || _terminalTitle!.isEmpty)
          ? connection.nickname
          : _terminalTitle!;

  /// @brief Ctrl 是否处于待生效（高亮）状态。
  bool get ctrlArmed => _ctrlArmed;
  /// @brief Alt 是否处于待生效（高亮）状态。
  bool get altArmed => _altArmed;

  /// @brief 当前字号（逻辑像素）。
  ///
  /// 由设置里的原始值乘 [fontSizeScale] 换算而来。
  double get fontSize {
    final raw = _fontSizeOverride ?? settings.terminalFontSize;
    return raw * fontSizeScale;
  }

  /// @brief 当前字号对应的原始设置值，用于设置页回显。
  int get fontSizeSetting => _fontSizeOverride ?? settings.terminalFontSize;

  /// @brief 传给 [Terminal] 的字体样式（字号与字体族）。
  TerminalStyle get textStyle => TerminalStyle(
        fontSize: fontSize,
        fontFamily: TerminalFonts.familyOf(settings.terminalFont),
        fontFamilyFallback: TerminalFonts.fallback,
      );

  /// @brief 终端原始配色主题，供菜单、失败页等使用。
  TerminalTheme get theme => JuiceTerminalThemes.build(settings.terminalThemeIndex);

  /// @brief 终端**画布**用的配色：底色额外叠一层白色（原版实测 12%）。
  ///
  /// `TerminalView` 自己会画底色，所以必须把叠加写进传给它的主题里；
  /// [theme] 保持原始值，供菜单/失败页等其它地方使用。
  TerminalTheme get surfaceTheme => JuiceTerminalThemes.build(
        settings.terminalThemeIndex,
        surfaceOverlay: JuiceTerminalThemes.surfaceOverlay,
      );

  /// @brief 快捷键栏底色。
  ///
  /// 原版比画布略暗，见 [JuiceTerminalThemes.keyBarOverlay]。
  Color get keyBarBackground => JuiceTerminalThemes.blendWithForeground(
        settings.terminalThemeIndex,
        JuiceTerminalThemes.keyBarOverlay,
      );

  /// @brief 等交互回调贴上（最多 5 秒，每 50ms 查一次）。
  ///
  /// 消除 `SessionHost.acquire` 与 `terminal_page` 之间"先建会话、后挂回调"的竞态：
  /// 首次连接新主机时，主机密钥质询会早于回调到达。
  Future<T?> _awaitHandler<T>(T? Function() read) async {
    var value = read();
    for (var i = 0; i < 100 && value == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      value = read();
    }
    return value;
  }

  /// @brief 建立连接。
  Future<void> connect() async {
    _state = TerminalSessionState.connecting;
    _failure = null;
    _progress = '正在连接 ${connection.address}:${connection.port}';
    notifyListeners();

    try {
      final session = await SshConnector.connect(
        connection: connection,
        identities: identities,
        hostKeyStore: hostKeyStore,
        // 页面附着与会话开始连接之间存在竞态：`SessionHost.acquire` 先构造控制器
        // （`connect()` 随即开始），`terminal_page` 之后才
        // `_controller.onHostKeyChallenge = …`。首次连接**新主机**时，主机密钥质询
        // 会早于回调到达；若此时立刻拒绝，"全新安装后第一次连接任何新主机"必然
        // 失败，界面还只显示误导性的"连接超时"（第 26 轮定位到）。
        // 所以这里**短暂等待**回调贴上；确实没有页面附着（后台会话）才拒绝。
        onHostKey: (challenge) async {
          final handler = await _awaitHandler(() => onHostKeyChallenge);
          if (handler == null) return HostKeyVerdict.rejected;
          return handler(challenge);
        },
        // 口令提示同理：早到一步就拿不到页面回调，直接放弃会表现成认证失败。
        onPassword: (prompt, echo) async {
          final handler = await _awaitHandler(() => onPasswordPrompt);
          if (handler == null) return null;
          return handler(prompt, echo);
        },
        onProgress: (message) {
          _progress = message;
          notifyListeners();
        },
        terminalType: settings.terminalType,
        columns: _columns,
        rows: _rows,
        useUtf8: settings.terminalUtf8,
        agentForwarding: settings.sshAgentForwarding,
      );

      _session = session;
      _state = TerminalSessionState.connected;

      // 端口转发绑在连接上：会话一建立就启动，断开时由 _teardown 统一回收。
      // 单条转发起不来（端口被占用、服务器拒绝）不影响会话本身。
      if (portForwards.isNotEmpty) {
        final forwardService = PortForwardService(
          session: session,
          connection: connection,
          disconnectLabel: disconnectLabel,
        );
        _forwardService = forwardService;
        // 列表页靠这个注册表知道「这条转发现在通没通」，并驱动它的开关。
        if (connection.id != 0) {
          PortForwardRegistry.instance.register(connection.id, forwardService);
        }
        unawaited(forwardService.startAll(portForwards));
      }

      // 远端输出按 UTF-8 流式解码：用 StreamTransformer 形式可以正确处理
      // 被切分到两个数据块里的多字节字符（直接对每块 decode 会出现乱码）。
      final decoded = session.output
          .cast<List<int>>()
          .transform(settings.terminalUtf8
              ? const Utf8Decoder(allowMalformed: true)
              : const Latin1Decoder());
      _outputSubscription = decoded.listen(
        _writeToTerminal,
        onDone: _handleRemoteClosed,
        onError: (Object error) {
          _fail(SshFailure.from(error, connection));
        },
      );

      notifyListeners();
    } catch (error) {
      _fail(error is SshFailure ? error : SshFailure.from(error, connection));
    }
  }

  /// @brief 主动断开当前会话。
  ///
  /// 由终端页在「返回键 → 否」这条路径上调用，对应原版
  /// `BackgroundPrompt` 选择「否」时执行的断连分支。
  Future<void> disconnect() async {
    await _teardown();
    if (_state != TerminalSessionState.failed) {
      _state = TerminalSessionState.closed;
    }
    notifyListeners();
  }

  /// @brief 断开并重新连接。
  Future<void> reconnect() async {
    await _teardown();
    await connect();
  }

  /// @brief 把会话置为失败态并广播原因。
  void _fail(SshFailure failure) {
    _failure = failure;
    _state = TerminalSessionState.failed;
    notifyListeners();
  }

  /// @brief 远端输出流正常结束（shell 退出）时的收尾处理。
  void _handleRemoteClosed() {
    if (_state == TerminalSessionState.connected) {
      _state = TerminalSessionState.closed;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------- 终端回调 --

  /// @brief 设备属性（DA）应答：`ESC[?1;2c` / `ESC[>0;276;0c` 这类。
  ///
  /// xterm 会替终端回答设备属性查询（`ESC[c` → `ESC[?1;2c`），但它自己的解析器把
  /// **任何**以 `c` 结尾的 CSI 都当查询 —— 分不清自己那条应答和查询的区别。于是
  /// 远端 pty 只要处于回显状态（shell 提示符下、vi 启动早期等），应答被回显回来就
  /// **再触发一次应答**，形成无限 ping-pong。设备实测（`tools/_sshd.py --alt-screen`，
  /// 服务端日志里刷满 `收到 7 字节: b'\x1b[?1;2c'`）：vi 拿到的是这串垃圾当输入，
  /// 这正是用户报的"vi 不能输入、屏幕上出现字面 `^[[?1;2c`、按 `:` 也进不了命令模式"。
  ///
  /// 所以把这类应答**整条丢掉**，循环两个方向都断掉（我们不回答 → 远端没得回显；
  /// 万一远端回显过来，xterm 再生成的应答同样被丢掉）。原版 JuiceSSH 的老终端也不做
  /// 这套应答，丢掉反而更接近 1:1。
  static final RegExp _deviceAttributesAnswer =
      RegExp(r'^\x1b\[[>?][0-9;]*c$');

  /// @brief 终端要往远端发送数据。
  void _handleTerminalOutput(String data) {
    final session = _session;
    if (session == null || _state != TerminalSessionState.connected) return;

    if (_deviceAttributesAnswer.hasMatch(data)) {
      return;
    }

    var payload = data;

    // Ctrl 待生效：把下一个字符转成控制字符，然后解除待生效状态。
    // 这正是原版 `EmulatorView.sendControlKey()` 的行为。
    if (_ctrlArmed && payload.length == 1) {
      final converted = _controlCharacter(payload.codeUnitAt(0));
      if (converted != null) {
        payload = String.fromCharCode(converted);
        _setCtrlArmed(false);
      }
    }

    session.write(payload);
  }

  /// @brief 字符 → 控制字符。
  ///
  /// 与原版 emulator 的换算一致：
  /// `a`–`z` 映射到 1–26，`@`–`_`（含 `[ \ ] ^ _`）映射到 0–31，`?` 映射到 127。
  static int? _controlCharacter(int code) {
    if (code >= 0x61 && code <= 0x7A) return code - 0x60; // a-z → ^A..^Z
    if (code >= 0x40 && code <= 0x5F) return code - 0x40; // @A-Z[\]^_ → 0..31
    if (code == 0x3F) return 0x7F; // ? → DEL
    return null;
  }

  /// @brief 终端尺寸回调：记住新的列 / 行数并同步给远端 PTY。
  void _handleTerminalResize(
    int width,
    int height,
    int pixelWidth,
    int pixelHeight,
  ) {
    _columns = width;
    _rows = height;
    _session?.resize(width, height, pixelWidth: pixelWidth, pixelHeight: pixelHeight);
  }

  /// @brief 响铃回调，按设置里的响铃模式决定震动 / 通知 / 忽略。
  void _handleBell() {
    // "终端确实收到了 \a" 的直接证据（release 构建也会打到 logcat 的 flutter 标签）。
    // 没有这行时，"模式 1 下没有通知"既可能是走了震动分支，也可能是铃压根没响。
    switch (settings.terminalBellMode) {
      case 1:
        // 震动
        HapticFeedback.vibrate();
      case 2:
        onBell?.call();
      default:
        break;
    }
  }

  /// @brief 窗口标题变化回调（远端通过转义序列设置）。
  void _handleTitleChange(String title) {
    _terminalTitle = title;
    notifyListeners();
  }

  // ------------------------------------------------------------ 按键 --

  /// @brief 处理额外键行抛出的 tag。
  ///
  /// 正数 tag 是 Android `KeyEvent` 键码，映射到 xterm 的 [TerminalKey]，
  /// 这样连 `DECCKM`（应用方向键模式）都能像原版一样被正确响应 ——
  /// 原版正是把按键交回系统分发、由终端模拟器生成序列的。
  void handleKeyTag(int tag) {
    final session = _session;

    switch (tag) {
      case KeyTag.pipe:
      case KeyTag.minus:
      case KeyTag.slash:
        // 这三个键面是**可打印字符**（`|` `-` `/`）。原版把它们当按键交给系统分发、
        // 由终端模拟器翻译成字符；但 xterm 的默认输入处理器里**没有**
        // `TerminalKey.minus` / `TerminalKey.slash` 分支（整个包里这两个名字只出现在
        // `qt_keyname.dart` / `input_map.dart` 的映射表里），`keyInput` 会返回 false
        // 且什么都不发 —— 用户实测"按了 `/` 和 `-` 没有输入任何字符"正是如此。
        // 所以和 `|` 走同一条路：直接写字符。
        terminal.textInput(switch (tag) {
          KeyTag.minus => '-',
          KeyTag.slash => '/',
          _ => '|',
        });
        return;

      case KeyTag.ctrl:
        _setCtrlArmed(!_ctrlArmed);
        return;

      case KeyTag.alt:
        // 原版：立刻写入一个 ESC 作为 meta 前缀，同时切换高亮。
        _setAltArmed(!_altArmed);
        session?.writeBytes(const [0x1b]);
        return;

      case KeyTag.fn:
      case KeyTag.backToMain:
      case KeyTag.toggleKeyboard:
        // 这三个由界面层处理（翻页 / 切换软键盘），此处不产生终端输入。
        return;
    }

    // F1–F12：序列随终端类型变化。
    final functionNumber = KeyTag.functionKeyNumber(tag);
    if (functionNumber > 0) {
      final sequence =
          EscapeCharacters(settings.terminalType).functionKey(functionNumber);
      // 原版 vt100 的 F11/F12 是空串，按下不发送任何内容。
      if (sequence.isNotEmpty) session?.write(sequence);
      return;
    }

    final key = _terminalKeyForAndroidKeyCode(tag);
    if (key == null) return;
    terminal.keyInput(key, ctrl: _ctrlArmed, alt: _altArmed);

    // 原版 `keyboardPress` 在走完按键分发后调用 `n()`，会**把 Ctrl 与 Alt
    // 两个锁定状态一起清掉** —— 也就是说它们只作用于紧接的一个按键。
    if (_ctrlArmed || _altArmed) {
      _ctrlArmed = false;
      _altArmed = false;
      notifyListeners();
    }
  }

  /// @brief Android `KeyEvent` 键码 → xterm 按键；无对应项时返回 null。
  static TerminalKey? _terminalKeyForAndroidKeyCode(int keyCode) {
    switch (keyCode) {
      case KeyTag.dpadUp:
        return TerminalKey.arrowUp;
      case KeyTag.dpadDown:
        return TerminalKey.arrowDown;
      case KeyTag.dpadLeft:
        return TerminalKey.arrowLeft;
      case KeyTag.dpadRight:
        return TerminalKey.arrowRight;
      case KeyTag.tab:
        return TerminalKey.tab;
      case KeyTag.minus:
        return TerminalKey.minus;
      case KeyTag.slash:
        return TerminalKey.slash;
      case KeyTag.pageUp:
        return TerminalKey.pageUp;
      case KeyTag.pageDown:
        return TerminalKey.pageDown;
      case KeyTag.escape:
        return TerminalKey.escape;
      case KeyTag.moveHome:
        return TerminalKey.home;
      case KeyTag.moveEnd:
        return TerminalKey.end;
      default:
        return null;
    }
  }

  /// @brief 设置 Ctrl 待生效状态并刷新界面高亮。
  void _setCtrlArmed(bool value) {
    _ctrlArmed = value;
    notifyListeners();
  }

  /// @brief 设置 Alt 待生效状态并刷新界面高亮。
  void _setAltArmed(bool value) {
    _altArmed = value;
    notifyListeners();
  }

  /// @brief 解除两个修饰键的待生效状态（例如点开菜单时）。
  void clearModifiers() {
    if (!_ctrlArmed && !_altArmed) return;
    _ctrlArmed = false;
    _altArmed = false;
    notifyListeners();
  }

  // ---------------------------------------------------------- 字号 --

  /// @brief 在会话中调整字号。原版支持用音量键操作。
  void adjustFontSize(int delta) {
    final next = (fontSizeSetting + delta).clamp(1, 30);
    if (next == fontSizeSetting) return;
    _fontSizeOverride = next;
    // 原版用 `Config.h("terminal:font_size", …)` 持久化，所以音量键改过的字号
    // 下次连接仍然生效（规范里 `terminal:font_size` 那一行）。
    SettingsController.instance.setTerminalFontSize(next);
    notifyListeners();
  }

  // ---------------------------------------------------------- 输入 --

  /// @brief 粘贴文本。走 [Terminal.paste] 以便遵循远端的 bracketed paste 设置。
  void paste(String text) => terminal.paste(text);

  /// @brief 直接在会话里执行一条命令（用于 Snippet）。
  ///
  /// 原版行为是把命令内容写入终端（而不是另开 exec 通道），
  /// 这样用户能看见命令回显，也符合"在会话里跑脚本"的预期。
  void runSnippet(String content) {
    if (content.isEmpty) return;
    _session?.write(content.endsWith('\n') ? content : '$content\n');
  }

  /// @brief 往会话写入原始字节（例如 Ctrl+C）。
  void sendBytes(List<int> bytes) => _session?.writeBytes(bytes);

  /// @brief 往会话写入文本。
  void sendText(String text) => _session?.write(text);

  /// @brief 取当前会话的可见文本，用于 "Copy (whole session)"。
  String get bufferText => terminal.buffer.getText().trimRight();

  /// @brief 回收会话资源：停端口转发、取消输出订阅、关闭 SSH 会话。
  Future<void> _teardown() async {
    final forwardService = _forwardService;
    _forwardService = null;
    if (forwardService != null) {
      if (connection.id != 0) {
        PortForwardRegistry.instance.unregister(connection.id, forwardService);
      }
      await forwardService.close();
    }
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    await _session?.close();
    _session = null;
  }

  /// @brief 释放控制器：先断开会话，再交给父类销毁通知机制。
  @override
  Future<void> dispose() async {
    await _teardown();
    super.dispose();
  }
}
