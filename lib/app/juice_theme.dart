import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'juice_colors.dart';

/// @brief 开关「关」态的拇指颜色（原版实测 `#B9B9B9`，19.4dp 圆）。
const Color _switchThumbOff = Color(0xFFB9B9B9);

/// @brief 开关「关」态的轨道颜色（原版实测 `#E5E5E5`，是描边而非填充）。
const Color _switchTrackOff = Color(0xFFE5E5E5);

/// @brief 开关「开」态的拇指颜色（原版实测 `#566C73`）。
const Color _switchThumbOn = Color(0xFF566C73);

/// @brief 开关「开」态的轨道填充色（原版实测 `#CDD3D5`）。
const Color _switchTrackOn = Color(0xFFCDD3D5);

/// @brief 把原版 JuiceSSH 的 AppCompat 主题翻译成 Flutter 的 [ThemeData]。
///
/// 关键取值来自 `res/values/styles.xml` 的 `Theme.JuiceSSH` 一系：
///
/// * `colorPrimary`       = `@color/primary_bold`
/// * `colorPrimaryDark`   = `@color/primary_darker`（ActionBar 背景）
/// * `colorAccent`        = `@color/accent_bold`
/// * `android:windowBackground` = `@color/background`
/// * ActionBar 标题       = 白色、加粗、24sp
///
/// 原版是 2020 年的 AppCompat/Material 1 风格，所以这里刻意**关闭 Material 3**，
/// 否则组件形状与配色会和原版明显不同。
abstract final class JuiceTheme {
  /// @brief ActionBar 标题字号：
  /// `Theme.JuiceSSH.Material.Actionbar.Text` 的 24.0sp。
  static const double actionBarTitleSize = 24;

  /// @brief 原版 ActionBar 默认高度（Material 规范 56dp）。
  static const double actionBarHeight = 56;

  /// @brief 按调色板构建整套 [ThemeData]（关闭 Material 3）。
  static ThemeData build(JuicePalette palette) {
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.primaryBold,
      brightness: brightness,
    ).copyWith(
      primary: palette.primaryDarker,
      onPrimary: palette.actionBarTitle,
      secondary: palette.accentBold,
      onSecondary: palette.background,
      surface: palette.background,
      onSurface: palette.textNormal,
      error: const Color(0xFFB00020),
    );

