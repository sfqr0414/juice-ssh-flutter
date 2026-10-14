import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_form.dart';

/// @brief 新建 / 编辑身份 —— 对应原版 `activities.ManageIdentityActivity`。
///
/// 界面严格按 `res/layout/manage_identity.xml` 还原：
/// ```
/// RelativeLayout id=@id/main_content  fitsSystemWindows=true  w=match_parent h=wrap_content
/// └─ ScrollView id=@id/scroll_view  padding=@dimen/activity_padding (16dp)
///       scrollbars=vertical  clipToPadding=false  w=match_parent h=wrap_content
///    └─ TableLayout  orientation=horizontal  focusable=true  focusableInTouchMode=true
///       ├─ TableRow  → 分组标题 TextView  textColor=@color/text_form_heading
///       │     text=@string/identity  style="?android:listSeparatorTextViewStyle"
///       ├─ TableRow  marginTop=8dp
///       │  ├─ TextView   text=@string/nickname_colon   marginRight=5dp
///       │  └─ EditText id=@id/identityNickname_value  weight=1
///       │        hint=@string/optional
///       ├─ TableRow  marginTop=8dp
///       │  ├─ TextView   text=@string/username_colon
///       │  └─ EditText id=@id/identityUsername_value  weight=1
///       │        inputType=textVisiblePassword
///       ├─ TableRow  gravity=center_vertical  marginTop=8dp
///       │  ├─ TextView   text=@string/password_colon
///       │  ├─ TextView id=@id/identityPassword_status   visibility=gone
///       │  │     textSize=12sp  weight=1  text=@string/not_set
///       │  └─ Button   id=@id/identityPasswordButton    weight=1  h=36dp
///       │        text=@string/set_optional   background=@drawable/button
///       ├─ TableRow  gravity=center_vertical  marginTop=8dp
///       │  ├─ TextView   text=@string/private_key_colon
///       │  ├─ TextView id=@id/identityPrivateKey_status visibility=gone
///       │  │     weight=1  text=@string/not_set
///       │  └─ Button   id=@id/identityPrivateKey_button weight=1  h=36dp
///       │        text=@string/set_optional
///       ├─ TableRow id=@id/snippet_header_row  marginTop=8dp
///       │     → TextView  text=@string/snippet   (分组标题)
///       ├─ TableRow id=@id/snippet_row  marginTop=8dp
///       │     → TextView  text=@string/pro_users_can_public_key_snippet
///       └─ TableRow id=@id/snippet_button_row  marginTop=16dp
///             → Button id=@id/generate_snippet  h=42dp  text=@string/generate_snippet
/// ```
/// `@id/bottom_buttons`（Cancel / OK）在原版 `visibility="gone"`，
/// 保存按钮走 ActionBar，所以这里不实现。
///
/// ### 原版行为（读 `fragments/ManageIdentityFragment*.smali` 得到，逐条对照）
/// * **标题**：`AndroidManifest.xml` 里 `ManageIdentityActivity` 的 `android:label`
///   是 `@string/new_identity`，本页用同一个键。
/// * **保存菜单**：`res/menu/menu_manage_identity.xml` 只有一项
///   `menu_item_save` → `@string/save`，图标 `@drawable/ic_accept`，
///   `app:showAsAction="ifRoom"`。
/// * **昵称/用户名**：保存时都执行 `trim()`（`ManageIdentityFragment.p()`）。
/// * **用户名必填**：为空时 toast `@string/you_must_enter_a_username` 并中止保存。
/// * **密码 / 私钥按钮文案**：
///   `onCreateView` 里若 `password` 非空则按钮文案置为 `@string/update_or_clear`，
///   否则保持布局里的 `@string/set_optional`；私钥同理。
/// * **设置密码**：`ManageIdentityFragment$f.a(String, boolean)` —— 写入 `password`，
///   非空时 `passUpdated = System.currentTimeMillis()`、按钮变 `update_or_clear`、
///   状态文案 `@string/updated` + 相对时间；为空时 `passUpdated = 0`、
///   状态文案 `@string/not_set`、按钮回到 `set_optional`。
/// * **设置私钥**：`ManageIdentityFragment$g.e(String)` —— 完全对称，
///   写 `privatekey`、同时把 `privatekeyPassword` 清成 `""`，
///   非空时 `keyUpdated = System.currentTimeMillis()`；为空时 `keyUpdated = 0`。
/// * **状态文案**：`onResume` 里若 `passUpdated != 0` 则赋
///   `@string/updated` + `DateUtils.getRelativeTimeSpanString(passUpdated)`。
///   这里用本地时间格式化代替 `getRelativeTimeSpanString`（那是 Android 平台 API）。
///
/// ### 私钥三步提示流程（`res/layout/private_key_prompt.xml`）
/// 原版是一个三页 `TabHost`，三个页面分别是：
/// * `private_key_prompt_generatepage.xml` —— 生成：`@id/key_format_spinner`、
///   `@id/key_strength_spinner`、`@id/key_passphrase`，
///   文案 `@string/form_key_format` / `@string/form_key_strength` /
///   `@string/form_passphrase` / `@string/generating_key` / `@string/you_can_export_key`。
/// * `private_key_prompt_importpage.xml` —— 从文件导入：
///   `@id/radiogroup_import_type`（`@string/file_path` / `@string/smart_search`）、
///   `@id/ac_manual_import_path_text`（`@string/enter_path_relative_to_sdcard`）、
///   `@id/tv_loading_smart_search`（`@string/searching`）、
///   `@id/no_keys_found`（`@string/no_private_keys_found`）。
/// * `private_key_prompt_pastepage.xml` —— 粘贴：
///   单个 `EditText id=@id/key_paste_text`，`minLines=7`，
///   `inputType=textVisiblePassword|textMultiLine`。
///
/// **本次只实现「粘贴 PEM 私钥」这一条路**（[_promptPastePrivateKey]）；
/// 生成与文件导入两条路未实现（前者需要 BouncyCastle 级别的密钥生成，
/// 后者需要文件系统/存储权限，均超出本次范围）。
///
/// 另外原版在私钥需要口令时用 `@string/please_enter_your_private_key_passphrase`
/// 提示，本次也没有实现口令流程（`manage_identity.xml` 里并没有口令这一行，
/// 它属于运行期认证流程）。
class IdentityEditorScreen extends StatefulWidget {
  /// @brief 创建身份编辑页。
  const IdentityEditorScreen({super.key, this.identityId});

