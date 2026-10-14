import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_resources.dart';
import '../app/i18n.dart';
import '../app/juice_colors.dart';
import '../app/juice_theme.dart';
import '../app/settings_controller.dart';
import '../data/juice_database.dart';
import '../terminal/terminal_pickers.dart';
import '../widgets/juice_alert_dialog.dart';
import '../widgets/juice_dialogs.dart';
import 'known_hosts_screen.dart';
import 'pin_lock_screen.dart';
import 'snippets_screen.dart';

/// @brief 读取 `assets/data/dimens.json` 里的尺寸。
///
/// 值形如 `16.0dp` / `12.0sp`。
///
/// 设置页用到的尺寸全部走这条路，避免把 dp 数值抄死在代码里。
double _dimenValue(String name, double fallback) {
  final raw = AppResources.instance.dimens[name];
  if (raw == null || raw.isEmpty) return fallback;
  return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? fallback;
}

/// @brief `pinlock:style` —— 区分「密码短语」与「数字 PIN」两种锁屏样式。
///
/// 2 表示数字 PIN（`xk0.onPreferenceChange` 在开启安全锁时写入的值）。
const String _keyPinlockStyle = 'pinlock:style';

/// @brief 设置页。
///
/// 严格对应反编译出的 `res/xml/settings.xml`：**5 个分组、20 个条目、顺序一致**。
/// 分组标题取 `general` / `app_security` / `terminal` / `mosh` / `about_us`
/// 五个文案键；每个条目的标题、副标题也全部是 `strings.json` 里真实存在的键。
///
/// 行布局对应 `res/layout/preference.xml`：
///
/// ```
/// LinearLayout(horizontal, gravity=center_vertical, minHeight=?listPreferredItemHeight)
/// ├─ RelativeLayout(padding=@dimen/activity_padding, weight=1)
/// │  ├─ TextView(id=title,   textSize=@dimen/text_item_title,    color=@color/text_item_title)
/// │  └─ TextView(id=summary, textSize=@dimen/text_item_subtitle, color=@color/text_item_subtitle, maxLines=2)
/// └─ LinearLayout(id=widget_frame, gravity=center_vertical, orientation=vertical)
/// ```
///
/// 三个开关行（`security_lock` / `utf8_support` / `ssh_agent_forwarding`）**不走**
/// 这个布局：`SwitchCompatPreference.onCreateView` 会无视 `android:layout`，
/// 强行 inflate `res/layout/switch_preference.xml`，它的区别只有两点 ——
/// `widget_frame` 多了 `@dimen/activity_padding` 内边距，并且整行套了
/// `style="@style/Theme.JuiceSSH.Material.SelectableListItem"`
/// （`android:background=@android:drawable/list_selector_background`）。
///
/// 其余行没有背景：原版每个设置项的 `android:background="@drawable/highlight"`
/// 是一个**空的 `<selector />`** —— 既没有背景色，也没有点击涟漪。
/// 所以这里普通行用 [GestureDetector]（无反馈），开关行才用 [InkWell]。
class SettingsScreen extends StatefulWidget {
  /// @brief 创建设置页 widget。
  const SettingsScreen({
    super.key,
    this.onManageSnippets,
    this.onAmazonEc2Link,
    this.onSoftwareLicenses,
  });

  /// @brief `action:manageSnippets` → 原版 `ManageSnippetsActivity`。
  ///
  /// 不传时默认打开本仓库的 [SnippetsScreen]（等价于原版跳转）；
  /// 传入则以此回调为准。
  final VoidCallback? onManageSnippets;

  /// @brief `action:manageEc2SyncProfiles` → 原版 `Ec2ProfilesActivity`。
  ///
  /// Pro 功能。
  final VoidCallback? onAmazonEc2Link;

  /// @brief `action:software_licenses` → 原版 `SoftwareLicensesActivity`。
  final VoidCallback? onSoftwareLicenses;

  /// @brief 创建本页的 State。
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// @brief 设置页状态：把 SettingsController 的值渲染成原版设置项列表。
class _SettingsScreenState extends State<SettingsScreen> {
  /// @brief 设置控制器单例；本页的读值与写值都走它。
  SettingsController get _settings => SettingsController.instance;

