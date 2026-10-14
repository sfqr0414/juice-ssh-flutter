import 'package:flutter/material.dart';

import '../data/juice_database.dart';
import '../screens/main_screen.dart';
import '../screens/pin_lock_screen.dart';
import 'app_resources.dart';
import 'i18n.dart';
import 'juice_colors.dart';
import 'juice_theme.dart';
import 'settings_controller.dart';

/// @brief 应用根 widget。
///
/// 负责把「数据库 / 设置 / 资源数组 / 文案」四样东西注入 widget 树，
/// 并让主题跟随 `theme:dark` 设置实时切换。
///
/// 主题的落地方式与原版 `Theme.AppCompat.DayNight` 对应：
/// 亮色取自 `res/values`、暗色取自 `res/values-night`，
/// 由 [JuiceTheme] 分别构建，再按当前明暗挑一套 [JuicePalette] 交给
/// [JuicePaletteScope]。
class JuiceApp extends StatefulWidget {
  /// @brief 创建应用根 widget。
  const JuiceApp({
    super.key,
    required this.database,
    required this.settings,
    required this.resources,
    required this.strings,
  });

  /// @brief 数据库连接，供各页面读写连接与凭据等数据。
  final JuiceDatabase database;
  /// @brief 应用设置，页面通过它读写 `config` 键。
  final SettingsController settings;
  /// @brief 反编译出的原版资源表。
  final AppResources resources;
  /// @brief 界面文案，供 `context.s()` 取用。
  final JuiceStrings strings;

  /// @brief 创建应用根 widget 对应的 State。
  @override
  State<JuiceApp> createState() => _JuiceAppState();
}

/// @brief 应用根状态：跟随主题重建，并负责应用锁的自动上锁。
class _JuiceAppState extends State<JuiceApp> with WidgetsBindingObserver {
  /// @brief 用它在任意时刻把解锁页压到导航栈顶（[PinLockScreen.show] 需要一个
  /// 位于 Navigator 之下的 context）。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// @brief 进入后台的时刻，用来和 `pinlock:timeout` 比较。
  DateTime? _pausedAt;

  /// @brief 解锁页是否已经在栈上，避免重复压栈。
  bool _lockVisible = false;

  /// @brief 注册生命周期观察者，并在首帧后排一次上锁检查。
  @override
  void initState() {
    super.initState();
    // 设置里选「跟随系统」时需要响应系统明暗切换，
    // 所以监听平台亮度变化并重建。
    WidgetsBinding.instance.addObserver(this);
    // 冷启动：只要设了应用锁就立刻要求解锁（对应原版 SessionedActivity
    // 在 onStart 时发现没有有效会话就弹 PinLock）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockIfNeeded());
  }

  /// @brief 注销生命周期观察者。
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// @brief 系统切换明暗时，仅在「跟随系统」下重建。
  @override
  void didChangePlatformBrightness() {
    if (widget.settings.themeMode == AppThemeMode.automatic) {
      setState(() {});
    }
  }

  /// @brief 进入后台时记下时刻，回到前台且超过超时时间就重新上锁。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        _pausedAt = null;
        if (pausedAt == null) return;
        // 只在后台停留超过 `lock_juicessh_after` 秒数时才重新上锁，
        // 短暂切走（比如接了个通知）不该打断终端会话。
        final idle = DateTime.now().difference(pausedAt);
        if (idle.inSeconds >= widget.settings.pinLockTimeoutSeconds) {
          _lockIfNeeded();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// @brief 设了应用锁且当前没有解锁页在栈上时，压入解锁页。
  void _lockIfNeeded() {
    if (!mounted) return;
    if (!widget.settings.pinLockEnabled) return;
    if (_lockVisible) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    _lockVisible = true;
    PinLockScreen.show(context).whenComplete(() {
      _lockVisible = false;
      if (mounted) setState(() {});
    });
  }

  /// @brief 当前是否使用暗色。
  ///
  /// 这里不去读 `Theme.of(context)`，因为本 widget 位于 [MaterialApp] 之上；
  /// 直接按设置项 + 平台亮度推导，顺序上更可靠。
  bool get _isDark => switch (widget.settings.themeMode) {
        AppThemeMode.light => false,
        AppThemeMode.dark => true,
        AppThemeMode.automatic =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  /// @brief 构建 `MaterialApp`，注入主题、调色板与文案。
  @override
  Widget build(BuildContext context) {
    // `SettingsController.themeMode` 是应用自己的枚举，
    // 再取一次 `.themeMode` 才是 Flutter 的 ThemeMode。
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final isDark = _isDark;
        return MaterialApp(
          title: 'JuiceSSH',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: JuiceTheme.light,
          darkTheme: JuiceTheme.dark,
          themeMode: widget.settings.themeMode.themeMode,
          // 调色板挂在 MaterialApp 之下，所有路由与对话框都能取到；
          // 文案同理，保证 `context.s(...)` 在任何页面可用。
          //
          // 外面这层 bottom padding 是当初为 `targetSdk=36` 打的补丁：Android 15+
          // 对 targetSdk 35+ 的应用强制 edge-to-edge，Flutter 会一路画到 2400px，
          // 右下角 FAB 与列表最后一行会被导航栏压住（原版窗口底边在 2337px）。
          // 第 57 轮已把 targetSdk 改回原版的 29（见 android/app/build.gradle.kts），
          // 系统会像对原版那样把窗口让到导航栏之上，于是这里取到的
          // `viewPadding.bottom` 是 0，这层 padding 自然退化成无操作。保留是为了
          // 兜住其它窗口几何情形（如分屏、异形屏底部缺口）。
          builder: (context, child) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: JuicePaletteScope(
              palette: isDark ? JuicePalette.dark : JuicePalette.light,
              child: JuiceI18n(
                strings: widget.strings,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}