  /// @brief 为 null 时是「新建身份」，否则编辑该 id 的身份。
  final int? identityId;

  /// @brief 创建本页的 State。
  @override
  State<IdentityEditorScreen> createState() => _IdentityEditorScreenState();
}

/// @brief 身份编辑页的 State：持有输入控制器与当前编辑中的身份。
class _IdentityEditorScreenState extends State<IdentityEditorScreen> {
  /// @brief 数据库单例，本页读写身份的唯一入口。
  JuiceDatabase get _db => JuiceDatabase.instance;

  /// @brief 本页 `TableLayout` 第 0 列的宽度（实测 194px = 73.9dp）。
  ///
  /// 由这一列里最宽的标签（"Private Key:"）决定 —— `TableLayout` 的列宽规则是
  /// **整列等宽**，不是每个标签各算各的。连接编辑页的同一列是 207px
  /// （那边最宽的是 "Backspace:"），所以这个值不能全局共用一份。
  static const double _labelColumnWidth = 194 / 2.625;

  /// @brief 本页的一行「标签 + 控件」。
  JuiceFormRow _row({
    required String label,
    required Widget child,
    double? height,
  }) =>
      JuiceFormRow(
        label: label,
        labelWidth: _labelColumnWidth,
        height: height,
        child: child,
      );

  /// @brief `@id/identityNickname_value`（昵称）输入框的控制器。
  final TextEditingController _nickname = TextEditingController();
  /// @brief `@id/identityUsername_value`（用户名）输入框的控制器。
  final TextEditingController _username = TextEditingController();

  /// @brief 当前编辑中的身份。
  ///
  /// 新建时先造一个空壳，字段随输入即时写回。
  Identity _identity = const Identity(nickname: '');

  /// @brief 是否仍在载入数据；载入完成前保存按钮不可点。
  bool _loading = true;