  /// @brief 构建设置页：5 个分组、20 个条目的列表。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s('settings'))),
      // 设置项的值会随操作变化（列表项副标题显示当前值），
      // 所以整个列表跟着 SettingsController 重建。
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => ListView(
          padding: EdgeInsets.zero,
          children: [
            // --- 分组 1：General（`@string/general`，key `general`）---
            _section(context, 'general', [
              _darkThemeRow(context),
              _actionRow(
                context,
                'manage_snippets',
                widget.onManageSnippets ?? _openSnippets,
                // 第 57 轮用运行中的原版逐行复核：这两行**没有**副标题。
                // （早前注释写的"实测三个 Pro 行都是 pro_users_only"是错的，
                // uiautomator 实测原版只有标题。）片段功能在本复刻里是
                // **可用**的，但外观仍与原版一致。
              ),
              _actionRow(
                context,
                'amazon_ec2_link',
                widget.onAmazonEc2Link ??
                    () => JuiceDialogs.notInThisBuild(
                          context,
                          title: context.s('amazon_ec2_link'),
                        ),
              ),
            ]),
            // --- 分组 2：App Security（`@string/app_security`，key `account`）---
            _section(context, 'app_security', [
              _switchRow(
                context,
                titleKey: 'security_lock',
                // 原版这一行的副标题是 `Lock app after 5min inactivity`
                // （`@string/lock_juicessh_after`），不是 `pro_users_only`：
                // uiautomator 实测该节点 y=1101，紧贴标题底边 1080，属同一行。
                subtitle: context.s('lock_juicessh_after'),
                value: _settings.pinLockEnabled,
                onChanged: _setSecurityLock,
              ),
              _actionRow(
                context,
                'clear_known_hosts',
                _clearKnownHosts,
                subtitle: context.s('removes_host_keys'),
                // 长按进入「已知主机」列表页。
                //
                // 原版没有这一页，只有这个破坏性的「全部清空」动作；
                // 长按原本无绑定，因此单击行为与观感完全不变。
                onLongPress: _openKnownHosts,
              ),
              _switchRow(
                context,
                titleKey: 'ssh_agent_forwarding',
                value: _settings.sshAgentForwarding,
                onChanged: _settings.setSshAgentForwarding,
              ),
            ]),
            // --- 分组 3：Terminal（`@string/terminal`，key `terminal`）---
            _section(context, 'terminal', [
              _terminalThemeRow(context),
              _terminalFontRow(context),
              _numberRow(
                context,
                titleKey: 'font_size',
                labelKey: 'font_size',
                messageKey: 'you_can_adjust_the_font',
                min: 1,
                max: 30,
                current: _settings.terminalFontSize,
                onChanged: _settings.setTerminalFontSize,
              ),
              _numberRow(
                context,
                titleKey: 'terminal_margin',
                labelKey: 'pixels',
                messageKey: 'specify_the_terminal_margin',
                min: 0,
                max: 128,
                current: _settings.terminalMargin,
                subtitle: context.s('useful_for_those_with_screen_protectors'),
                onChanged: _settings.setTerminalMargin,
              ),
              _entryRow(
                context,
                titleKey: 'horizontal_swipe',
                names: AppResources.instance.swipeModeNames,
                values: AppResources.instance.swipeModeValues,
                currentValue: '${_settings.terminalSwipeMode}',
                onChanged: (value) =>
                    _settings.setTerminalSwipeMode(int.tryParse(value) ?? 0),
              ),
              _switchRow(
                context,
                titleKey: 'utf8_support',
                value: _settings.terminalUtf8,
                onChanged: _settings.setTerminalUtf8,
              ),
              _entryRow(
                context,
                titleKey: 'emulator_type',
                names: AppResources.instance.terminalTypeTitles,
                values: AppResources.instance.terminalTypeValues,
                currentValue: _settings.terminalType,
                onChanged: _settings.setTerminalType,
              ),
              _entryRow(
                context,
                titleKey: 'terminal_bell',
                names: AppResources.instance.bellModeNames,
                values: AppResources.instance.bellModeValues,
                currentValue: '${_settings.terminalBellMode}',
                onChanged: (value) =>
                    _settings.setTerminalBellMode(int.tryParse(value) ?? 0),
              ),
              _entryRow(
                context,
                titleKey: 'popup_keyboard_position',
                names: AppResources.instance.keyboardPositionNames,
                values: AppResources.instance.keyboardPositionValues,
                currentValue: '${_settings.terminalKeyboardPosition}',
                onChanged: (value) => _settings
                    .setTerminalKeyboardPosition(int.tryParse(value) ?? 0),
              ),
            ]),
            // --- 分组 4：Mosh（`@string/mosh`，key `mosh`）---
            _section(context, 'mosh', [
              _moshServerRow(context),
            ]),
            // --- 分组 5：About Us（`@string/about_us`，key `about_us`）---
            _section(context, 'about_us', [
              _actionRow(
                context,
                'rate_us',
                _rateUs,
                subtitle: context.s('it_really_helps'),
              ),
              _actionRow(
                context,
                'website',
                _openWebsite,
                subtitle: context.s('website_address'),
              ),
              _actionRow(
                context,
                'about',
                widget.onSoftwareLicenses ??
                    () => JuiceDialogs.notInThisBuild(
                          context,
                          title: context.s('about'),
                        ),
                subtitle: context.s('components_and_licenses'),
              ),
              _SettingsRow(
                title: context.s('application_version'),
                // 原版 `ej0.onResume()`：把 `unknown_version` 占位换成
                // `@string/app_name` + " v" + `PackageInfo.versionName`。
                subtitle: '${context.s('app_name')} v${AppResources.instance.versionName}',
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 分组骨架 --

  /// @brief 一个分组：标题 + 若干行，行之间补分隔线（最后一行后面不补）。
  Widget _section(BuildContext context, String titleKey, List<Widget> rows) {
    // **行与行之间没有分隔线。** 实测原版设置页任意两行交界处的整行像素都是
    // 纯白 `#FFFFFF`（扫了 y=546..561 与 730..745，非白像素为 0）；
    // 原版 dump 里两个相邻行的 bounds 也严格相接（`368..552` / `552..736`）。
    // 早先这里插了 `Divider(height: 1)`，既多画了 `#E0E0E0` 的线，
    // 又让每一行多出 2~3px，整页往下漂（实测到页尾累计 +80px）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryHeader(title: context.s(titleKey)),
        ...rows,
      ],
    );
  }

  // -------------------------------------------------------------- 行构造 --

  /// @brief 纯动作行（`ActionPreference`）。
  Widget _actionRow(
    BuildContext context,
    String titleKey,
    VoidCallback? onTap, {
    String? subtitle,
    VoidCallback? onLongPress,
  }) {
    return _SettingsRow(
      title: context.s(titleKey),
      subtitle: subtitle,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// @brief 开关行（`SwitchDBPreference` / `EncSwitchDBPreference`）。
  Widget _switchRow(
    BuildContext context, {
    required String titleKey,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return _SettingsRow(
      title: context.s(titleKey),
      subtitle: subtitle,
      selectable: true,
      trailing: Transform.scale(
        // 原版开关的**绘制**范围实测 85×59px（关）/ 86×63px（开），即约
        // 32.4×22.5dp；Flutter 的 M2 `Switch` 画出来是 100×64px（38.1×24.4dp），
        // 宽了约 5dp。0.88 是宽高两个比例（0.850 / 0.922）的折中，
        // 缩放后约 33.5×21.5dp，两个方向都只差 1dp 左右。
        // 布局尺寸不变（仍是 48dp 的点击区），所以不影响行高。
        scale: 0.88,
        child: _JuiceSwitchText(value: value, onChanged: onChanged),
      ),
      onTap: () => onChanged(!value),
    );
  }

  /// @brief `theme:dark` 行 —— 深色主题样式选择（`ListDBPreference`）。
  ///
  /// 选项来自 `@array/dark_theme_names`。
  ///
  /// 索引与取值都从 `@array/dark_theme_values` 反查，这样 API 29+ 把
  /// 「跟随系统」的取值从 `3` 改成 `-1` 也不影响。
  Widget _darkThemeRow(BuildContext context) {
    final names = AppResources.instance.darkThemeNames;
    final values = AppResources.instance.darkThemeValues;
    final mode = _settings.themeMode;
    var index = values.indexWhere((v) => AppThemeMode.fromValue(v) == mode);
    if (index < 0) index = 0;
    return _SettingsRow(
      title: context.s('dark_theme'),
      subtitle: _entryName(names, index),
      onTap: () async {
        final picked = await _pickEntry(
          context,
          title: context.s('dark_theme'),
          names: names,
          current: index,
        );
        if (picked == null) return;
        final value = picked < values.length ? values[picked] : values.first;
        await _settings.setThemeMode(AppThemeMode.fromValue(value));
      },
    );
  }

  /// @brief `terminal:theme` 行 —— 复用已有的配色选择器。
  ///
  /// 选择器布局来自 `terminal_theme_item.xml`。
  Widget _terminalThemeRow(BuildContext context) {
    final index = _settings.terminalThemeIndex;
    return _SettingsRow(
      title: context.s('theme_slash_colors'),
      subtitle: _entryName(AppResources.instance.terminalThemeNames, index),
      onTap: () async {
        final picked = await TerminalPickers.pickTheme(context, index);
        if (picked == null) return;
        await _settings.setTerminalThemeIndex(picked);
      },
    );
  }

  /// @brief `terminal:font` 行 —— 复用已有的字体选择器。
  ///
  /// 选择器布局来自 `terminal_font_item.xml`。
  Widget _terminalFontRow(BuildContext context) {
    final name = _settings.terminalFont;
    return _SettingsRow(
      title: context.s('font'),
      subtitle: name,
      onTap: () async {
        final picked = await TerminalPickers.pickFont(context, name);
        if (picked == null) return;
        await _settings.setTerminalFont(picked);
      },
    );
  }

  /// @brief `NumberDBPreference` 行（`font_size` / `terminal:margin`）。
  Widget _numberRow(
    BuildContext context, {
    required String titleKey,
    required String labelKey,
    required String messageKey,
    required int min,
    required int max,
    required int current,
    required ValueChanged<int> onChanged,
    String? subtitle,
  }) {
    return _SettingsRow(
      title: context.s(titleKey),
      subtitle: subtitle,
      onTap: () async {
        final picked = await _pickNumber(
          context,
          title: context.s(titleKey),
          label: context.s(labelKey),
          message: context.s(messageKey),
          min: min,
          max: max,
          current: current,
        );
        if (picked == null) return;
        onChanged(picked);
      },
    );
  }

  /// @brief 普通 `ListDBPreference` 行：副标题显示当前取值的显示名。
  ///
  /// （原版
  /// `ListDBPreference$a` 给 `ListPreference` 设了 `%s`，所以副标题就是当前项）。
  Widget _entryRow(
    BuildContext context, {
    required String titleKey,
    required List<String> names,
    required List<String> values,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    var index = values.indexOf(currentValue);
    if (index < 0) index = 0;
    return _SettingsRow(
      title: context.s(titleKey),
      subtitle: _entryName(names, index),
      onTap: () async {
        final picked = await _pickEntry(
          context,
          title: context.s(titleKey),
          names: names,
          current: index,
        );
        if (picked == null || picked >= values.length) return;
        onChanged(values[picked]);
      },
    );
  }

  /// @brief `mosh:mosh-server`：`TextDBPreference`，副标题显示当前命令。
  ///
  /// （`TextDBPreference$a.b()` 里 `setSummary(text)`）。
  Widget _moshServerRow(BuildContext context) {
    final current = _settings.moshServerCommand;
    return _SettingsRow(
      title: context.s('server_command'),
      subtitle: current,
      onTap: () async {
        final picked = await JuiceDialogs.promptForText(
          context,
          title: context.s('server_command'),
          initialValue: current,
        );
        if (picked == null) return;
        await _settings.setMoshServerCommand(picked);
      },
    );
  }

  /// @brief 取显示名：索引越界时返回 null。
  String? _entryName(List<String> names, int index) =>
      index >= 0 && index < names.length ? names[index] : null;

  // ------------------------------------------------------------ 交互逻辑 --

  /// @brief `security_lock` 开关：先走 PIN 设置流程，成功后才启用。
  ///
  /// （原版 `PinManager.a()`），
  /// 设置成功才写 `pinlock:enabled=true`；关闭时清掉 PIN。
  Future<void> _setSecurityLock(bool enabled) async {
    if (enabled) {
      final done = await PinSetupScreen.show(context);
      if (!mounted || !done) return;
      await _settings.set(_keyPinlockStyle, '2');
      await _settings.setPinLockFailedAttempts(0);
      await _settings.setPinLockEnabled(true);
      return;
    }
    // 原版关闭时只写 `pinlock:enabled=false`（`xk0`），并不清 PIN；
    // 这里按本项目的需求一并清掉。
    await PinLockService.instance.clearPin();
    if (!mounted) return;
    await _settings.setPinLockEnabled(false);
  }

  /// @brief 打开片段管理页（原版 `ManageSnippetsActivity`）。
  void _openSnippets() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SnippetsScreen()),
    );
  }

  /// @brief 打开「已知主机」列表页（本复刻新增）。
  ///
  /// 原版只有下面的破坏性清空动作。
  void _openKnownHosts() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const KnownHostsScreen()),
    );
  }

  /// @brief `action:clear_known_hosts`。
  ///
  /// 原版 `ej0.u()`：标题 `clear_known_hosts`、正文 `are_you_sure_clear_known_hosts`、
  /// 按钮 `confirm` / `cancel`；清完弹出 `known_hosts_cleared`。
  Future<void> _clearKnownHosts() async {
    final s = context.s;
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('clear_known_hosts'),
      message: s('are_you_sure_clear_known_hosts'),
      confirmLabel: s('confirm'),
    );
    if (!mounted || !confirmed) return;
    await JuiceDatabase.instance.clearKnownHosts();
    if (!mounted) return;
    await JuiceDialogs.message(
      context,
      title: s('clear_known_hosts'),
      message: s('known_hosts_cleared'),
    );
  }

