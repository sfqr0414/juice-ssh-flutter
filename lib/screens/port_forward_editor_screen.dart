import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_form.dart';

/// 新建 / 编辑端口转发 —— 对应原版 `activities.ManagePortForwardActivity`。
///
/// `AndroidManifest.xml` 里该 Activity 的 `android:label` 是
/// `@string/new_port_forward`（"New Port Forward"），
/// `parentActivityName` 是 `AddressBookActivity`。
///
/// 界面严格按 `res/layout/manage_port_forward.xml` 还原：
/// ```
/// RelativeLayout  fitsSystemWindows=true  w/h=match_parent
/// └─ ScrollView  padding=@dimen/activity_padding(16dp)
///       scrollbars=vertical  clipToPadding=false  w=match_parent h=wrap_content
///    └─ TableLayout id=@id/table  focusable=true  focusableInTouchMode=true
///       ├─ TableRow → TextView  textColor=@color/text_form_heading
///       │     text=@string/port_forward  style="?android:listSeparatorTextViewStyle"
///       ├─ TableRow  marginTop=8dp  gravity=center_vertical
///       │  ├─ TextView   text=@string/name               (marginRight=5dp)
///       │  └─ EditText id=@id/name        w=0dp weight=1  inputType=text
///       ├─ TableRow  marginTop=8dp  gravity=center_vertical
///       │  ├─ TextView   text=@string/connection_colon
///       │  └─ Spinner  id=@id/connection_spinner  w=0dp h=36dp weight=1
///       ├─ TableRow  marginTop=8dp  gravity=center_vertical
///       │  ├─ TextView   text=@string/mode_colon
///       │  └─ Spinner  id=@id/mode_spinner        w=0dp h=36dp weight=1
///       ├─ TableRow id=@id/row_local_port  marginTop=8dp
///       │  ├─ TextView   text=@string/port_from
///       │  └─ EditText id=@id/local_port  ems=5 maxEms=5 maxLength=5 inputType=number
///       ├─ TableRow id=@id/row_remote_host  visibility=gone  marginTop=8dp
///       │  ├─ TextView   text=@string/destination
///       │  └─ EditText id=@id/remote_host  w=0dp weight=1
///       │        hint=@string/localhost  inputType=textVisiblePassword
///       ├─ TableRow id=@id/row_remote_port  visibility=gone  marginTop=8dp
///       │  ├─ TextView   text=@string/port_to
///       │  └─ EditText id=@id/remote_port  ems=5 maxEms=5 maxLength=5 inputType=number
///       ├─ TableRow id=@id/row_open_in_browser  visibility=gone  marginTop=8dp
///       │  └─ CheckBox id=@id/open_in_browser  weight=1  text=@string/open_in_browser
///       ├─ TableRow id=@id/row_socks_explanation  visibility=gone  marginTop=8dp
///       │  └─ TextView id=@id/socks_explanation  weight=1  paddingTop=8dp
///       │        autoLink=web  text=@string/socks_description
///       └─ TableRow id=@id/row_use_as_proxy  visibility=gone  marginTop=8dp
///          └─ CheckBox id=@id/use_as_proxy  weight=1  text=@string/set_as_browser_proxy
/// ```
///
/// ### 实测几何（420dpi，`o_pf.xml` / `o_pf.png`）
/// 原版这一页默认是 Pro 拦截的（FAB 直接跳 `PurchaseActivity`），所以最初
/// 只能照布局文件推。后来把 APK 里那两处 Pro 判定改掉重打包，才拿到真机基准：
///
/// | 元素 | 原版 bounds | 备注 |
/// | --- | --- | --- |
/// | ActionBar | `[0,128][1080,275]` | 与其它页一致 |
/// | 标题 "New Port Forward" | `[189,159][699,244]` | 墨迹 180..227 |
/// | `menu_item_save` | `[954,138][1080,264]` | 图标（对勾），非文字 |
/// | ScrollView | `[0,275][1080,1288]` | `wrap_content` |
/// | `TableLayout` | `[42,317][1038,1246]` | 内容顶端 317 = 275 + 16dp |
/// | PORT FORWARD 行 | `[42,317][1038,401]` | 高 **84px** |
/// | Name 行 | `[42,422][1038,528]` | 高 106px；标签盒 `[42,449][330,500]` |
/// | Connection / Mode 行 | `[42,549][1038,644]` / `[42,665][1038,760]` | 高 **95px** |
/// | Port (from) 行 | `[42,781][1038,887]` | `local_port` `[343,781][558,887]` |
/// | Destination 行 | `[42,908][1038,1014]` | `remote_host` 满宽，hint=127.0.0.1 |
/// | Port (to) 行 | `[42,1035][1038,1141]` | `remote_port` `[343,1035][558,1141]` |
/// | Open in browser 行 | `[42,1162][1038,1246]` | 高 **84px**，复选框 `[42,1162][1025,1246]` |
///
/// 两个关键列宽：
/// * **标签列 288px**（`42..330`，字段一律从 `343` 起）—— 和连接编辑页的
///   207px、身份编辑页的 194px 都不一样，就是本页最宽标签撑出来的；
/// * **端口输入框 215px**（`343..558`）—— 与连接编辑页的 `@id/port_value`
///   同为 `ems=5`，实测宽度**完全相同**，所以这里直接写 215px，不再靠估算。
///
/// 下划线和其它页同款：`#666666`、1dp、左右各内缩 10px。实测
/// `name` 在 `y=505..506 x=353..1027`、`local_port` 在 `y=864..865 x=353..547`。
///
/// ### 行可见性（逐行照抄 `ManagePortForwardActivity.o(I)`，第 705-775 行）
/// `o(int mode)` 只改动五个 `TableRow`：
/// * `mode == 2`（`MODE_SOCKS` / 动态转发）：
///   `row_remote_host` = GONE、`row_remote_port` = GONE、
///   `row_open_in_browser` = GONE、`row_socks_explanation` = VISIBLE；
/// * `mode == 0` / `1`（`MODE_LOCAL` / `MODE_REMOTE`）：
///   `row_use_as_proxy` = GONE、`row_remote_host` = VISIBLE、
///   `row_remote_port` = VISIBLE、`row_open_in_browser` = VISIBLE、
///   `row_socks_explanation` = GONE。
///
/// 也就是说 SOCKS 时目标主机/端口是**整行隐藏（GONE）**而不是禁用，
/// 本文件照此隐藏（不渲染）。`o(I)` 的调用方是
/// `ManagePortForwardActivity$a.onItemSelected`（`mode_spinner` 的
/// `OnItemSelectedListener`），所以切换模式即时生效。
///
/// `row_use_as_proxy` 在上面两个分支里**都没有被置成 VISIBLE**，
/// 而它在布局里的默认值是 `visibility="gone"` —— 即原版实际上永远看不到
/// "Set as browser proxy" 复选框（上游 bug）。见 [showUseAsProxyRow]。
///
/// ### 保存（`ManagePortForwardActivity.n()` 第 459-703 行）
/// 从控件读值 → 交给 `PortForward.w(Context)` 校验 → 有错就 Toast 并中止
/// → 否则 ORMLite `createOrUpdate` 落库、`setResult(-1)`、`finish()`。
/// 保存入口在 ActionBar：`res/menu/menu_manage_portforward.xml` 只有一项
/// `menu_item_save` → `@string/save`，图标 `@drawable/ic_accept`，
/// `app:showAsAction="ifRoom"`。布局里**没有**底部按钮。
///
/// ### 校验顺序（`PortForward.w(Context)` 第 517-670 行，逐条照抄）
/// 1. `name` 为空 → `@string/you_must_enter_a_name`
/// 2. `connection == null` → `@string/you_must_pick_a_connection`
/// 3. `host` 为空 → **就地写成 `"127.0.0.1"`**（`@string/localhost` 的取值），
///    不算错误
/// 4. `mode == 0/1`：只校验 `remotePort <= 0`
///    → `@string/you_must_enter_a_remote_port`
/// 5. `mode == 2`：`localPort <= 0` → `@string/you_must_enter_a_local_port`；
///    `localPort <= 1024` → `@string/local_port_must_be_higher_than_1024`
///
/// 注意第 4 条：原版**在本地/远程转发时不校验 `localPort`**，
/// 于是这两种模式可以存下 `localPort = 0`。本文件照抄这个行为，
/// 没有额外加校验（加了就与原版不一致）。
///
/// 另外 `n()` 只在输入框文本**非空**时才写回 `localPort` / `remotePort`
/// （第 507-571 行），空文本保留模型里的旧值；`name` 与 `host` 则不加
/// `trim()` 直接写回（第 466-504 行）。本文件同样照抄，不做 trim。
class PortForwardEditorScreen extends StatefulWidget {
  const PortForwardEditorScreen({
    super.key,
    this.portForward,
    this.showUseAsProxyRow = false,
  });

