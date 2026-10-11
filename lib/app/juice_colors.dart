import 'package:flutter/material.dart';

/// 调色板 —— 逐项对应原版 JuiceSSH 3.2.2 的颜色资源。
///
/// 亮色取自 `res/values/colors.xml`，暗色取自 `res/values-night/colors.xml`。
/// 每个字段的注释里保留了原始资源名，方便与原版逐项核对。
@immutable
class JuicePalette {
  const JuicePalette({
    required this.isDark,
    required this.primaryBold,
    required this.primaryDarker,
    required this.primaryLighter,
    required this.accentBold,
    required this.accentDarker,
    required this.accentLighter,
    required this.accentLighterTransparent,
    required this.background,
    required this.buttonBackground,
    required this.buttonStroke,
    required this.buttonText,
    required this.cardItemBackground,
    required this.cardItemDivider,
    this.formDivider = const Color(0xFFE0E0E0),
    required this.cardItemPressed,
    required this.textForm,
    required this.textFormHeading,
    required this.textHeading,
    required this.textItemSubtitle,
    required this.textItemTitle,
    required this.textNormal,
    required this.textSubheading,
    required this.actionBarBackground,
    required this.actionBarTitle,
    required this.secondaryText,
  });

  /// 原版用 `Theme.AppCompat.DayNight` + `values-night` 覆盖来表达暗色。
  final bool isDark;

  // --- 品牌黄 ---
  /// `@color/primary_bold`
  final Color primaryBold;

  /// `@color/primary_darker` —— 也是 ActionBar 背景
  final Color primaryDarker;

  /// `@color/primary_lighter`
  final Color primaryLighter;

  // --- 强调色 ---
  /// `@color/accent_bold`，同时是主题的 `colorAccent`
  final Color accentBold;

  /// `@color/accent_darker`
  final Color accentDarker;

  /// `@color/accent_lighter`
  final Color accentLighter;

  /// `@color/accent_lighter_transparent`
  final Color accentLighterTransparent;

  // --- 背景与按钮 ---
  /// `@color/background`，也是 `android:windowBackground`
  final Color background;

  /// `@color/button_background`
  final Color buttonBackground;

  /// `@color/button_stroke`
  final Color buttonStroke;

  /// `@color/button_text`
  final Color buttonText;

  // --- 卡片 / 列表行 ---
  /// `@color/card_item_background`
  final Color cardItemBackground;

  /// `@color/card_item_divider`
  final Color cardItemDivider;

  /// 分组表单标题（`?android:listSeparatorTextViewStyle`）下方的整宽分隔线。
  ///
  /// 亮色为**实测值** `#E0E0E0`：`o_id.png` 的 y 396..400 / 987..991 各 5px
  /// @density 2.625 ≈ 2dp、x 42..1037 整宽；`o_ed.png` 另有 1567..1571 一条。
  /// 暗色实例覆写为 12% 白 —— **按 Android 惯例取值**，`.research` 里没有暗色
  /// 编辑页可供实测，属未验证项。
  final Color formDivider;

  /// `@color/card_item_pressed`
  final Color cardItemPressed;

  // --- 文字 ---
  /// `@color/text_form`
  final Color textForm;

  /// `@color/text_form_heading`
  final Color textFormHeading;

  /// `@color/text_heading`
  final Color textHeading;

  /// `@color/text_item_subtitle`
  final Color textItemSubtitle;

  /// `@color/text_item_title`
  final Color textItemTitle;

  /// `@color/text_normal`
  final Color textNormal;

  /// `@color/text_subheading`
  final Color textSubheading;

  /// ActionBar 背景：`Theme.JuiceSSH.Material.Actionbar` 的 `background`
  final Color actionBarBackground;

  /// ActionBar 标题：`Theme.JuiceSSH.Material.Actionbar.Text` 的 `android:textColor`
  final Color actionBarTitle;

  /// 暗色下 `@android:color/secondary_text_dark`，亮色下等于 `accent_bold`
  final Color secondaryText;

  /// 亮色：`res/values/colors.xml`
  static const JuicePalette light = JuicePalette(
    isDark: false,
    primaryBold: Color(0xFFFFE24C),
    primaryDarker: Color(0xFFF0D235),
    primaryLighter: Color(0xFFFFEE96),
    accentBold: Color(0xFF586E75),
    accentDarker: Color(0xFF073642),
    accentLighter: Color(0xFFBCCACF),
    accentLighterTransparent: Color(0x33BCCACF),
    background: Color(0xFFFFFFFF),
    buttonBackground: Color(0xFF586E75),
    buttonStroke: Color(0x00000000),
    buttonText: Color(0xFFFFFFFF),
    cardItemBackground: Color(0xFFFFFFFF),
    cardItemDivider: Color(0x33BCCACF),
    cardItemPressed: Color(0xFF586E75),
    textForm: Color(0xFF073642),
    textFormHeading: Color(0xFF586E75),
    textHeading: Color(0xFF586E75),
    textItemSubtitle: Color(0xFF586E75),
    textItemTitle: Color(0xFF073642),
    textNormal: Color(0xFF073642),
    textSubheading: Color(0xFF586E75),
    actionBarBackground: Color(0xFFF0D235),
    actionBarTitle: Color(0xFFFFFFFF),
    // 卡片右侧 FontAwesome 图标用的就是它（实测截图 #757575 = 54% 黑叠白）。
    secondaryText: Color(0x8A000000),
  );