  /// @brief `action:rate_us` —— 打开应用商店的评分页。
  ///
  /// 原版打开 `market://details?id=<app_package_name>`，
  /// 打不开时提示 `google_play_not_installed`。
  Future<void> _rateUs() async {
    final packageName = context.s('app_package_name');
    final failure = context.s('google_play_not_installed');
    await _launch('market://details?id=$packageName', failure);
  }

  /// @brief `action:website` —— 打开项目官网。
  ///
  /// 原版打开 `@string/app_website`，失败提示
  /// `there_are_no_browsers_available`。
  Future<void> _openWebsite() async {
    final website = context.s('app_website');
    final failure = context.s('there_are_no_browsers_available');
    await _launch(website, failure);
  }

  /// @brief 用外部程序打开链接，失败时提示。
  ///
  /// 原版这里是 Toast，这里用 SnackBar。
  Future<void> _launch(String url, String failureMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      opened = false;
    }
    if (opened) return;
    messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
  }

  // -------------------------------------------------------------- 对话框 --

  /// @brief 单选列表对话框，对应原版 `ListDBPreference` 弹的 `AlertDialog`。
  ///
  /// 外观走 [JuiceListDialog]：行高 48dp、起始内边距 20dp、单选标记槽 32dp、
  /// 文字 16sp，全部按原版 `select_dialog_singlechoice_material.xml` 实测。
  Future<int?> _pickEntry(
    BuildContext context, {
    required String title,
    required List<String> names,
    required int current,
  }) {
    final s = context.s;
    return showDialog<int>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => JuiceListDialog(
        title: title,
        entries: names,
        selectedIndex: current,
        cancelLabel: s('cancel'),
      ),
    );
  }

  /// @brief 数值对话框，对应原版 `NumberDBPreference`。
  Future<int?> _pickNumber(
    BuildContext context, {
    required String title,
    required String label,
    required String message,
    required int min,
    required int max,
    required int current,
  }) {
    return showDialog<int>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => _NumberPickerDialog(
        title: title,
        label: label,
        message: message,
        min: min,
        max: max,
        initial: current,
      ),
    );
  }
}