  /// 为 null 时是「新建端口转发」，否则编辑传入的这一条。
  ///
  /// 说明：`JuiceDatabase` 有 `portForwards()` / `savePortForward()` /
  /// `deletePortForward()`，但**没有** `portForward(int id)`，
  /// 所以这里直接接收整个模型对象，而不是像身份编辑页那样接收 id 再查库。
  final PortForward? portForward;

  /// 是否渲染 `@id/row_use_as_proxy`（"Set as browser proxy"）。
  ///
  /// 默认 `false` —— 照抄原版的实际可见行为：`ManagePortForwardActivity.o(I)`
  /// 在 local/remote 分支把它置 GONE，在 SOCKS 分支则完全不碰它，
  /// 而布局默认就是 `gone`，所以原版从来不会显示它。
  /// 传 `true` 则改为在动态转发（SOCKS）时显示该复选框，
  /// 让 `PortForward.useAsProxy` 可以被编辑。
  ///
  /// 两种情况都不会丢数据：保存时该字段的值原样保留。
  final bool showUseAsProxyRow;

  @override
  State<PortForwardEditorScreen> createState() =>
      _PortForwardEditorScreenState();
}

class _PortForwardEditorScreenState extends State<PortForwardEditorScreen> {
  JuiceDatabase get _db => JuiceDatabase.instance;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _host = TextEditingController();
  final TextEditingController _localPort = TextEditingController();
  final TextEditingController _remotePort = TextEditingController();