  /// 暗色：`res/values-night/colors.xml`
  static const JuicePalette dark = JuicePalette(
    isDark: true,
    primaryBold: Color(0xFFD8C041),
    primaryDarker: Color(0xFFD5BA31),
    primaryLighter: Color(0xFFFFE24C),
    accentBold: Color(0xFFD5BA31),
    accentDarker: Color(0xFFD5BA31),
    accentLighter: Color(0xFFFFE24C),
    accentLighterTransparent: Color(0xFFFFE24C),
    background: Color(0xFF000000),
    buttonBackground: Color(0x00000000),
    buttonStroke: Color(0xFFD5BA31),
    buttonText: Color(0xFFD5BA31),
    cardItemBackground: Color(0xFF000000),
    cardItemDivider: Color(0x00000000),
    // 暗色无参照实测，按 Android 惯例取 12% 白（未验证项，见字段注释）。
    formDivider: Color(0x1FFFFFFF),
    cardItemPressed: Color(0xFFFFFFFF),
    textForm: Color(0xFFFFFFFF),
    textFormHeading: Color(0xFFBEBEBE),
    textHeading: Color(0xFFFFFFFF),
    textItemSubtitle: Color(0xFFBEBEBE),
    textItemTitle: Color(0xFFFFFFFF),
    textNormal: Color(0xFFFFFFFF),
    textSubheading: Color(0xFFBEBEBE),
    actionBarBackground: Color(0xFFD5BA31),
    actionBarTitle: Color(0xFFFFFFFF),
    secondaryText: Color(0xB3FFFFFF),
  );
}

/// 原版里与主题无关的固定颜色，散落在 `res/values/colors.xml`。
abstract final class JuiceFixedColors {
  /// `@color/titlebar_background`
  static const Color titlebarBackground = Color(0xC1000000);

  /// `@color/table_row_highlight`
  static const Color tableRowHighlight = Color(0x33BCCACF);

  /// `@color/log_viewer_background` / `@color/log_viewer_foreground`
  static const Color logViewerBackground = Color(0xFF000000);
  static const Color logViewerForeground = Color(0xFF00FF00);

  /// `@color/copy_instructions_background`
  static const Color copyInstructionsBackground = Color(0xFFF44336);

  /// `@color/copy_instructions_start_selection_background`
  static const Color copyInstructionsStartSelection = Color(0xFFF44336);

  /// `@color/copy_instructions_end_selection_background`
  static const Color copyInstructionsEndSelection = Color(0xFF4CAF50);

  /// `@color/copy_instructions_text`
  static const Color copyInstructionsText = Color(0xFFFFFFFF);

  /// `@color/pinlock_background`
  static const Color pinlockBackground = Color(0xFF000000);

  /// `@drawable/loading_screen` —— 终端连接中的径向渐变
  static const Color loadingScreenStart = Color(0xFF292929);
  static const Color loadingScreenEnd = Color(0xFF090909);
}

/// 原版 `arrays.xml` 里 `dark_theme_values` 的三个取值，注意顺序是 3/1/2。
enum AppThemeMode {
  /// value 3 —— 跟随系统
  automatic(3, 'Automatic (system default)'),

  /// value 1
  light(1, 'Light'),

  /// value 2
  dark(2, 'Dark');

  const AppThemeMode(this.value, this.label);

  final int value;
  final String label;

  static AppThemeMode fromValue(String? raw) {
    final parsed = int.tryParse(raw ?? '');
    // 第 62 轮实测推翻了这里原先的推断（原先认为 `res/values-v29/arrays.xml` 把
    // 取值覆盖成 `-1,1,2`，于是把 -1 当成"跟随系统"）。实测：原版与复刻的库里
    // `theme:dark` 都是 `-1`，模拟器 `cmd uimode night` = no（浅色系统），而原版
    // 连接编辑页正文底色采样为**纯黑 (0,0,0)**、文字 (190,190,190) —— 说明这个 -1
    // 在原版里落到的是 **Dark**，而不是跟随系统。`res/values/arrays.xml` 的官方
    // 取值只有 `3 = Automatic (system default)` / `1 = Light` / `2 = Dark`，-1 不在
    // 表内，属旧版遗留值，原版对表外值回退到深色默认（其 Settings 那一行也显示 Dark，
    // 与本复刻改完后一致）。
    if (parsed == -1) return AppThemeMode.dark;
    return AppThemeMode.values.firstWhere(
      (mode) => mode.value == parsed,
      orElse: () => AppThemeMode.automatic,
    );
  }

  ThemeMode get themeMode => switch (this) {
        AppThemeMode.automatic => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}
