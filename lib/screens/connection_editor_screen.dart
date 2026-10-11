import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../app/settings_controller.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_alert_dialog.dart';
import '../widgets/juice_form.dart';
import 'identity_editor_screen.dart';

/// 新建 / 编辑连接 —— 对应原版
/// `com.sonelli.juicessh.activities.ManageConnectionActivity`。
///
/// ### 布局依据 —— `res/layout/manage_connection.xml`（字段与顺序逐条对照）
/// ```
/// RelativeLayout  orientation=vertical  fitsSystemWindows=true  w/h=match_parent
/// └─ ScrollView  padding=@dimen/activity_padding (16dp)  scrollbars=vertical
///       clipToPadding=false  w/h=match_parent
///    └─ LinearLayout  orientation=vertical  focusable=true  focusableInTouchMode=true
///          w=match_parent  h=wrap_content
///       ├─ TableLayout  id=@id/connectionTableForm  w=match_parent  h=wrap_content
///       │  ├─ TextView  text=@string/basic_settings  textColor=@color/text_form_heading
///       │  │     style="?android:listSeparatorTextViewStyle"      ← 分组标题
///       │  ├─ TableRow  id=@id/nicknameRow   marginTop=8dp
///       │  │  ├─ TextView  text=@string/form_nickname   marginRight=5dp
///       │  │  └─ EditText  id=@id/nickname_value  weight=1  hint=@string/form_optional
///       │  ├─ TableRow  id=@id/typeRow       marginTop=8dp
///       │  │  ├─ TextView  text=@string/type_colon
///       │  │  └─ Spinner   id=@id/type_spinner  h=36dp  prompt=@string/pick_one
///       │  ├─ TableRow  id=@id/addressRow    marginTop=8dp
///       │  │  ├─ TextView  text=@string/form_address
///       │  │  └─ EditText  id=@id/address_value  weight=1  inputType=textVisiblePassword
///       │  ├─ TableRow  id=@id/identityRow   marginTop=8dp
///       │  │  ├─ TextView  text=@string/form_identity
///       │  │  └─ Spinner   id=@id/idSpinner  h=36dp  prompt=@string/choose_an_identity
///       │  ├─ TextView  text=@string/advanced_settings  marginTop=8dp
///       │  │     style="?android:listSeparatorTextViewStyle"      ← 分组标题
///       │  ├─ TableRow  id=@id/portRow       marginTop=8dp
///       │  │  ├─ TextView  text=@string/form_port
///       │  │  └─ EditText  id=@id/port_value  ems=5  maxLength=5  inputType=number
///       │  │        hint=@string/form_22
///       │  ├─ TableRow  id=@id/viaRow        marginTop=8dp
///       │  │  ├─ TextView  text=@string/form_connect_via
///       │  │  └─ Spinner   id=@id/via_spinner  h=36dp  prompt=@string/form_optional
///       │  ├─ TableRow  id=@id/runOnConnectRow  marginTop=8dp
///       │  │  ├─ TextView  text=@string/run_snippet
///       │  │  └─ Spinner   id=@id/snippetSpinner  h=36dp  prompt=@string/choose_a_snippet
///       │  ├─ TableRow  id=@id/backspaceModeRow marginTop=8dp
///       │  │  ├─ TextView  text=@string/backspace_mode
///       │  │  └─ Spinner   id=@id/backspaceModeSpinner  h=36dp（无 prompt）
///       │  └─ TableRow  id=@id/mosh_command_row  visibility=gone  marginTop=8dp
///       │     ├─ TextView  text=@string/command
///       │     └─ EditText  id=@id/mosh_command_value  weight=1
///       │           inputType=textVisiblePassword
///       ├─ TextView  text=@string/groups  marginTop=8dp
///       │     style="?android:listSeparatorTextViewStyle"          ← 分组标题
///       └─ LinearLayout  id=@id/group_selector_holder  w=match_parent
///             h=wrap_content                ← 子视图在 Java 里添加
/// ```
///
/// ### 保存菜单
/// `res/menu/menu_manage_connection.xml` 只有一项：
/// `menu_item_save` → `@string/save`，图标 `@drawable/ic_accept`，
/// `app:showAsAction="ifRoom"`。这里的 ActionBar 只放一个白色对勾
/// （返回箭头由 AppBar 主题提供 `ic_arrow_back_white_24dp`）。
///
/// ### 原版交互（读 `activities/ManageConnectionActivity.smali` 得到）
/// * **进入**：`onCreate` 先按 `connection_id` 取连接；取不到（或没有这个
///   extra）就当成新建。编辑时逐个回填 `nickname` / `address` / `port` /
///   `moshCommand`，再把标题设成 `@string/update_connection`
///   （**没有**用连接昵称）。
/// * **类型下拉**（`jh0`）顺序固定为 `ssh(0) / telnet(1) / mosh(2) /
///   local(3)`，条目文案分别是 `@string/ssh`、`@string/telnet`、
///   `@string/mosh`、`@string/local_device`；spinner 的 `getSelectedItemId()`
///   直接就是落库的 `type`。选中 mosh 时显示 `@id/mosh_command_row`。
/// * **连接方式下拉**（`ih0`，`ConnectionSpinnerAdapter`）：候选是**全部连接**
///   （按名字排序，编辑时把自己剔除），第 0 项固定为占位
///   （`@string/optional`；新版由 `new Connection(null, ...)` 触发的是
///   `@string/pick_one`），选中占位即 `via = null`。
/// * **Snippet 下拉**（`uh0`）：第 0 项占位 `@string/optional`，其余按名字排序。
/// * **退格键下拉**（`fh0`）：索引 0 → `@string/backspace_mode_default`，
///   索引 1 → `@string/backspace_mode_legacy`，
///   `getSelectedItemPosition()` 直接落库成 `backspaceMode`。
/// * **身份下拉**（`vh0`，`SpinnerArrayAdapter`）：候选是全部身份（按
///   `Comparable` 排序，即昵称），末尾多一项 `@string/_new + "..."`，
///   选中它会跳到 `ManageIdentityActivity` 新建身份。
/// * **分组选择器**（`xj0`，`MultiSelector`）：`res/layout/multi_selector.xml`
///   是一个「标题 + 若干『spinner + X 按钮』行 + 底部按钮」的容器；
///   容器宽度是 `match_parent`，底部按钮文案由调用方设置——
///   本页用 `@string/add_to_group`，标题 `@string/add_to_group` 在没有任何
///   条目时显示 `@string/select_one + "..."`。点按钮弹出的选择框里
///   是所有分组（按名字排序），选中一项就多一行。
/// * **地址校验**：`trim()` 后为空 → Toast `@string/you_must_enter_an_address`；
///   `Connection.y()` 判空/非法时 → Toast `@string/invalid_address`。
/// * **端口**：`Integer.parseInt` 失败就退回 **22**（`0x16`），不做范围校验。
/// * **身份为空**（`vh0.b() == 0`）→ 抛 `NullPointerException` 被捕获后
///   Toast `@string/you_must_select_an_identity` 并中止保存。
/// * **mosh 命令**：等于 `Config` 里 `mosh:mosh-server` 默认值时写 `null`，
///   否则写用户输入。
/// * **保存写表**：先 `DAO.g(connection)`（insert/update），
///   再 `Connection.z(identity)` 写身份关联，最后同步
///   `connectiongroupmembership`（新增缺的、删除多余的）。
///   身份/分组**不是**独立表关联的写入，而是在保存时统一同步。
///
/// ### 与原版的三处有意偏差（其余逐项照搬）
/// 1. **身份多选 + 排序**：原版 3.2.2 的 `@id/idSpinner` 是单选，
///    但 `connectionidentity` 表本身支持一条连接挂多个身份、按
///    `position` 决定认证尝试顺序，`Connection.identity(Connection)`
///    返回的就是这串有序身份。本页因此把该行做成「可多选 + 可上下调序」，
///    选择框标题用 `@string/choose_an_identity`，行内仍保留原版的
///    `@string/_new...` 新建入口。**这是应任务要求做的功能扩展**。
/// 2. **分组选择器用对话框**：原版是行内「spinner 行 + X」，
///    这里改成「加号按钮 + 已选分组行（带 X）」，语义相同（都是多选）。
/// 3. **端口校验**：原版没有范围校验；按任务要求补上 1–65535 校验，
///    提示文案因原版无对应键而借用 `@string/invalid_address`（见 [_invalidPortKey]）。
class ConnectionEditorScreen extends StatefulWidget {
  const ConnectionEditorScreen({super.key, this.connection});