  /// 被编辑（或新建）的端口转发。新建时是一个空壳，字段在保存时统一写回。
  late PortForward _base;

  /// "Connection:" 下拉框的占位项取值。
  ///
  /// 原版 `ih0`（`ConnectionSpinnerAdapter`）在列表最前面插了一项占位，
  /// 文案取 `@string/pick_one`（"(Pick one)"，因为构造时 `hasEmptyOption=false`；
  /// 为 true 时用 `@string/optional`）。选中它表示"还没选连接"。
  static const int _noConnection = -1;

  List<Connection> _connections = const <Connection>[];
  int? _connectionId;
  PortForwardMode _mode = PortForwardMode.local;
  bool _openInBrowser = false;
  bool _useAsProxy = false;
  bool _loading = true;

  // ------------------------------------------------------------------ 度量 --
  //
  // 全部是 420dpi 下的实测值（1dp = 2.625px），依据见类注释里的表格。

  /// `ScrollView` 的 `padding=@dimen/activity_padding`（16dp）。
  static const double _activityPadding = 16;

  /// 每行 `android:layout_marginTop="8.0dp"`（实测 21px）。
  static const double _rowSpacing = 8;

  /// 本页标签列宽：`TableLayout` 第 0 列实测 288px（`42..330`）。
  static const double _labelColumnWidth = 288 / 2.625;

  /// 端口输入框实测宽 215px（`343..558`），与连接编辑页的 `@id/port_value` 相同。
  static const double _portFieldWidth = 215 / 2.625;

  /// 复选框行行高：实测 84px，比输入框行（106px）矮。
  static const double _checkRowHeight = 84 / 2.625;

  /// 本页的一行「标签 + 控件」。
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