    final base = ThemeData(
      useMaterial3: false,
      brightness: brightness,
      colorScheme: colorScheme,
      primaryColor: palette.primaryDarker,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.cardItemDivider,
      splashColor: palette.cardItemPressed.withValues(alpha: 0.16),
      highlightColor: palette.accentLighterTransparent,
      // UI 正文字体：设备上原版用的就是系统 Roboto，而 Flutter 引擎只内置了
      // Roboto-Regular，`fontWeight: bold` 只能合成描边。实测同一屏设置页的分区
      // 标题（原版用框架样式 `?android:listSeparatorTextViewStyle`，确实是 bold）：
      // 字号、宽度、位置、颜色都与原版一致，但克隆的饱和黄像素多 29%，而普通正文
      // 只差 ±3% —— 即差在粗体字形上。这里改用从设备取回并实例化的静态 Roboto
      // （见 pubspec.yaml 的 `JuiceUiRoboto`），粗体才是真正的 Roboto Bold。
      fontFamily: 'JuiceUiRoboto',
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: palette.actionBarBackground,
        foregroundColor: palette.actionBarTitle,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        // 状态栏：原版 `Theme.JuiceSSH` 里 `colorPrimaryDark = @color/primary_darker`，
        // 而 `colorPrimaryDark` 就是 API 21+ 的状态栏底色 —— 所以原版的状态栏与
        // ActionBar **同色且连续**。设备实测原版截图 `o_d_ab.png`（暗）/`o_ed.png`（亮）
        // 的 y0..y260 主色分别是 `(213,186,49)` = #D5BA31 与 `(240,210,53)` = #F0D235，
        // 中间没有黑色分界带。
        //
        // 图标是**白色**：原版 `windowLightStatusBar` 未开启，实测状态栏带内非底色像素
        // 只有 `(255,255,255)`（2043px）。故 statusBarIconBrightness 取 light。
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: palette.primaryDarker,
          statusBarIconBrightness: Brightness.light,
          // iOS 侧：底色是浅色黄，需要亮色内容。
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: palette.actionBarTitle,
          fontSize: actionBarTitleSize,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: palette.actionBarTitle),
        actionsIconTheme: IconThemeData(color: palette.actionBarTitle),
        toolbarTextStyle: TextStyle(
          color: palette.actionBarTitle,
          fontSize: actionBarTitleSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      // 弹出菜单：`Theme.JuiceSSH.Material.Actionbar.PopupMenu`
      //   android:popupBackground = @color/background
      //   android:textColor       = @color/text_normal
      popupMenuTheme: PopupMenuThemeData(
        color: palette.background,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: palette.textNormal, fontSize: 16),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        // 遮罩：原版实测亮色下 `#FFFFFF` 被压到 `#666666`，即 60% 黑
        // （`showDialog` 默认是 `Colors.black54`，只有 54%）。
        barrierColor: const Color(0x99000000),
        // 盒模型：窗口宽度 = 屏幕的 95%（`abc_dialog_min_width_minor`），
        // 再让出 9-patch 的 16dp 背景内缩，面板正好 940px（实测原版
        // `[70,892][1010,1573]`）。上下不对称是为了让对话框中心落在
        // 「状态栏之下、导航栏之上」的中点 1232.5
        //（+24dp 的上下留白会互相抵消，只有差值起作用）。
        //
        // 这一条是给**还在用原生 `AlertDialog`** 的那些对话框兜底的；
        // 新对话框请直接用 `JuiceAlertDialog`（它自己算 insets，
        // 不受这里写死的状态栏/导航栏高度影响）。
        insetPadding: const EdgeInsets.only(
          left: 26.3,
          right: 26.3,
          top: 72.8,
          bottom: 48,
        ),
        titleTextStyle: TextStyle(
          color: palette.textHeading,
          fontSize: 20,
          height: 1.362,
        ),
        contentTextStyle: TextStyle(
          color: palette.textNormal,
          fontSize: 16,
          height: 1.171,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.cardItemBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
      // 原版设置页用 `@drawable/highlight` 作背景，而它是个空 selector，
      // 也就是说设置项本身没有背景，只有点击涟漪。
      listTileTheme: ListTileThemeData(
        iconColor: palette.textHeading,
        textColor: palette.textNormal,
      ),
      dividerTheme: DividerThemeData(
        color: palette.cardItemDivider,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primaryDarker,
        foregroundColor: palette.actionBarTitle,
      ),
      // 开关（设置页的 `SwitchDBPreference` / `EncSwitchDBPreference`）。
      //
      // 实测原版真机（420dpi，Security Lock 关 / SSH Agent Forwarding 开）：
      //   关：**轨道是描边不是填充** `#E5E5E5`（约 2dp 描边），拇指 `#B9B9B9`；
      //   开：轨道填充 `#CDD3D5`，拇指 `#566C73`；
      //   轨道 82×37px = 31.2×14.1dp，拇指 51×51px = 19.4dp 圆。
      // Flutter 的 M2 `Switch` 轨道是 33×14dp、拇指 20dp，尺寸几乎一致，
      // 差别主要是配色：默认是 `#ADADAD` 描边 + `#F8F8F8` 拇指，比原版深一档。
      //
      // 注意 `#566C73` 与调色板里的 `accentBold`（亮色 `#586E75`）只差每通道 2，
      // 但那是**实测值**，就直接写实测值。第 65 轮补测了暗色主题下的关闭态：拇指
      // 同样是 `#B9B9B9`（实测 (185,185,185)），所以关闭态两种主题共用同一个常量。
      // 此前暗色走 `null` 即 Material 默认 `#BDBDBD`(189)，实测比原版浅 4/255。
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (palette.isDark ? palette.accentBold : _switchThumbOn)
              : _switchThumbOff,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (palette.isDark
                    ? palette.accentBold.withValues(alpha: 0.5)
                    : _switchTrackOn)
              : (palette.isDark ? null : Colors.transparent),
        ),
        // 关态是描边轨道；开态没有描边（填充块本身）。
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : (palette.isDark ? null : _switchTrackOff),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: palette.textNormal,
        displayColor: palette.textHeading,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: palette.textFormHeading),
        helperStyle: TextStyle(color: palette.textFormHeading),
        hintStyle: TextStyle(color: palette.textFormHeading),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.accentLighter),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.accentBold),
        ),
      ),
    );
  }

  /// @brief 亮色主题。
  static ThemeData get light => build(JuicePalette.light);

  /// @brief 暗色主题。
  static ThemeData get dark => build(JuicePalette.dark);
}

/// @brief 把当前生效的调色板挂到 widget 树上。
///
/// [ThemeData] 只覆盖了标准组件，而原版有大量自己指定的颜色
/// （列表行标题/副标题、卡片分隔线、复制提示条等），
/// 这些需要业务代码直接取调色板，所以单独用 InheritedWidget 提供。
class JuicePaletteScope extends InheritedWidget {
  /// @brief 创建调色板注入 widget。
  const JuicePaletteScope({
    required this.palette,
    required super.child,
    super.key,
  });

  /// @brief 要注入的调色板。
  final JuicePalette palette;

  /// @brief 取最近的调色板；未挂载时断言失败。
  static JuicePalette of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<JuicePaletteScope>();
    assert(scope != null, 'JuicePaletteScope 未挂载：请检查 app.dart 的根 widget');
    return scope!.palette;
  }

  /// @brief 调色板换了就通知依赖方重建。
  @override
  bool updateShouldNotify(JuicePaletteScope oldWidget) =>
      oldWidget.palette != palette;
}

/// @brief 给 [BuildContext] 加取调色板的便捷入口。
extension JuicePaletteContext on BuildContext {
  /// @brief 当前调色板。
  JuicePalette get palette => JuicePaletteScope.of(this);
}