  /// @brief 首次进入时载入待编辑的身份。
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// @brief 释放本页持有的输入框控制器。
  @override
  void dispose() {
    _nickname.dispose();
    _username.dispose();
    super.dispose();
  }

  /// @brief 按 id 读库回填；新建时直接结束载入。
  Future<void> _load() async {
    final id = widget.identityId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    final loaded = await _db.identity(id);
    if (!mounted) return;
    setState(() {
      _identity = loaded ?? const Identity(nickname: '');
      _nickname.text = _identity.nickname;
      _username.text = _identity.username ?? '';
      _loading = false;
    });
  }

  // ------------------------------------------------------------------ 保存 --

  /// @brief 保存 —— 对应 ActionBar 上的 `menu_item_save`。
  Future<void> _save() async {
    final s = context.s;
    // 先把 Navigator 取出来：`await` 之后再用 `context` 会触发
    // `use_build_context_synchronously`，`Navigator.of` 本身就是同步查找。
    final navigator = Navigator.of(context);
    final nickname = _nickname.text.trim();
    final username = _username.text.trim();

    // 原版 `ManageIdentityFragment.p()`：用户名为空则不保存。
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s('you_must_enter_a_username'))),
      );
      return;
    }

    final saved = _identity.copyWith(
      nickname: nickname,
      username: username,
      // `Identity.copyWith` 的置空开关：密码/私钥为空时要真正写回 null，
      // 否则 copyWith 会把旧值保留下来。
      clearPassword: !_identity.hasPassword,
      clearPrivateKey: !_identity.hasPrivateKey,
      clearPrivateKeyPassword: !_identity.hasPrivateKey,
    );
    await _db.saveIdentity(saved);
    if (!mounted) return;
    navigator.pop(saved.id);
  }

  // ------------------------------------------------------- 密码 / 私钥 --

  /// @brief 设置 / 清除密码 —— `@id/identityPasswordButton`。
  ///
  /// 对应原版 `ManageIdentityFragment$f`：清空即 `passUpdated = 0`。
  Future<void> _editPassword() async {
    final s = context.s;
    final entered = await JuiceDialogs.promptForSecret(
      context,
      prompt: s('manage_password'),
      echo: false,
    );
    if (!mounted || entered == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hasValue = entered.isNotEmpty;
    setState(() {
      _identity = _identity.copyWith(
        password: hasValue ? entered : null,
        clearPassword: !hasValue,
        // 原版：设置时间戳仅在值非空时写入，清空时归零。
        passUpdated: hasValue ? now : 0,
      );
    });
  }

  /// @brief 设置 / 清除私钥 —— `@id/identityPrivateKey_button`。
  ///
  /// 对应原版 `ManageIdentityFragment$g`：同时把 `privatekeyPassword` 清空，
  /// 清空私钥时 `keyUpdated = 0`。
  Future<void> _editPrivateKey() async {
    final entered = await _promptPastePrivateKey();
    if (!mounted || entered == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hasValue = entered.isNotEmpty;
    setState(() {
      _identity = _identity.copyWith(
        privateKey: hasValue ? entered : null,
        clearPrivateKey: !hasValue,
        clearPrivateKeyPassword: true,
        keyUpdated: hasValue ? now : 0,
      );
    });
  }

  /// @brief 私钥提示框 —— 只实现「粘贴」这条 `pastepage` 路。
  ///
  /// 原文案键：`@string/private_key`（标题）与 `@string/paste`（输入提示）。
  Future<String?> _promptPastePrivateKey() {
    final s = context.s;
    // 交给 JuiceDialogs：controller 由对话框自己持有并在自己的 dispose 里
    // 释放。这里曾经写成 `.whenComplete(controller.dispose)`，会在路由 pop
    // 那一刻就释放，而退出动画期间 TextField 仍会重建（第 12 轮那个
    // "used after being disposed" 的同类问题）。
    return JuiceDialogs.promptForPrivateKey(
      context,
      title: s('private_key'),
      hint: s('paste'),
      initialValue: _identity.privateKey,
    );
  }

  /// @brief 生成公钥代码片段按钮 —— `@id/generate_snippet`。
  ///
  /// 原版这一步会由私钥推导出公钥并生成一段 `authorized_keys` 片段，
  /// 属于 Pro 功能（`@string/pro_users_can_public_key_snippet` 说明就是这句话）。
  /// 本项目尚未实现密钥推导，所以这里只给出提示，不写数据库。
  Future<void> _generateSnippet() async {
    final s = context.s;
    await JuiceDialogs.message(
      context,
      title: s('generate_snippet'),
      message: s('pro_users_can_public_key_snippet'),
    );
  }

  // ------------------------------------------------------------------ 视图 --

  /// @brief 构建页面骨架：AppBar（保存按钮）+ 表单 / 载入指示。
  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        // 与连接编辑页同理：原版标题墨迹在 `y=180..227`，
        // Flutter 居中后是 `176..223`，差 4px = 1.5dp。
        title: Transform.translate(
          offset: const Offset(0, 4 / 2.625),
          // 原版在这一页有两个标题键，和连接编辑页的 `new_connection` /
          // `update_connection` 一一对应：新建用 `new_identity`，编辑既有身份用
          // `update_identity`。此前一律用前者，导致点开一个已有身份时标题也写着
          // "New Identity"（设备实测确认过，原版两个键都在 strings.xml 里）。
          child: Text(s(widget.identityId == null ? 'new_identity' : 'update_identity')),
        ),
        actions: [
          // `menu_manage_identity.xml`：`menu_item_save` → `@string/save`，
          // 图标 `@drawable/ic_accept`（白色对勾）→ Material 的 `Icons.check`。
          // 尺寸按原版墨迹（60×44px）反推。
          IconButton(
            iconSize: 31.5,
            icon: const Icon(Icons.check),
            tooltip: s('save'),
            onPressed: _loading ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(context),
    );
  }

  /// @brief 构建表单主体，逐行对应原版 `manage_identity.xml`。
  Widget _buildForm(BuildContext context) {
    final s = context.s;

    // `@id/scroll_view`：`padding=@dimen/activity_padding`（16dp）、
    // `clipToPadding=false`。
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JuiceFormSectionHeader(text: s('identity')),
          const SizedBox(height: 8),
          _row(
            height: juiceEditRowHeight,
            label: s('nickname_colon'),
            child: JuiceFormTextField(
              controller: _nickname,
              hintText: s('optional'),
            ),
          ),
          const SizedBox(height: 8),
          _row(
            height: juiceEditRowHeight,
            label: s('username_colon'),
            child: JuiceFormTextField(
              controller: _username,
              // `inputType=textVisiblePassword`：不做自动联想/纠错。
              autocorrect: false,
            ),
          ),
          const SizedBox(height: 8),
          _SecretRow(
            labelWidth: _labelColumnWidth,
            label: s('password_colon'),
            isSet: _identity.hasPassword,
            status: _statusText(context, _identity.passUpdated),
            onPressed: _editPassword,
          ),
          const SizedBox(height: 8),
          _SecretRow(
            labelWidth: _labelColumnWidth,
            label: s('private_key_colon'),
            isSet: _identity.hasPrivateKey,
            status: _statusText(context, _identity.keyUpdated),
            // 这一格原版用的是 `?android:textAppearanceSmall`（14sp），
            // 口令那一格才写死 `textSize="12.0sp"`。
            statusTextSize: 14,
            onPressed: _editPrivateKey,
          ),
          const SizedBox(height: 8),
          // `@id/snippet_header_row`。
          JuiceFormSectionHeader(text: s('snippet')),
          const SizedBox(height: 8),
          // `@id/snippet_row` 的说明文字：`textAppearanceSmall` = 14sp。
          //
          // 原版这一行 `[42,1013][1038,1150]`，高 **137px**。
          //
          // Android 多行 TextView 的高度 = `N × 1.171em + includeFontPadding`，
          // 而 `includeFontPadding` 只在**首尾各加一次**、不是每行都加
          // （≈0.19em，首尾分配不均）。
          //
          // Flutter 这边还有个额外麻烦：`TextStyle.height` 算出来的行高会被
          // **取整到整数逻辑像素**（1.171 × 14sp = 16.39dp → 16dp），3 行就比
          // Android 少 ~3px。所以上下内边距不能照抄 0.19em，得按实测配平：
          // 上 6.5px 让首行墨迹落在 1025、下 5.5px 让这一行仍收在 1150。
          // 用内边距而不是写死高度，是为了文本换行数变了也能自然撑开。
          Padding(
            padding: const EdgeInsets.only(
              top: 6.5 / 2.625,
              bottom: 5.5 / 2.625,
            ),
            child: Text(
              s('pro_users_can_public_key_snippet'),
              style: TextStyle(
                fontSize: 14,
                height: 1.171,
                color: context.palette.textForm,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // `@id/snippet_button_row` / `@id/generate_snippet`：高 42dp。
          JuiceFormButton(
            height: juiceWideButtonHeight,
            label: s('generate_snippet'),
            onPressed: _generateSnippet,
          ),
        ],
      ),
    );
  }

  /// @brief 口令/私钥的状态文字。
  ///
  /// 原版：`passUpdated`/`keyUpdated` 非 0 时显示
  /// `@string/updated` + 相对时间（`DateUtils.getRelativeTimeSpanString`），
  /// 否则显示 `@string/not_set`。这里用本地时间代替平台相对时间。
  String? _statusText(BuildContext context, int? timestamp) {
    if (timestamp == null || timestamp == 0) return null;
    final s = context.s;
    final updated = DateTime.fromMillisecondsSinceEpoch(timestamp);
    /// @brief 把数字补零成两位，用于拼 `yyyy-MM-dd HH:mm` 时间戳。
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${updated.year}-${two(updated.month)}-${two(updated.day)} '
        '${two(updated.hour)}:${two(updated.minute)}';
    return '${s('updated')} $stamp';
  }
}

/// @brief 「密码 / 私钥」一行。
///
/// 对应 `manage_identity.xml` 的
/// `TextView status` + `Button`（两者都是 `layout_weight=1`，各占一半宽度）。
///
/// * 未设置时 status 为空（原版 `visibility="gone"`），按钮文案 `@string/set_optional`；
/// * 已设置时 status 显示 `@string/updated` + 时间，按钮文案 `@string/update_or_clear`。
class _SecretRow extends StatelessWidget {
  /// @brief 创建「密码 / 私钥」一行。
  const _SecretRow({
    required this.labelWidth,
    required this.label,
    required this.isSet,
    required this.status,
    required this.onPressed,
    this.statusTextSize = 12,
  });

  /// @brief 标签列宽度（本页实测 194px）。
  final double labelWidth;
  /// @brief 该行的标签文案（如 `@string/password_colon`）。
  final String label;
  /// @brief 是否已设置；false 时状态格完全不占位。
  final bool isSet;
  /// @brief 状态文案（未设置时为 null）。
  final String? status;
  /// @brief 点击设置 / 清除按钮的回调。
  final VoidCallback onPressed;

  /// @brief 状态文字字号：口令那一格原版写死 `textSize="12.0sp"`，
  /// 私钥那一格用的是 `?android:textAppearanceSmall`（14sp）。
  final double statusTextSize;

  /// @brief 构建「状态文字 + 设置/清除按钮」一行。
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;

    // 原版状态格是 `android:visibility="gone"`：未设置时**完全不占位**，
    // 按钮（`layout_weight=1`）于是独吞剩下的宽度（实测按钮 260..1038
    // = 778px，而输入框那一列只有 249..1038 = 789px，差的正是 4dp 左边距）。
    // 之前这里无论有没有状态都放一个 `Expanded`，按钮被压成一半宽。
    return JuiceFormRow(
      label: label,
      labelWidth: labelWidth,
      height: juiceButtonHeight,
      child: Row(
        children: [
          if (isSet)
            Expanded(
              child: Text(
                status ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: statusTextSize,
                  height: 1.362,
                  color: palette.textForm,
                ),
              ),
            ),
          // `android:layout_marginLeft="4.0dp"`
          const SizedBox(width: juiceButtonLeftMargin),
          Expanded(
            child: JuiceFormButton(
              label: isSet ? s('update_or_clear') : s('set_optional'),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}