  @override
  void initState() {
    super.initState();
    final existing = widget.portForward;
    _base = existing ?? const PortForward(name: '', mode: PortForwardMode.local);
    _mode = _base.mode;
    _connectionId = _base.connectionId;
    _openInBrowser = _base.openInBrowser;
    _useAsProxy = _base.useAsProxy;

    // 原版只在成功从 Intent 的 `id` 载入一条已有转发后才回填控件
    // （`ManagePortForwardActivity.j(Bundle)` 第 242-409 行的 try 块）；
    // 走 catch（新建）时**不回填**，控件保持布局里的空值。
    // 注意回填用的是 `String.valueOf(int)`，所以已存的 0 会显示成 "0"。
    if (existing != null) {
      _name.text = existing.name;
      _host.text = existing.host ?? '';
      _localPort.text = '${existing.localPort ?? 0}';
      _remotePort.text = '${existing.remotePort ?? 0}';
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _localPort.dispose();
    _remotePort.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final connections = await _db.connections();
    if (!mounted) return;
    setState(() {
      _connections = connections;
      _loading = false;
    });
  }

  // ------------------------------------------------------------------ 保存 --

  /// 读端口输入框。原版只在文本非空时才写回字段（`n()` 第 507-571 行），
  /// 所以空文本要退回 [fallback]。
  int _parsePort(TextEditingController controller, int fallback) {
    final text = controller.text.trim();
    if (text.isEmpty) return fallback;
    return int.tryParse(text) ?? fallback;
  }

  /// `PortForward.w(Context)` 的等价实现。返回 null 表示校验通过。
  ///
  /// 判定顺序与文案见类注释里的清单。
  String? _validate() {
    final s = context.s;
    // 原版判的是 `name.length() < 1`，等价于 isEmpty（且不做 trim）。
    if (_name.text.isEmpty) return s('you_must_enter_a_name');
    if (_connectionId == null) return s('you_must_pick_a_connection');

    if (_mode == PortForwardMode.local || _mode == PortForwardMode.remote) {
      // 原版在 local/remote 分支只校验 remotePort。
      if (_parsePort(_remotePort, _base.remotePort ?? 0) <= 0) {
        return s('you_must_enter_a_remote_port');
      }
      return null;
    }

    final localPort = _parsePort(_localPort, _base.localPort ?? 0);
    if (localPort <= 0) return s('you_must_enter_a_local_port');
    if (localPort <= 1024) return s('local_port_must_be_higher_than_1024');
    return null;
  }

  /// 保存 —— 对应 ActionBar 上的 `menu_item_save`（`@string/save`）。
  Future<void> _save() async {
    // 先把 Navigator 取出来：`await` 之后再用 `context` 会触发
    // `use_build_context_synchronously`。
    final navigator = Navigator.of(context);

    final error = _validate();
    if (error != null) {
      // 原版是 `Toast.makeText(this, error, Toast.LENGTH_SHORT).show()`。
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final name = _name.text;
    final host = _host.text;
    final saved = _base.copyWith(
      name: name,
      mode: _mode,
      connectionId: _connectionId,
      // 原版校验时把空的 host 就地写成字面量 "127.0.0.1"
      // （`w(Context)` 第 552-568 行），它的取值恰好等于 `@string/localhost`。
      host: host.isEmpty ? '127.0.0.1' : host,
      localPort: _parsePort(_localPort, _base.localPort ?? 0),
      remotePort: _parsePort(_remotePort, _base.remotePort ?? 0),
      openInBrowser: _openInBrowser,
      useAsProxy: _useAsProxy,
    );
    await _db.savePortForward(saved);
    if (!mounted) return;
    navigator.pop(true);
  }

  // ------------------------------------------------------------------ 视图 --

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final editing = widget.portForward != null;

    return Scaffold(
      appBar: AppBar(
        // 原版 ActionBar 标题：载入已有转发时被 `setTitle(0x7f1103f5)` 改成
        // `@string/update_port_forward`（"Update Port Forward"），
        // 新建时保持 Manifest 里的 `@string/new_port_forward`。
        //
        // 下移 4px：原版标题墨迹在 `y=180..227`（实测 `[189,159][699,244]`），
        // Flutter 的 `AppBar` 居中后会高 4px；`NavigationToolbar` 会重新居中，
        // 所以只能 `Transform` 平移（`Padding` 会撑高盒子、只挪一半）。
        title: Transform.translate(
          offset: const Offset(0, 4 / 2.625),
          child: Text(s(editing ? 'update_port_forward' : 'new_port_forward')),
        ),
        actions: [
          // `menu_manage_portforward.xml`：`menu_item_save` → `@string/save`，
          // 图标 `@drawable/ic_accept`（白色对勾）→ Material 的 `Icons.check`。
          //
          // 31.5dp 是按墨迹反推的（原版对勾墨迹 60×44px，`Icons.check` 在
          // 24dp 时是 45×34px，等比 1.33 倍），与连接/身份编辑页同款。
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

    // 动态转发（SOCKS）时隐藏目标主机/端口/浏览器三行，改为显示 SOCKS 说明。
    final dynamicMode = _mode == PortForwardMode.dynamic;

    // `@id/scroll_view`：`padding=@dimen/activity_padding`（16dp）、
    // `clipToPadding=false`。
    return SingleChildScrollView(
      padding: const EdgeInsets.all(_activityPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 分组标题：`@string/port_forward`。
          JuiceFormSectionHeader(text: s('port_forward')),
          const SizedBox(height: _rowSpacing),

          // `@id/name`：`@string/name`（"Name:"）。
          _row(
            height: juiceEditRowHeight,
            label: s('name'),
            child: JuiceFormTextField(controller: _name),
          ),

          const SizedBox(height: _rowSpacing),
          // `@id/connection_spinner`：`@string/connection_colon`。
          _row(
            height: juiceSpinnerRowHeight,
            label: s('connection_colon'),
            child: _Dropdown<int>(
              value: _selectedConnectionValue,
              items: [
                // 占位项，对应 `ConnectionSpinnerAdapter` 的第 0 项
                // （`@string/pick_one`）。
                DropdownMenuItem<int>(
                  value: _noConnection,
                  child: Text(s('pick_one')),
                ),
                for (final connection in _connections)
                  DropdownMenuItem<int>(
                    value: connection.id,
                    child: Text(
                      _connectionDisplayName(connection),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _connectionId =
                    value == null || value == _noConnection ? null : value;
              }),
            ),
          ),

          const SizedBox(height: _rowSpacing),
          // `@id/mode_spinner`：`@string/mode_colon`。
          // 顺序 = `PortForwardMode` 的声明顺序 = 原版枚举值 local(0)/remote(1)/
          // dynamic(2)（`PortForward.smali` 的 MODE_LOCAL/MODE_REMOTE/MODE_SOCKS），
          // 因为原版是 `mode_spinner.setSelection(PortForward.mode)`，
          // 且 `th0` 适配器按同样的下标给出 `local` / `remote` / `dynamic_socks`。
          _row(
            height: juiceSpinnerRowHeight,
            label: s('mode_colon'),
            child: _Dropdown<int>(
              value: _mode.index,
              items: [
                for (final mode in PortForwardMode.values)
                  DropdownMenuItem<int>(
                    value: mode.index,
                    child: Text(s(modeLabelKey(mode))),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                // `ManagePortForwardActivity$a.onItemSelected` → `o(mode)`：
                // 切换模式即时改变下面几行的可见性。
                setState(() => _mode = PortForwardMode.values[value]);
              },
            ),
          ),

          const SizedBox(height: _rowSpacing),
          // `@id/row_local_port`：`@string/port_from`（"Port (from):"）。
          // 宽度 `wrap_content` + `ems=5`，实测 215px（不是 `weight=1`）。
          _row(
            height: juiceEditRowHeight,
            label: s('port_from'),
            child: SizedBox(
              width: _portFieldWidth,
              child: JuiceFormTextField(
                controller: _localPort,
                keyboardType: TextInputType.number,
                inputFormatters: const [_PortFieldFormatter()],
              ),
            ),
          ),

          // `@id/row_remote_host` / `@id/row_remote_port`：
          // 原版只在非 SOCKS 时显示（`o(I)` 里被置 VISIBLE）。
          if (!dynamicMode) ...[
            const SizedBox(height: _rowSpacing),
            _row(
              height: juiceEditRowHeight,
              label: s('destination'),
              child: JuiceFormTextField(
                controller: _host,
                // `@id/remote_host` 的 `hint=@string/localhost`（"127.0.0.1"）。
                hintText: s('localhost'),
                // `inputType=textVisiblePassword`：不做自动联想/纠错。
                autocorrect: false,
              ),
            ),
            const SizedBox(height: _rowSpacing),
            _row(
              height: juiceEditRowHeight,
              label: s('port_to'),
              child: SizedBox(
                width: _portFieldWidth,
                child: JuiceFormTextField(
                  controller: _remotePort,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_PortFieldFormatter()],
                ),
              ),
            ),
          ],

          // `@id/row_open_in_browser`：原版只在非 SOCKS 时显示。
          // 行高 84px（实测），比输入框行矮。
          if (!dynamicMode) ...[
            const SizedBox(height: _rowSpacing),
            JuiceCheckRow(
              height: _checkRowHeight,
              label: s('open_in_browser'),
              value: _openInBrowser,
              onChanged: (value) => setState(() => _openInBrowser = value),
            ),
          ],

          // `@id/row_socks_explanation`：原版只在 SOCKS 时显示。
          if (dynamicMode) ...[
            const SizedBox(height: _rowSpacing),
            Padding(
              // `paddingTop="8.0dp"`（行本身已有 `marginTop=8dp`）。
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                // `autoLink="web"`：原版会把文中的 URL 变成可点链接。
                // Flutter 侧未接入 url_launcher，这里按纯文本展示。
                s('socks_description'),
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.textForm,
                ),
              ),
            ),
          ],

          // `@id/row_use_as_proxy`：原版从未显示过它，见
          // [PortForwardEditorScreen.showUseAsProxyRow]。
          if (widget.showUseAsProxyRow && dynamicMode) ...[
            const SizedBox(height: _rowSpacing),
            JuiceCheckRow(
              height: _checkRowHeight,
              label: s('set_as_browser_proxy'),
              value: _useAsProxy,
              onChanged: (value) => setState(() => _useAsProxy = value),
            ),
          ],
        ],
      ),
    );
  }

  /// `Connection.w()`（`models/Connection.smali`）的等价实现：
  /// 昵称非空取昵称，否则取地址。原版连接下拉框就用它作文本。
  String _connectionDisplayName(Connection connection) =>
      connection.nickname.isNotEmpty ? connection.nickname : connection.address;

  /// 当前下拉框的取值。存的那条连接若已被删除，就退回占位项，
  /// 否则 `DropdownButton` 会因为 value 不在 items 里而断言失败。
  int get _selectedConnectionValue {
    final id = _connectionId;
    if (id == null) return _noConnection;
    final exists = _connections.any((connection) => connection.id == id);
    return exists ? id : _noConnection;
  }
}

/// 端口转发模式的文案键。
///
/// 依据 `com/sonelli/th0.smali`（`ModeSpinnerAdapter`）的 `getView`：
/// 下标 0 → `@string/local`、1 → `@string/remote`、2 → `@string/dynamic_socks`。
String modeLabelKey(PortForwardMode mode) => switch (mode) {
      PortForwardMode.local => 'local',
      PortForwardMode.remote => 'remote',
      PortForwardMode.dynamic => 'dynamic_socks',
    };

/// 充当 `Spinner` 的紧凑下拉框（原版行高 36dp）。
///
/// 与连接编辑页的 `_Dropdown` 同款：不用 `DropdownButtonFormField`，
/// 因为它会把当前值画成 `InputDecorator` 的浮动标签，与 Spinner 观感差很远；
/// `DropdownButtonHideUnderline` 去掉 Flutter 自带的下划线（原版 Spinner
/// 只有右下角一个小三角，没有下划线）。
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // `Spinner` 的 `android:layout_height="36.0dp"`。
      height: 36,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          isDense: true,
          // 与连接编辑页 `_Dropdown` 同款：原版 `Spinner` 的左右内边距不对称
          // （左约 8dp、右约 12dp），且 `isDense: true` 会压掉 `DropdownButton`
          // 的默认内边距，故显式钉死。
          // 依据：`manage_port_forward.xml` 里 `connection_spinner` / `mode_spinner`
          // 均为 `layout_width=0dp + layout_weight=1.0 + height=36dp`，**无 style 覆盖**，
          // 即默认 Spinner 样式 —— 与连接编辑页的 Spinner 同源同值。
          // 连接编辑页实测（`Type:` 行）：原版 值文字 284 / 箭头 963..987；
          // 本组取值改后为 285 / 963..986（差 1px / 0-1px）。
          padding: const EdgeInsets.only(left: 8, right: 12),
          style: TextStyle(fontSize: 14, color: context.palette.textForm),
          dropdownColor: context.palette.background,
        ),
      ),
    );
  }
}

/// 端口号的输入限制，对应 `@id/local_port` / `@id/remote_port` 上的
/// `inputType=number` + `maxLength="5"`。
///
/// 原版只靠 `Integer.parseInt` 的 `NumberFormatException` 兜底，
/// 这里直接以「最多 5 位数字」表达同一件事。
class _PortFieldFormatter extends TextInputFormatter {
  const _PortFieldFormatter();

  /// `maxLength="5"`。
  static const int maxLength = 5;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final text =
        digits.length > maxLength ? digits.substring(0, maxLength) : digits;
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}