  /// 为 null 表示「新建连接」，否则编辑这条连接。
  final Connection? connection;

  @override
  State<ConnectionEditorScreen> createState() => _ConnectionEditorScreenState();
}

class _ConnectionEditorScreenState extends State<ConnectionEditorScreen> {
  JuiceDatabase get _db => JuiceDatabase.instance;

  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '22');
  final TextEditingController _moshCommand = TextEditingController();

  ConnectionType _type = ConnectionType.ssh;
  BackspaceMode _backspaceMode = BackspaceMode.del;

  /// `@id/via_spinner` 的当前值；null 表示占位项（`via` 为空）。
  int? _viaId;

  /// `@id/snippetSpinner` 的当前值；null 表示占位项（`snippet` 为空）。
  int? _snippetId;

  /// `@id/idSpinner`：身份按**认证尝试顺序**排列，下标即 `position`。
  ///
  /// 原版是单选（长度 0 或 1），这里扩展成多选；保存时整串写进
  /// `connectionidentity.position`。
  final List<int> _identityIds = <int>[];

  /// `@id/group_selector_holder`：已选分组（多选）。
  final List<int> _groupIds = <int>[];

  List<Connection> _connections = const [];
  List<Identity> _identities = const [];
  List<Snippet> _snippets = const [];
  List<ConnectionGroup> _groups = const [];

  /// `Config.d("mosh:mosh-server")` 的默认值。
  ///
  /// 原版在 `onCreate` 里把它填进 `@id/mosh_command_value`，保存时若
  /// 文本仍等于默认值就把 `moshCommand` 写成 `null`（即"用默认"）。
  late final String _defaultMoshCommand = _loadDefaultMoshCommand();

  bool _loading = true;

  String _loadDefaultMoshCommand() {
    try {
      return SettingsController.instance.moshServerCommand;
    } on StateError {
      // 设置控制器未初始化时（例如单页调试）退回到原版 `Config` 里的常量。
      return 'mosh-server new -s -l LANG=en_US.UTF-8';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _address.dispose();
    _port.dispose();
    _moshCommand.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 载入 --

  Future<void> _load() async {
    final editing = widget.connection;

    final connections = await _db.connections();
    final identities = await _db.identities();
    final snippets = await _db.snippets();
    final groups = await _db.groups();

    // 编辑模式：按 id 把关联的身份与分组读出来（身份保持 position 顺序）。
    List<int> identityIds = const <int>[];
    List<int> groupIds = const <int>[];
    if (editing != null && editing.id != 0) {
      identityIds = await _db.connectionIdentityIds(editing.id);
      groupIds = await _db.groupIdsForConnection(editing.id);
    }

    if (!mounted) return;
    setState(() {
      // 「连接方式」候选是全部连接，编辑时把自己剔除（原版 `ih0` 的构造参数）。
      _connections = connections
          .where((item) => item.id != (editing?.id ?? 0))
          .toList();
      _identities = identities;
      _snippets = snippets;
      _groups = groups;

      if (editing != null) {
        _nickname.text = editing.nickname;
        _address.text = editing.address;
        _port.text = '${editing.port}';
        _type = editing.type;
        _backspaceMode = editing.backspaceMode;
        _viaId = editing.viaId;
        _snippetId = editing.snippetId;
        // 原版只在 moshCommand 非空时才覆盖默认值。
        final command = editing.moshCommand;
        _moshCommand.text =
            (command != null && command.isNotEmpty) ? command : _defaultMoshCommand;
      } else {
        _moshCommand.text = _defaultMoshCommand;
      }

      _identityIds
        ..clear()
        ..addAll(identityIds);
      _groupIds
        ..clear()
        ..addAll(groupIds);
      // `connection.group` 是单值列；关联表为空时回退到它，
      // 保证编辑一条只有单分组列的旧数据时不丢分组。
      final legacyGroupId = editing?.groupId;
      if (_groupIds.isEmpty && legacyGroupId != null) {
        _groupIds.add(legacyGroupId);
      }
      _loading = false;
    });
  }

  // ------------------------------------------------------------- 展示辅助 --

  String get _title {
    final connection = widget.connection;
    if (connection == null) return context.s('new_connection');
    // 原版标题固定 `@string/update_connection`（不是连接昵称）。
    return context.s('update_connection');
  }

  Identity? _identityById(int id) {
    for (final identity in _identities) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  ConnectionGroup? _groupById(int id) {
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// 连接类型下拉的条目文案。
  ///
  /// 取自 `ConnectionTypeSpinnerAdapter`（`jh0`）：`@string/ssh` /
  /// `@string/telnet` / `@string/mosh` / `@string/local_device`。
  /// 注意 `ConnectionType.labelKey`（`connection_type_*`）在本项目的
  /// `strings_en.json` 里并不存在，所以这里直接用原版的那四个键。
  String _typeLabel(ConnectionType type) => switch (type) {
        ConnectionType.ssh => context.s('ssh'),
        ConnectionType.telnet => context.s('telnet'),
        ConnectionType.mosh => context.s('mosh'),
        ConnectionType.local => context.s('local_device'),
      };

  /// 退格键下拉的条目文案。
  ///
  /// 取自 `BackspaceModeSpinnerAdapter`（`fh0`）：
  /// 索引 0 → `@string/backspace_mode_default`，
  /// 索引 1 → `@string/backspace_mode_legacy`。
  String _backspaceLabel(BackspaceMode mode) => switch (mode) {
        BackspaceMode.del => context.s('backspace_mode_default'),
        BackspaceMode.backspace => context.s('backspace_mode_legacy'),
      };

  /// `@id/port_value` 校验失败时的提示键。
  ///
  /// **推断说明**：原版 3.2.2 对端口不做校验，`strings.xml` 里也没有
  /// "端口非法"这一类键（`you_must_enter_a_local_port` /
  /// `you_must_enter_a_remote_port` 属于端口转发页，语义不符）。
  /// 这里退而借用 `@string/invalid_address`（"Invalid address"），
  /// 它是原版真实的校验类提示，含义最接近。
  static const String _invalidPortKey = 'invalid_address';

  /// 弹一条 Toast 等价提示（原版用 `Toast.makeText(...).show()`）。
  ///
  /// SnackBar 文案与 `SnackBar` 的默认行为等价，且本项目其它编辑页
  /// （`identity_editor_screen.dart`）也是这么做的。
  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ 保存 --

  /// 保存 —— 对应 ActionBar 上的 `menu_item_save`。
  ///
  /// 顺序照抄原版 `ManageConnectionActivity.v()`：
  /// 地址校验 → 身份校验 → 写 `connection` → 写 `connectionidentity`
  /// → 同步 `connectiongroupmembership`。
  Future<void> _save() async {
    final s = context.s;
    // `await` 之后不能再碰 `context`（`use_build_context_synchronously`），
    // 所以先把 Navigator 与文案取出来。
    final navigator = Navigator.of(context);

    final isLocal = _type == ConnectionType.local;
    final nickname = _nickname.text.trim();
    final address = _address.text.trim();
    // 原版：`Integer.parseInt` 失败退回 22。
    final parsedPort = int.tryParse(_port.text.trim()) ?? 22;

    // 1. 地址不能为空（`@string/you_must_enter_an_address`）。
    if (address.isEmpty) {
      _toast(s('you_must_enter_an_address'));
      return;
    }
    // 2. 端口必须是 1–65535 的整数（本项目的补充校验）。
    if (!isLocal && (parsedPort < 1 || parsedPort > 65535)) {
      _toast(s(_invalidPortKey));
      return;
    }
    // 3. identity 行只对 ssh/telnet/mosh 有效；这些类型必须至少有一个身份。
    if (!isLocal && _identityIds.isEmpty) {
      _toast(s('you_must_select_an_identity'));
      return;
    }

    // mosh 命令：等于默认值就写 null（原版行为）。
    String? moshCommand;
    if (_type == ConnectionType.mosh) {
      final text = _moshCommand.text;
      moshCommand = text == _defaultMoshCommand ? null : text;
    }

    // local 类型不写身份/端口/跳板机/片段等字段。
    final identityIds = isLocal ? const <int>[] : List<int>.of(_identityIds);

    final draft = Connection(
      id: widget.connection?.id ?? 0,
      nickname: nickname,
      address: address,
      port: isLocal ? 0 : parsedPort,
      type: _type,
      // `group` 列只能存一个；取多选列表的第一个（分组本身写关联表）。
      groupId: _groupIds.isEmpty ? null : _groupIds.first,
      viaId: isLocal ? null : _viaId,
      snippetId: isLocal ? null : _snippetId,
      moshCommand: moshCommand,
      backspaceMode: _backspaceMode,
    );

    final id = await _db.saveConnection(draft);
    // 新建时 `saveConnection` 返回自增 id；关联表必须用这个 id。
    final connectionId = id == 0 ? draft.id : id;
    await _db.setConnectionIdentities(connectionId, identityIds);
    await _db.setConnectionGroups(connectionId, List<int>.of(_groupIds));

    if (!mounted) return;
    // 外层连接列表据此刷新。
    navigator.pop(true);
  }

  // ------------------------------------------------------- 身份：多选 + 调序 --

  /// 打开身份多选选择框（标题 `@string/choose_an_identity`）。
  ///
  /// 勾选顺序即认证尝试顺序，返回的列表已按该顺序排好。
  ///
  /// 选择框里的 `@string/_new...` 入口返回 `true`（而不是列表），
  /// 这里据此跳到新建身份页 —— 对应原版
  /// `startActivityForResult(ManageIdentityActivity, 2)`。
  Future<void> _pickIdentities() async {
    if (_identities.isEmpty) {
      // 一个身份都没有时，直接走新建流程。
      await _createIdentity();
      return;
    }
    // 注意不能用 `await showDialog<T>()`：这个框有两个返回类型
    // （`List<int>` 与 `bool`），只能按 `Object?` 接收再判断。
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _IdentityPickerDialog(
        identities: _identities,
        selected: _identityIds,
      ),
    );
    if (!mounted || result == null) return;
    if (result is bool) {
      await _createIdentity();
      return;
    }
    // 剩下的情况只可能是勾选结果（Cancel / 点外部返回 null）。
    if (result is! List<int>) return;
    setState(() {
      _identityIds
        ..clear()
        ..addAll(result);
    });
  }

  /// 选择框里的 `@string/_new...` 入口：跳到新建身份页。
  ///
  /// 原版走 `startActivityForResult(ManageIdentityActivity, 2)`，
  /// 回来后刷新下拉；这里 push 之后重新拉一次身份列表。
  Future<void> _createIdentity() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const IdentityEditorScreen()),
    );
    if (!mounted) return;
    final identities = await _db.identities();
    if (!mounted) return;
    setState(() => _identities = identities);
  }

  /// 交换两个身份的顺序（认证尝试顺序）。
  void _moveIdentity(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _identityIds.length) return;
    setState(() {
      final moved = _identityIds.removeAt(index);
      _identityIds.insert(target, moved);
    });
  }

  /// 把某个身份从列表里去掉。
  void _removeIdentity(int index) {
    setState(() => _identityIds.removeAt(index));
  }

  // --------------------------------------------------------- 分组：多选 --

  /// 打开分组多选选择框。
  ///
  /// 原版 `MultiSelector` 点 `@string/add_to_group` 时直接弹列表，
  /// 列表为空就是一个空选择框（只留 Cancel / OK），这里保持一致，
  /// 不做特殊提示。
  Future<void> _pickGroups() async {
    final selected = await showDialog<List<int>>(
      context: context,
      builder: (_) => _GroupPickerDialog(groups: _groups, selected: _groupIds),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _groupIds
        ..clear()
        ..addAll(selected);
    });
  }

  // ------------------------------------------------------------------ 视图 --

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        // 标题整体下移 4px = 1.5dp。
        //
        // 原版标题墨迹在 `y=180..227`，Flutter 的 `AppBar` 居中后是 `176..223`
        // —— 字高完全一致（都是 47px），只是基线位置差 4px。
        // `NavigationToolbar` 会把 title 垂直居中，所以用 `Transform` 平移
        // （而不是 Padding：Padding 会撑高盒子，居中后只挪一半）。
        title: Transform.translate(
          offset: const Offset(0, 4 / 2.625),
          child: Text(_title),
        ),
        actions: [
          // `menu_manage_connection.xml`：`menu_item_save` → `@string/save`，
          // 图标 `@drawable/ic_accept`（白色对勾）→ Material 的 `Icons.check`。
          //
          // 注意 uiautomator 层级里这一项是 `TextView menu_item_save
          // text="Save"`，看着像「文字按钮」，但把那一块像素打成 ASCII 图
          // 就清楚了：屏幕上画的是一枚对勾图标，`text` 只是无障碍文案。
          //
          // 尺寸 31.5dp 是按墨迹反推的：原版对勾墨迹 60×44px，
          // `Icons.check` 在 24dp 时是 45×34px，等比放大 60/45 ≈ 1.33 倍。
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

  Widget _buildForm(BuildContext context) {
    final s = context.s;
    final isLocal = _type == ConnectionType.local;

    // `ScrollView padding=@dimen/activity_padding`（16dp）、`clipToPadding=false`。
    return SingleChildScrollView(
      padding: const EdgeInsets.all(_activityPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------------------------------------------- Basic Settings --
          JuiceFormSectionHeader(text: s('basic_settings')),
          const SizedBox(height: _rowSpacing),
          _row(
            height: juiceEditRowHeight,
            label: s('form_nickname'),
            child: JuiceFormTextField(
              controller: _nickname,
              hintText: s('form_optional'),
            ),
          ),
          const SizedBox(height: _rowSpacing),
          _row(
            height: juiceSpinnerRowHeight,
            label: s('type_colon'),
            child: _Dropdown<int>(
              value: _type.index,
              hint: s('pick_one'),
              items: [
                for (final type in ConnectionType.values)
                  DropdownMenuItem<int>(
                    value: type.index,
                    child: Text(_typeLabel(type), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _onTypeChanged,
            ),
          ),
          const SizedBox(height: _rowSpacing),
          _row(
            height: juiceEditRowHeight,
            label: s('form_address'),
            child: JuiceFormTextField(
              controller: _address,
              // `inputType=textVisiblePassword`：不做自动联想/纠错。
              autocorrect: false,
            ),
          ),
          const SizedBox(height: _rowSpacing),
          // `@id/identityRow`：原版是单选 spinner，这里按任务要求做成多选。
          if (!isLocal) ...[
            _row(
              height: juiceSpinnerRowHeight,
              label: s('form_identity'),
              child: _SelectorValue(
                text: _identitySummary(context),
                onTap: _pickIdentities,
              ),
            ),
            // 下面是**多选扩展**才有的内容，单身份/未选身份时不渲染 ——
            // 原版只有上面那一行，这样默认状态下与本页逐像素一致。
            //
            // 原来这里还有一个常驻的「Choose an identity」按钮和一段说明文案，
            // 会让表单凭空多出两行（实测多出 2 行、整页下移）。
            // 该按钮本身也是多余的：上面的行点了就打开同一个选择框。
            if (_identityIds.length > 1) ...[
              for (var index = 0; index < _identityIds.length; index++)
                _SelectedIdentityRow(
                  name: _identityName(context, _identityIds[index]),
                  // 顺序提示：`%d` 是认证尝试次序（从 1 开始）。
                  position: index + 1,
                  canMoveUp: index > 0,
                  canMoveDown: index < _identityIds.length - 1,
                  onMoveUp: () => _moveIdentity(index, -1),
                  onMoveDown: () => _moveIdentity(index, 1),
                  onRemove: () => _removeIdentity(index),
                ),
              // 原版身份页的说明文案（`@string/juicessh_will_automatically_push_keys`）。
              Text(
                s('juicessh_will_automatically_push_keys'),
                style: TextStyle(fontSize: 12, color: context.palette.textSubheading),
              ),
            ],
          ],

          // ------------------------------------------------- Advanced Settings --
          const SizedBox(height: _rowSpacing),
          JuiceFormSectionHeader(text: s('advanced_settings')),
          if (!isLocal) ...[
            const SizedBox(height: _rowSpacing),
            _row(
              height: juiceEditRowHeight,
              label: s('form_port'),
              child: SizedBox(
                width: _portFieldWidth,
                child: JuiceFormTextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  // `inputType="number"` + `maxLength="5"` + `ems="5"`。
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  hintText: s('form_22'),
                ),
              ),
            ),
            const SizedBox(height: _rowSpacing),
            _row(
              height: juiceSpinnerRowHeight,
              label: s('form_connect_via'),
              child: _Dropdown<int?>(
                value: _viaId,
                hint: s('form_optional'),
                items: [
                  // 第 0 项占位，选中即 `via = null`（原版 `ih0` 的第 0 项）。
                  DropdownMenuItem<int?>(value: null, child: Text(s('form_optional'))),
                  for (final connection in _connections)
                    DropdownMenuItem<int?>(
                      value: connection.id,
                      child: Text(
                        _viaLabel(connection, context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _viaId = value),
              ),
            ),
          ],
          const SizedBox(height: _rowSpacing),
          _row(
            height: juiceSpinnerRowHeight,
            label: s('run_snippet'),
            child: _Dropdown<int?>(
              value: _snippetId,
              hint: s('choose_a_snippet'),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(s('form_optional'))),
                for (final snippet in _snippets)
                  DropdownMenuItem<int?>(
                    value: snippet.id,
                    child: Text(snippet.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _snippetId = value),
            ),
          ),
          const SizedBox(height: _rowSpacing),
          _row(
            height: juiceSpinnerRowHeight,
            label: s('backspace_mode'),
            child: _Dropdown<BackspaceMode>(
              value: _backspaceMode,
              items: [
                for (final mode in BackspaceMode.values)
                  DropdownMenuItem<BackspaceMode>(
                    value: mode,
                    child: Text(_backspaceLabel(mode), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _backspaceMode = value);
              },
            ),
          ),
          // `@id/mosh_command_row`：`visibility="gone"`，只有 mosh 类型才显示。
          if (_type == ConnectionType.mosh) ...[
            const SizedBox(height: _rowSpacing),
            _row(
              height: juiceEditRowHeight,
              label: s('command'),
              child: JuiceFormTextField(
                controller: _moshCommand,
                autocorrect: false,
              ),
            ),
          ],

          // ------------------------------------------------------------- Groups --
          const SizedBox(height: _rowSpacing),
          JuiceFormSectionHeader(text: s('groups')),
          // `@id/group_selector_holder` 的内容（原版由 `MultiSelector` 在
          // Java 里填充，标题与按钮文案都是 `@string/add_to_group`）。
          for (final groupId in _groupIds)
            _SelectorRow(
              name: _groupName(context, groupId),
              onRemove: () => setState(() => _groupIds.remove(groupId)),
            ),
          // `@id/group_selector_holder` 里的按钮（`@id/multi_selector_add`）。
          //
          // 实测 `[84,1611][996,1706]`：在表单区域（`[42,1038]`）里再左右各
          // 内缩 42px = 16dp，宽度**撑满**，高 95px = 36dp；按钮顶边距
          // `group_selector_holder` 的顶边（1572）15dp。
          // 原来这里是「左对齐的紧凑按钮」，宽度只有原版的三分之一。
          Padding(
            padding: const EdgeInsets.only(
              top: 15,
              left: _multiSelectorInset,
              right: _multiSelectorInset,
            ),
            child: SizedBox(
              width: double.infinity,
              child: JuiceFormButton(
                // `@string/add_to_group` 资源里是 "Add to group"，
                // 大写由 `JuiceFormButton` 统一处理（原版 Button 的 textAllCaps）。
                label: s('add_to_group'),
                onPressed: _pickGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 类型下拉改变：mosh 行需要跟着出现 / 消失。
  void _onTypeChanged(int? index) {
    if (index == null) return;
    final type = ConnectionType.values[index];
    setState(() {
      _type = type;
      // 切到 mosh 且命令框还是空的，就填上默认值。
      if (type == ConnectionType.mosh && _moshCommand.text.isEmpty) {
        _moshCommand.text = _defaultMoshCommand;
      }
    });
  }

  /// `@id/idSpinner` 的显示文本：按认证顺序列出身份昵称。
  String _identitySummary(BuildContext context) {
    // 原版空选时显示的是 `@string/select_one + "..."`（实测 dump 里
    // `itemTitle` 的文案就是 "Select one..."），不是 `choose_an_identity`
    // —— 后者是 spinner 弹框的标题（`android:prompt`），不会显示在行内。
    if (_identityIds.isEmpty) return '${context.s('select_one')}...';
    final names = [
      for (final id in _identityIds) _identityName(context, id),
    ];
    return names.join(', ');
  }

  String _identityName(BuildContext context, int id) =>
      _identityById(id)?.nickname ?? '#$id';

  String _groupName(BuildContext context, int id) => _groupById(id)?.name ?? '#$id';

  /// `@id/via_spinner` 的条目文本。
  ///
  /// 原版 `ih0` 调 `Connection.w()`，这里用等价的「昵称（地址:端口）」，
  /// 昵称为空时退回 `地址:端口`。
  String _viaLabel(Connection connection, BuildContext context) {
    final host = '${connection.address}:${connection.port}';
    final nickname = connection.nickname.trim();
    return nickname.isEmpty ? host : '$nickname ($host)';
  }

  // --------------------------------------------------------------- 度量常量 --

  /// `@dimen/activity_padding` —— 16dp。
  static const double _activityPadding = 16;

  /// 每行之间的 `android:layout_marginTop="8.0dp"`。
  static const double _rowSpacing = 8;

  /// `@id/port_value` 的实测宽度：`[262,477]` = 215px = 81.9dp
  /// （`android:ems="5"` + `maxEms="5"` 下的实际排版宽度）。
  static const double _portFieldWidth = 215 / 2.625;

  /// 本页 `TableLayout` 第 0 列的宽度（实测 207px = 78.86dp）——由最宽的标签
  /// （"Backspace:" / "Connect Via:"）决定，**整列等宽**，不是每个标签各算各的。
  static const double _labelColumnWidth = 207 / 2.625;

  /// `@id/group_selector_holder` 里按钮的左右内缩：实测按钮 `[84,1611][996,1706]`，
  /// 在表单区域 `[42,1038]` 里再左右各缩 42px = 16dp
  /// （`multi_selector.xml` 自带的内边距）。
  static const double _multiSelectorInset = 16;

  /// 本页的一行「标签 + 控件」。度量都在 `widgets/juice_form.dart` 里，
  /// 这里只固定本页的标签列宽。
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
}

// ===========================================================================
// 复用的小组件
// ===========================================================================


/// 充当 `Spinner` 的紧凑下拉框（原版行高 36dp）。
///
/// 这里没有直接用 `DropdownButtonFormField`，因为它会把当前值画成
/// `InputDecorator` 的浮动标签，和原版 Spinner 的观感差得较远。
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          // 原版 `Spinner` 的左右内边距**不对称**：左侧约 8dp、右侧约 12dp。
          // 依据（连接编辑页 `Type:` 行实测，@2.625）：
          //   原版 值文字 284 / 箭头 963..987
          //   对称 8dp 时 285（差 1px，左侧命中）/ 973..997（箭头偏右 10px）
          //   对称 10dp 时 290 / 968..992（两侧同向偏 +5~6px）
          // `isExpanded: true` 下控件右缘固定，内边距越小箭头越靠右，故对称值
          // 无法同时满足两侧；左侧沿用已验证的 8dp，右侧加 4dp 推出箭头。
          padding: const EdgeInsets.only(left: 8, right: 12),
          hint: hint == null ? null : Text(hint!),
          items: items,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 14,
            color: context.palette.textForm,
          ),
          dropdownColor: context.palette.background,
        ),
      ),
    );
  }
}

/// 一行「值 + 点击弹出选择框」，替代原版 `Spinner` 的单选观感。
class _SelectorValue extends StatelessWidget {
  const _SelectorValue({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: context.palette.textForm),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: context.palette.textForm),
          ],
        ),
      ),
    );
  }
}

/// 已选身份的「序号 + 昵称 + 调序/移除」行。
///
/// 序号即 `connectionidentity.position + 1`，也就是 SSH 认证的尝试次序。
class _SelectedIdentityRow extends StatelessWidget {
  const _SelectedIdentityRow({
    required this.name,
    required this.position,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final String name;
  final int position;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$position.',
              style: TextStyle(fontSize: 14, color: palette.textFormHeading),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: palette.textForm),
            ),
          ),
          // 上移 / 下移：原版 `strings.xml` 里**没有**"上移/下移"这类键，
          // 所以这里不挂 tooltip，只留图标（`remove` 键存在，见下）。
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: canMoveUp ? onMoveUp : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: canMoveDown ? onMoveDown : null,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            // 原版 `@id/multi_selector_remove` 的按钮文案是 `@string/X`，
            // 这里用语义更清楚的 `@string/remove`（两个键都在 strings 里）。
            tooltip: context.s('remove'),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 已选分组的「昵称 + X」行，对应 `multi_selector_item.xml`。
class _SelectorRow extends StatelessWidget {
  const _SelectorRow({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: palette.textForm),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            // 对应 `multi_selector_item.xml` 里的 `@id/multi_selector_remove`
            // 按钮（原版文案 `@string/X`）。
            tooltip: context.s('remove'),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 身份多选对话框
// ===========================================================================

/// 身份多选对话框 —— 对应原版 `@id/idSpinner` + `@string/choose_an_identity`。
///
/// **勾选顺序就是认证尝试顺序**：条目右侧会显示它当前排在第几位；
/// 取消再重新勾选会把它挪到队尾。
///
/// 返回值有两种（所以调用方用 `showDialog<Object>` 接收）：
/// * `List<int>` —— OK 时的勾选结果，已按认证顺序排好；
/// * `true` —— 点了末尾的 `@string/_new...`，调用方应去新建身份；
/// * `null` —— Cancel 或点外部关闭（调用方不做改动）。
class _IdentityPickerDialog extends StatefulWidget {
  const _IdentityPickerDialog({required this.identities, required this.selected});

  final List<Identity> identities;

  /// 进入时的已选顺序。
  final List<int> selected;

  @override
  State<_IdentityPickerDialog> createState() => _IdentityPickerDialogState();
}

class _IdentityPickerDialogState extends State<_IdentityPickerDialog> {
  /// 勾选顺序即认证顺序。
  late final List<int> _order = List<int>.of(widget.selected);

  void _toggle(int identityId, bool checked) {
    setState(() {
      if (checked) {
        if (!_order.contains(identityId)) _order.add(identityId);
      } else {
        _order.remove(identityId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;

    return JuiceAlertDialog(
      title: s('choose_an_identity'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final identity in widget.identities)
              CheckboxListTile(
                value: _order.contains(identity.id),
                onChanged: (checked) => _toggle(identity.id, checked ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(
                  identity.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: (identity.username ?? '').isEmpty
                    ? null
                    : Text(
                        identity.username!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                // 显示当前次序（1 起），让"顺序有意义"这件事可见。
                secondary: _order.contains(identity.id)
                    ? Text(
                        '${_order.indexOf(identity.id) + 1}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: palette.accentBold,
                        ),
                      )
                    : null,
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add),
              // 原版下拉末尾的 `@string/_new + "..."` 入口：
              // pop 一个 `bool` 让调用方去打开新建身份页。
              title: Text('${s('_new')}...'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(
          label: s('ok'),
          onPressed: () => Navigator.of(context).pop(List<int>.of(_order)),
        ),
      ],
    );
  }
}

// ===========================================================================
// 分组多选对话框
// ===========================================================================

/// 分组多选对话框 —— 对应原版 `xj0`（`MultiSelector`）弹出的选择框。
///
/// 分组没有顺序语义，只做勾选。
class _GroupPickerDialog extends StatefulWidget {
  const _GroupPickerDialog({required this.groups, required this.selected});

  final List<ConnectionGroup> groups;
  final List<int> selected;

  @override
  State<_GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<_GroupPickerDialog> {
  late final Set<int> _selected = <int>{...widget.selected};

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return JuiceAlertDialog(
      title: s('groups'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final group in widget.groups)
              CheckboxListTile(
                value: _selected.contains(group.id),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selected.add(group.id);
                  } else {
                    _selected.remove(group.id);
                  }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(
          label: s('ok'),
          // 保持与 `_groups` 的原始顺序，避免每次保存都打乱分组顺序。
          onPressed: () => Navigator.of(context).pop([
            for (final group in widget.groups)
              if (_selected.contains(group.id)) group.id,
          ]),
        ),
      ],
    );
  }
}