/// @brief 类别标题（`PreferenceCategory`）。
///
/// 框架的 `preference_category.xml` 用的是 `?android:listSeparatorTextViewStyle`
/// 并**没有**被 JuiceSSH 覆盖颜色；框架资源不在 APK 里，所以这里按该样式在
/// Material 主题下的取值复刻：全大写、14sp、加粗、次要文字色、最小高度
/// `?android:listPreferredItemHeightSmall`（= `@dimen/abc_list_item_height_small_material`
/// = 48dp）、左右各 `@dimen/abc_action_bar_content_inset_material`（16dp）内边距。
class _CategoryHeader extends StatelessWidget {
  /// @brief 创建类别标题 widget。
  const _CategoryHeader({required this.title});

  /// @brief 区段标题文案（已翻译）。
  final String title;

  /// @brief 区段标题内边距：`abc_action_bar_content_inset_material`。
  static final double _padding =
      _dimenValue('abc_action_bar_content_inset_material', 16);

  /// @brief 构建区段标题行。
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // 实测（原版 420dpi）：区段标题行 `[0,275][1080,368]`，高 93px；
    // 标题墨迹起于 330px，横向 44..167（"General" 123px）。
    // 93px = 42px(16dp 上内边距) + 50px(14sp × 1.362 行盒)，**没有下内边距** ——
    // 所以紧接着的第一行从 368px 开始，正好接上。
    // 用 `minHeight: 48dp` 会得到 126px，比原版高 33px 并把它下面所有行都推下去。
    return Padding(
      padding: EdgeInsets.only(
        top: _padding,
        left: _padding,
        right: _padding,
      ),
      child: Text(
        // **不要** `toUpperCase()`：原版渲染的是 "General" / "App Security" /
        // "Terminal"，字符串资源本身就是这个词形。
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          height: 1.362,
          fontWeight: FontWeight.bold,
          // **不是** `textFormHeading`。设置页的区段标题来自 `PreferenceCategory`
          // 的 `android:titleTextStyle`，取的是 `@color/accent_bold`：
          // 亮色 `#586E75`、暗色 `#D5BA31`（实测；`text_form_heading` 在暗色下是
          // `@android:color/secondary_text_dark` = `#BEBEBE`，那是**表单页**区段
          // 标题的颜色，两个别混）。
          color: palette.accentBold,
        ),
      ),
    );
  }
}

/// @brief 通用设置行。
class _SettingsRow extends StatelessWidget {
  /// @brief 创建通用设置行 widget。
  const _SettingsRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selectable = false,
  });

  /// @brief 标题（`@android:id/title`）。
  final String title;

  /// @brief 副标题（`@android:id/summary`），最多两行。
  final String? subtitle;

  /// @brief 右侧控件区（`@android:id/widget_frame`）内容。
  final Widget? trailing;

  /// @brief 整行单击回调。
  final VoidCallback? onTap;

  /// @brief 长按行为：原版无绑定，这里用于打开本复刻新增的补充页面。
  ///
  /// 当前只有「已知主机」列表页。
  final VoidCallback? onLongPress;

  /// @brief 整行是否套列表选中背景（只有开关行会）。
  ///
  /// 背景取自 `@android:drawable/list_selector_background`。
  final bool selectable;

  /// @brief `@dimen/activity_padding`（16dp）
  static final double _padding = _dimenValue('activity_padding', 16);

  /// @brief `@dimen/text_item_title`（16sp）
  static final double _titleSize = _dimenValue('text_item_title', 16);

  /// @brief `@dimen/text_item_subtitle`（12sp）
  static final double _subtitleSize = _dimenValue('text_item_subtitle', 12);

  /// @brief 行最小高度 `?android:listPreferredItemHeight`。
  ///
  /// AppCompat 把它定义成
  /// `@dimen/abc_list_item_height_material`（64dp）。
  static final double _minHeight =
      _dimenValue('abc_list_item_height_material', 64);

  /// @brief `@android:id/widget_frame` 的宽度：78.5dp。
  ///
  /// 实测原版开关行里是 206px
  /// （`[874,...][1080,...]`），即 78.5dp。
  static const double _widgetFrameWidth = 206 / 2.625;

  /// @brief 构建设置行（标题 + 副标题 + 右侧控件区）。
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final summary = subtitle;

    final content = Row(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(_padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  // 原版是 `ellipsize="marquee"`，Flutter 没有等价的内建跑马灯，
                  // 这里退化成省略号。
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _titleSize,
                    // 原生 `TextView` 的行盒 = 1.172em 行高 + 0.19em
                    // `includeFontPadding` = 1.362em。实测原版标题盒 57px
                    // （16sp × 2.625 × 1.362 = 57），摘要盒 43px
                    // （12sp × 2.625 × 1.362 = 43）。
                    // 不写 `height` 时 Flutter 用字体自带的行高（约 1.17em），
                    // 两行加起来少 14px，整页会越往下越偏。
                    height: 1.362,
                    color: palette.textItemTitle,
                  ),
                ),
                if (summary != null && summary.isNotEmpty)
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _subtitleSize,
                      height: 1.362,
                      color: palette.textItemSubtitle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null)
          // `@android:id/widget_frame`：原版实测 `[874,1013][1080,1197]`，
          // 即**撑满整行高度**、宽 206px（78.5dp = 46.5dp 控件 + 两侧各 16dp），
          // 控件在其中垂直居中。
          //
          // 不能写成 `Padding(EdgeInsets.all(16))`：`Switch` 自身高 48dp，
          // 加上下各 16dp 会把行高撑到 210px，而原版是 184px，
          // 于是「App Security」下面每一行都往下漂（实测累计 +80px）。
          SizedBox(
            width: _widgetFrameWidth,
            child: Center(child: trailing),
          ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _minHeight),
      child: switch (selectable) {
        // 开关行：`@android:drawable/list_selector_background`。
        true => InkWell(onTap: onTap, child: content),
        // 其它行：`@drawable/highlight` 是空的 `<selector />`，没有任何反馈。
        false => (onTap == null && onLongPress == null)
            ? content
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                onLongPress: onLongPress,
                child: content,
              ),
      },
    );
  }
}

/// @brief 数值选择对话框（原版 `NumberDBPreference` 的 `NumberPicker`）。
///
///
/// 原版在 API > 13 上用 `android.widget.NumberPicker`（min..max 的滚轮），
/// 上面还有一行 `custom:label` 文本、对话框正文是 `custom:message`。
/// Flutter 没有等价控件，这里用 [ListWheelScrollView] 复刻滚轮与中间放大效果。
class _NumberPickerDialog extends StatefulWidget {
  /// @brief 创建数值选择对话框 widget。
  const _NumberPickerDialog({
    required this.title,
    required this.label,
    required this.message,
    required this.min,
    required this.max,
    required this.initial,
  });

  /// @brief 对话框标题。
  final String title;
  /// @brief 滚轮左侧的标签文案。
  final String label;
  /// @brief 对话框正文文案。
  final String message;
  /// @brief 可选最小值（含）。
  final int min;
  /// @brief 可选最大值（含）。
  final int max;
  /// @brief 初始值，越界时夹回区间。
  final int initial;

  /// @brief 创建对话框的 State。
  @override
  State<_NumberPickerDialog> createState() => _NumberPickerDialogState();
}

/// @brief 数值选择对话框的状态：维护滚轮控制器与当前值。
class _NumberPickerDialogState extends State<_NumberPickerDialog> {
  /// @brief 滚轮控制器，初始定位到当前值。
  late final FixedExtentScrollController _controller;
  /// @brief 当前选中值（对话框返回值）。
  late int _value;

  /// @brief 初始化：把初始值夹进区间并定位滚轮。
  @override
  void initState() {
    super.initState();
    // `NumberDBPreference` 只允许 min..max，越界值夹回区间。
    var initial = widget.initial;
    if (initial < widget.min) initial = widget.min;
    if (initial > widget.max) initial = widget.max;
    _value = initial;
    _controller = FixedExtentScrollController(
      initialItem: _value - widget.min,
    );
  }

  /// @brief 释放滚轮控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// @brief 构建数值选择对话框。
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = context.s;
    final count = widget.max - widget.min + 1;
    // 正文与未选中数字的颜色：原版对话框里实测 (199,199,199)，正是白色以 70% 叠在
    // `#424242` 上的结果（0.7×255 + 0.3×66 ≈ 198），也就是 Android 对话框的
    // `textColorSecondary`。所以这里用 white70/black54，而不是某个扁平灰 ——
    // 亮色主题下对话框底色是 `#FAFAFA`，同一套语义给出 (117,117,117)。
    final bodyColor = palette.isDark ? Colors.white70 : Colors.black54;
    final strongColor = palette.isDark ? Colors.white : Colors.black87;
    return JuiceAlertDialog(
      title: widget.title,
      contentPadding: JuiceAlertDialog.messageContentPadding,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题到正文之间的间距：原版由 `?dialogPreferredPadding` 提供，实测标题
          // 视图底 848 → 正文视图顶 916 = 68px ≈ 26dp。但 `messageContentPadding`
          // 是**共用**常量，自定义视图的对话框（文档里实测过"没有这一条"的
          // Quick Connect）也在用它，所以这 20dp 只补在本对话框自己的内容里。
          const SizedBox(height: 20),
          Text(
            widget.message,
            // 16sp 是实测推出来的：原版正文每行墨迹高 41px，等于 0.94em（Roboto 的
            // 上伸+下伸）在 16sp 下的高度；行距 49px 又正好等于 16sp × 1.171em
            // （Roboto 的 hhea ascent+descent = 0.927+0.244），即 Android 默认行高。
            // 先前用 14sp/height 1.33 只是碰巧凑出同样的行距，墨迹却只有 36px。
            style: TextStyle(fontSize: 16, height: 1.171, color: bodyColor),
          ),
          const SizedBox(height: 10),
          // 原版是「标签 + NumberPicker」的 RelativeLayout：Picker 在对话框里**居中**
          // （实测 x 456..624，中心 540），标签右对齐贴在 Picker 左侧 15dp
          // （实测右边缘 417，滚轮左边缘 456，差 39px = 15dp），并与**选中项同高**
          // （标签墨迹 y 1321..1348，与中间数字同一带）。
          //
          // 用 Row 时两个 Expanded 必须等宽才能让 Picker 精确居中：间距放进左格
          // 的内边距里，而不是当成独立子项，否则 Picker 会右移 7.5dp。
          SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        widget.label,
                        style: TextStyle(fontSize: 16, color: bodyColor),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ListWheelScrollView.useDelegate(
                        controller: _controller,
                        // 原版 `NumberPicker` 实测：相邻数字墨迹中心相距 158px = 60dp；
                        // 外侧数字墨迹高 26/27px 对中间 28px，只小 4~7%，说明曲率很缓；
                        // 没有放大镜（中间项不比两侧大）。曲率取 1.78 时外侧缩放约 7%，
                        // 投影后的项距 R·sinθ ≈ 58.6dp ≈ 实测 60dp。
                        itemExtent: 60,
                        diameterRatio: 1.78,
                        overAndUnderCenterOpacity: 1,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) =>
                            setState(() => _value = widget.min + index),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: count,
                          builder: (context, index) {
                            final value = widget.min + index;
                            return Center(
                              child: Text(
                                '$value',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: value == _value
                                      ? strongColor
                                      : bodyColor,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // 分隔线：原版 `mSelectionDividerHeight` = 2dp，颜色实测
                      // (180..184,180..184,180..184) ≈ #B5B5B5。两条线的**内**间距实测
                      // 127px = 48dp（y 1265..1269 与 1396..1400），比项距 60dp 窄 ——
                      // 所以选中框是 48dp，线画在中心 ±24dp 处的内外两侧。
                      const Positioned(
                        top: 64,
                        left: 0,
                        right: 0,
                        height: 2,
                        child: ColoredBox(color: Color(0xFFB5B5B5)),
                      ),
                      const Positioned(
                        top: 114,
                        left: 0,
                        right: 0,
                        height: 2,
                        child: ColoredBox(color: Color(0xFFB5B5B5)),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ],
      ),
      actions: [
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(
          label: s('ok'),
          onPressed: () => Navigator.of(context).pop(_value),
        ),
      ],
    );
  }
}

/// @brief 带 ON/OFF 文字的开关（`SwitchCompat` 等价物）。
///
/// uiautomator 实测原版：`OFF` 节点与开关控件同 bounds（例如
/// `[916,1037][1038,1108]`，贴着列表右边缘，宽约 122px），而 Flutter 的 `Switch`
/// 不带文字。这里把标签叠在轨道上层（`IgnorePointer` 保证点击穿透）：
/// 关时留在右侧、开时移到左侧，与 Android 的观感一致。
class _JuiceSwitchText extends StatelessWidget {
  /// @brief 创建带 ON/OFF 文字的开关 widget。
  const _JuiceSwitchText({required this.value, required this.onChanged});

  /// @brief 开关当前状态。
  final bool value;
  /// @brief 状态变化回调；为 null 时开关禁用。
  final ValueChanged<bool>? onChanged;

  /// @brief 构建开关与叠加的 ON/OFF 文字。
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 32,
      child: Stack(
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: value ? Alignment.centerLeft : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Text(
                    value ? 'ON' : 'OFF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
