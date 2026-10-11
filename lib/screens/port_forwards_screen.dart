import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_popup_menu.dart';
import '../widgets/pager_list.dart';
import 'identities_screen.dart';
import 'dart:async';

import 'port_forward_editor_screen.dart';
import '../ssh/port_forward_registry.dart';

/// 端口转发列表页 —— 对应原版 `MainActivity` 的第三个标签页
/// （`AddressBookActivity` 的 ViewPager 第三页）。
///
/// 依据（全部来自反编译资源，逐条可核对）：
/// * `res/layout/port_forwards.xml`：
///   ```
///   RelativeLayout  fitsSystemWindows=true  w/h=match_parent
///   ├─ RelativeLayout id=@id/list_container  w/h=match_parent
///   │  ├─ ListView id=@id/page_list  clipToPadding=false
///   │  │     divider=@drawable/highlight(空 selector)  dividerHeight=0.5dp
///   │  ├─ LinearLayout id=@id/empty  layout_gravity=center  orientation=vertical
///   │  │     visibility=gone  w/h=match_parent
///   │  │  ├─ FrameLayout  w=match_parent h=0dp  weight=0.3
///   │  │  └─ LinearLayout orientation=vertical  padding=@dimen/activity_padding(16dp)
///   │  │        w=match_parent h=0dp  weight=0.7
///   │  │     ├─ TextView id=@id/title    textSize=@dimen/text_heading(36sp)
///   │  │     │     textColor=@color/text_heading   text=@string/no_port_forwards
///   │  │     └─ TextView id=@id/subtitle textColor=@color/text_subheading
///   │  │           layout_marginTop=5dp
///   │  │           text=@string/you_do_not_have_any_port_forwards
///   │  └─ FloatingActionButton id=@id/fab_new_portforward  margin=16dp
///   │        src=@drawable/ic_new  backgroundTint=@color/primary_bold  tint=@color/white
///   └─ RelativeLayout id=@id/problock   ← Pro 升级引导遮罩（本文件不实现，见下）
///   ```
/// * `res/layout/port_forward_item.xml` —— **本页真正的行布局**（不是
///   `card_list_item.xml`）：72dp 行高、左侧 40dp `FontAwesomeTextView`
///   （`@string/icon_share_alt` U+F064）、右侧 `SwitchCompat id=@id/toggleIndicator`、
///   中间标题 16sp / 副标题 12sp。
/// * `PortForwardListAdapter`（反编译落在 `com/sonelli/sh0.smali`，其内部类
///   `sh0$f.smali` 的 `.source` 写着 `PortForwardListAdapter.java`）：
///   * `getView` 把 `@id/itemTitle` 设为 `PortForward.name`
///     （`PortForward.toString()` 同样只返回 `name`）；
///   * `@id/itemSubtitle` 设为 **`@string/via_connection_string`（"via %s"）**
///     并把承载连接 `Connection.w()` 的返回值填进去；取不到时用
///     **`@string/invalid_connection`（"Invalid Connection"）**。
///   这是本页副标题的真相 —— 见 [PortForwardRowStyle]。
/// * 长按菜单 `res/menu/port_forward_context_menu.xml`：四项、无图标、
///   `android:orderInCategory="100"`：
///   1. `edit` → `@string/edit`
///   2. `duplicate` → `@string/duplicate`
///   3. `homescreen` → `@string/homescreen_shortcut`
///   4. `delete` → `@string/delete`
/// * 新建入口 `res/menu/menu_addressbook_portforwards.xml`：
///   `menu_item_new_portforward` → `@string/new_port_forward`，
///   图标 `@drawable/ic_new`，`app:showAsAction="ifRoom"`。
///
/// ### 未实现的原版元素
/// * `@id/problock`：原版在未购买 Pro 时用这一整块遮罩替换列表，文案是
///   `@string/port_forwarding` / `@string/port_forwarding_is_part_of_our_pro`。
///   本项目没有购买/授权状态，无法判断该显示哪一块，故两块文案都保留在
///   `strings_en.json` 里但不渲染。若日后接入授权，在这里加一个分支即可。
/// * `@id/toggleIndicator`（行尾 `SwitchCompat`）：它绑定的是
///   `PortForwardListAdapter$c`，即**建立/断开一条真实转发**的运行时开关，
///   背后是 `ConnectionManager` + SSH 通道层，不属于本次可用的 API
///   （`JuiceDatabase` 里没有、模型里也没有"启用中"字段）。
///   为了不摆一个点不动的假开关，[PortForwardListItem] 只把它做成可选插槽
///   `trailing`，本页默认不传。
class PortForwardsScreen extends StatefulWidget {
  const PortForwardsScreen({
    super.key,
    this.showScaffold = false,
    this.rowStyle = PortForwardRowStyle.viaConnection,
    this.onEditPortForward,
  });

  /// 是否自带 `Scaffold` / `AppBar`。
  ///
  /// 原版这一页是 `AddressBookActivity` 里的一个 ViewPager 页面，
  /// ActionBar 归 Activity 所有，所以默认（false）只提供 body。
  final bool showScaffold;

  /// 副标题样式，见 [PortForwardRowStyle]。
  final PortForwardRowStyle rowStyle;

  /// 点击行时的回调；默认自己 push [PortForwardEditorScreen]。
  final void Function(BuildContext context, PortForward forward)?
      onEditPortForward;

  @override
  State<PortForwardsScreen> createState() => PortForwardsScreenState();
}

/// 端口转发列表行的副标题样式。
///
/// 原版适配器（`sh0.smali`）的 `getView` 把副标题设为
/// `@string/via_connection_string`（"via %s"）填上连接名，**不是**端口映射说明。
/// 但 `PortForward.t(Context)`（`PortForward.smali` 第 226 行起）确实实现了
/// 「转发描述」文案，只是它只被 `com/sonelli/gi0.smali`（桌面小部件）调用，
/// 列表页没用它。
///
/// 因此这里提供两种样式，默认取原版行为：
/// * [viaConnection] —— 原版列表行为：`via <连接名>`；
/// * [forwardDescription] —— 端口映射说明，复用原版真实存在的三条文案键。
enum PortForwardRowStyle {
  /// 原版列表行为：`via <连接昵称或地址>`（`@string/via_connection_string`）。
  viaConnection,

  /// 端口映射说明，取值自 `PortForward.t(Context)` 的真实格式串
  /// （`local_forward_description_short` / `remote_forward_description_short`
  /// / `socks_forward_description`）。
  forwardDescription,
}

/// 端口转发列表页的 ActionBar 动作。
///
/// `res/menu/menu_addressbook_portforwards.xml` 只有一个条目：
/// `menu_item_new_portforward` → `@string/new_port_forward`，图标
/// `@drawable/ic_new`（白色加号），`app:showAsAction="ifRoom"`
/// （`android:visible="false"`，由代码按当前标签页打开）。
class PortForwardsActions {
  const PortForwardsActions._();

  /// 列表标题键。原版这一页的页面标题是在 Java 的 `PagerAdapter` 里设的
  /// （`docs/ui-spec.md` §4.1 标为 UNRESOLVED），这里取资源里语义最贴切的
  /// `@string/port_forwards`（"Port Forwards"）。
  static const String titleKey = 'port_forwards';

  /// 新建端口转发菜单项的标题键，`@string/new_port_forward`。
  static const String newPortForwardKey = 'new_port_forward';

  /// 新建端口转发菜单项，与 `menu_addressbook_portforwards.xml` 等价的
  /// Flutter 写法（`@drawable/ic_new` 是一个加号 → `Icons.add`）。
  static Widget newPortForwardButton(
    BuildContext context,
    VoidCallback onPressed,
  ) {
    return IconButton(
      icon: const Icon(Icons.add),
      tooltip: context.s(newPortForwardKey),
      onPressed: onPressed,
    );
  }
}

/// 端口转发列表行 —— 可复用的列表行组件（本文件导出，供标签页宿主
/// 与其它页面复用）。
///
/// 度量来自 `res/layout/port_forward_item.xml`：
/// * 行高 `@dimen/list_item_height` = **72dp**、`minHeight` 同为 72dp
/// * 整行 `padding=@dimen/activity_padding` = **16dp**
/// * 左侧 `FontAwesomeTextView id=@id/itemIcon`：**40dp × 40dp**、
///   `textSize=24dp`、`gravity=center`、`textColor=@color/icon_item`
///   （`= @color/accent_bold`），字形 `@string/icon_share_alt`（U+F064）
/// * 标题 `@dimen/text_item_title` = **16sp** / `@color/text_item_title`
/// * 副标题 `@dimen/text_item_subtitle` = **12sp** /
///   `@color/text_item_subtitle`
/// * 行尾 `SwitchCompat id=@id/toggleIndicator`，
///   `layout_alignParentRight="true" layout_centerVertical="true"`；
///   文字块是 `layout_toLeftOf=@id/toggleIndicator`，
///   并且 `layout_marginLeft/Right=@dimen/activity_padding`（16dp）
///
/// 实现上把 [CardListItem]（`identities_screen.dart` 导出，度量与本行完全一致）
/// 放进 `Expanded`，再把 [trailing] 贴在右侧，对应原版
/// `layout_toLeftOf="@id/toggleIndicator"` 的关系。
class PortForwardListItem extends StatelessWidget {
  const PortForwardListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;

  /// 行尾控件。原版这里是 `SwitchCompat id=@id/toggleIndicator`。
  ///
  /// 本页默认不传（原因见 [PortForwardsScreen] 的类注释）。
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;

    return Row(
      children: [
        Expanded(
          child: CardListItem(
            title: title,
            subtitle: subtitle,
            // 原版 `@string/icon_share_alt`（FontAwesome U+F064）是"分享"字形；
            // 本项目没有打进 FontAwesome 字体，用语义等价的 Material 图标代替
            // （与 `identities_screen.dart` / `snippets_screen.dart` 的做法一致）。
            leadingIcon: Icons.swap_horiz,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        ),
        if (trailingWidget != null)
          Padding(
            // 原版文字块与开关之间有 `@dimen/activity_padding` = 16dp 的间距。
            padding: const EdgeInsets.only(right: 16),
            child: trailingWidget,
          ),
      ],
    );
  }
}

/// 端口转发列表页。
class PortForwardsScreenState extends State<PortForwardsScreen> {
  JuiceDatabase get _db => JuiceDatabase.instance;

  List<PortForward> _forwards = const <PortForward>[];

  /// 承载连接的字典。原版列表行的副标题就是从这里取显示名
  /// （`Connection.w()` = 昵称非空取昵称，否则取地址）。
  Map<int, Connection> _connections = const <int, Connection>{};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 开关状态来自活动会话，会话建立/断开或别处拨动开关时都要重建列表。
    PortForwardRegistry.instance.addListener(_onForwardsChanged);
    reload();
  }

  @override
  void dispose() {
    PortForwardRegistry.instance.removeListener(_onForwardsChanged);
    super.dispose();
  }

  void _onForwardsChanged() {
    if (mounted) setState(() {});
  }

  /// 拨动一条转发的开关。
  ///
  /// 原版是 `sh0.i()` 翻转开关外观、再由开关的 checked-change 监听真正
  /// 建立/断开；这里直接用 [PortForwardService.toggle] 一次做完。
  /// 该连接没有活动会话时什么也不做（开关保持关着）。
  Future<void> _toggleForward(PortForward forward) async {
    final service =
        PortForwardRegistry.instance.serviceFor(forward.connectionId);
    if (service == null) return;
    await service.toggle(forward);
    if (mounted) setState(() {});
  }

  /// 重新读取端口转发列表与连接表。
  ///
  /// 宿主（标签页）可以在新建/编辑之后调用它刷新列表。
  Future<void> reload() async {
    final forwards = await _db.portForwards();
    final connections = await _db.connections();
    if (!mounted) return;
    setState(() {
      _forwards = forwards;
      _connections = {for (final connection in connections) connection.id: connection};
      _loading = false;
    });
  }

  // ------------------------------------------------------------ 展示辅助 --

  /// `Connection.w()` 的等价实现（`models/Connection.smali`）：
  /// 昵称非空则返回昵称，否则返回地址。
  String _connectionDisplayName(Connection connection) =>
      connection.nickname.isNotEmpty ? connection.nickname : connection.address;

  /// `PortForward.connection` 对应的连接；取不到时返回 null
  /// （原版此时副标题显示 `@string/invalid_connection`）。
  Connection? _connectionOf(PortForward forward) {
    final id = forward.connectionId;
    if (id == null) return null;
    return _connections[id];
  }

  /// 原版适配器的副标题：`@string/via_connection_string`（"via %s"），
  /// 参数是承载连接的显示名；取不到连接时用 `@string/invalid_connection`。
  String _viaSubtitle(PortForward forward) {
    final s = context.s;
    final connection = _connectionOf(forward);
    if (connection == null) return s('invalid_connection');
    return s.format('via_connection_string', [_connectionDisplayName(connection)]);
  }

  /// `PortForward.t(Context)` 的等价实现（`PortForward.smali` 第 226-433 行）。
  ///
  /// 三条分支与参数顺序**逐项照抄**：
  /// * `mode == 2`（`MODE_SOCKS`）→ `socks_forward_description`
  ///   （"Dynamic SOCKS on port %s"），参数 = `localPort`；
  /// * `mode == 1`（`MODE_REMOTE`）→ `remote_forward_description_short`
  ///   （"%1$s:%2$s to %3$s:%4$s"），参数 =
  ///   `connection.address`、`localPort`、`host`、`remotePort`；
  /// * `mode == 0`（`MODE_LOCAL`）→ `local_forward_description_short`
  ///   （"localhost:%1$s to %2$s:%3$s"），参数 =
  ///   `localPort`、`host`、`remotePort`。
  ///
  /// 注意：原版在取 `host` 之前会做一次**就地改写** —— 若 `host` 等于
  /// `"127.0.0.1"` 或 `"localhost"`，就把它替换成 `connection.address`，
  /// 并把结果写回 `PortForward.host` 字段（有副作用）。
  /// 这里只在显示时做等价替换（[_effectiveHost]），**不修改模型**。
  String _descriptionSubtitle(PortForward forward) {
    final s = context.s;
    final connection = _connectionOf(forward);
    final localPort = forward.localPort ?? 0;
    final remotePort = forward.remotePort ?? 0;
    final host = _effectiveHost(forward, connection);

    return switch (forward.mode) {
      PortForwardMode.dynamic =>
        s.format('socks_forward_description', [localPort]),
      PortForwardMode.remote => s.format('remote_forward_description_short', [
          connection?.address ?? '',
          localPort,
          host,
          remotePort,
        ]),
      PortForwardMode.local => s.format('local_forward_description_short', [
          localPort,
          host,
          remotePort,
        ]),
    };
  }

  /// 显示用的目标主机：`127.0.0.1` / `localhost` 会被换成连接地址。
  ///
  /// 对应 `PortForward.t(Context)` 里的就地改写，但这里不改模型
  /// （`PortForward.copyWith` 也没有 `clearHost` 开关）。
  String _effectiveHost(PortForward forward, Connection? connection) {
    final host = forward.host ?? '';
    final address = connection?.address ?? '';
    if (address.isNotEmpty && (host == '127.0.0.1' || host == 'localhost')) {
      return address;
    }
    return host;
  }

  String _subtitle(PortForward forward) => switch (widget.rowStyle) {
        PortForwardRowStyle.viaConnection => _viaSubtitle(forward),
        PortForwardRowStyle.forwardDescription => _descriptionSubtitle(forward),
      };

  // ---------------------------------------------------------- 交互 --

  /// 点击行 → 编辑页；新建 → `@string/new_port_forward`。
  Future<void> _openEditor(PortForward? forward) async {
    final handler = widget.onEditPortForward;
    if (handler != null && forward != null) {
      handler(context, forward);
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PortForwardEditorScreen(portForward: forward),
      ),
    );
    if (!mounted) return;
    if (saved == true) await reload();
  }

  /// 长按行 → 上下文菜单。
  ///
  /// 条目与顺序来自 `res/menu/port_forward_context_menu.xml`（edit / duplicate /
  /// homescreen / delete 四项，与复刻现有条目一致）。
  ///
  /// 表头文案不是猜的：`AddressBookActivity.smali:2514` 先
  /// `const p2, 0x7f1102c8` 取字符串再 `setHeaderTitle`，而 `public.xml` 里
  /// `0x7f1102c8` = `manage_port_forward`（"Manage Port Forward"）；紧接着
  /// `inflate` 的 `0x7f0d0018` = `port_forward_context_menu`。同一方法里表头
  /// `0x7f1102c3`→`manage_connection`（菜单 0x7f0d0000）、`0x7f1102c6`→
  /// `manage_identity`（菜单 0x7f0d0003），这两个已在设备上实测吻合，方法可信。
  ///
  /// `homescreen_shortcut` 那一项同样要拼 `(Pro users only)`：该块 `inflate`
  /// 之后紧接着 `new-instance StringBuilder` + `append(v8)` +
  /// `getString(0x7f11035a = pro_users_only)` + `append(v6)`，与连接菜单里实测到的
  /// `Homescreen shortcut (Pro users only)` 是同一段代码。
  Future<void> _showContextMenu(PortForward forward, Rect anchor) async {
    final s = context.s;
    final proSuffix = '(${s('pro_users_only')})';
    final action = await showJuicePopupMenu<_PortForwardMenuAction>(
      context: context,
      anchor: anchor,
      anchorAtTouch: true,
      title: s('manage_port_forward'),
      items: [
        JuicePopupItem<_PortForwardMenuAction>(
          value: _PortForwardMenuAction.edit,
          label: s('edit'),
        ),
        JuicePopupItem<_PortForwardMenuAction>(
          value: _PortForwardMenuAction.duplicate,
          label: s('duplicate'),
        ),
        JuicePopupItem<_PortForwardMenuAction>(
          value: _PortForwardMenuAction.homescreen,
          label: '${s('homescreen_shortcut')} $proSuffix',
        ),
        JuicePopupItem<_PortForwardMenuAction>(
          value: _PortForwardMenuAction.delete,
          label: s('delete'),
        ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _PortForwardMenuAction.edit:
        await _openEditor(forward);
      case _PortForwardMenuAction.duplicate:
        await _duplicate(forward);
      case _PortForwardMenuAction.homescreen:
        await _homescreenShortcut();
      case _PortForwardMenuAction.delete:
        await _delete(forward);
    }
  }

  /// 复制 —— 对应 `@string/duplicate`。
  ///
  /// 新名字用原版真实的 `@string/copy_of`（"Copy of %s"），
  /// 做法与 `connections_screen.dart` 的复制一致。
  Future<void> _duplicate(PortForward forward) async {
    final s = context.s;
    final copy = forward.copyWith(
      id: 0,
      name: s.format('copy_of', [forward.name]),
    );
    await _db.savePortForward(copy);
    if (!mounted) return;
    await reload();
  }

  /// 主屏快捷方式 —— 对应 `@string/homescreen_shortcut`。
  ///
  /// 原版会往 Android 桌面写一个快捷方式；失败（设备不支持）时 toast
  /// `@string/homescreen_shortcuts_not_supported`。Flutter 侧要真正实现需要
  /// 写 MethodChannel 原生代码，本次未做，因此直接给出原版那条"不支持"提示。
  Future<void> _homescreenShortcut() async {
    final s = context.s;
    await JuiceDialogs.message(
      context,
      title: s('homescreen_shortcut'),
      message: s('homescreen_shortcuts_not_supported'),
    );
  }

  /// 删除 —— 对应 `@string/delete`，删除前用 [JuiceDialogs.confirm] 确认。
  Future<void> _delete(PortForward forward) async {
    final s = context.s;
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('delete'),
      message: s.format('are_you_sure_you_want_to_remove_x', [forward.name]),
      confirmLabel: s('delete'),
    );
    if (!confirmed || !mounted) return;
    await _db.deletePortForward(forward.id);
    if (!mounted) return;
    await reload();
  }

  // ------------------------------------------------------------------ 视图 --

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (!widget.showScaffold) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s(PortForwardsActions.titleKey)),
        actions: [
          PortForwardsActions.newPortForwardButton(
            context,
            () => _openEditor(null),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = context.s;
    final palette = context.palette;

    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_forwards.isEmpty)
          _buildEmptyState(context)
        else
          ListView.separated(
            itemCount: _forwards.length,
            // 原版分隔线是 `@drawable/highlight` —— 一个**空的 `<selector/>`**，
            // 占 0.5dp 却什么都不画。这里保留同样的 0.5dp 间隙而不画线。
            separatorBuilder: (_, _) => const SizedBox(height: 0.5),
            itemBuilder: (context, index) {
              final forward = _forwards[index];
              final service = PortForwardRegistry.instance
                  .serviceFor(forward.connectionId);
              final active = service?.isActive(forward) ?? false;
              // 原版浮动菜单以**触点**为锚点（第 58/59 轮实测：底色框左上角 =
              // 触点坐标）。记下按下的位置，同时保留行自身的按压反馈。
              Offset? lastTouch;
              return Listener(
                onPointerDown: (event) => lastTouch = event.position,
                child: PortForwardListItem(
                  title: forward.name,
                  subtitle: _subtitle(forward),
                  // 行尾 `SwitchCompat id=@id/toggleIndicator`。开关状态来自活动
                  // 会话的转发服务；没有会话时它只是关着，拨动不会生效 —— 原版
                  // 也是这样：`sh0.i()` 只翻转开关外观，真正的建立/断开在
                  // `PortForwardListAdapter$c` 的 checked-change 监听里。
                  trailing: Switch(
                    value: active,
                    onChanged: (_) => unawaited(_toggleForward(forward)),
                  ),
                  // 原版 `AddressBookPagerAdapter` 的 `onItemClick` 调的是
                  // `sh0.i(forward)`：**点整行就是拨这个开关**，编辑走长按菜单
                  // （`port_forward_context_menu.xml` 的 Edit 项）。
                  onTap: () => unawaited(_toggleForward(forward)),
                  onLongPress: () {
                    final at = lastTouch;
                    _showContextMenu(
                      forward,
                      at == null
                          ? juiceContextMenuAnchor(context)
                          : Rect.fromLTWH(at.dx, at.dy, 0, 0),
                    );
                  },
                ),
              );
            },
          ),
        // `@id/fab_new_portforward`：右下角 + 号，`layout_margin=16dp`，
        // `app:backgroundTint=@color/primary_bold`（品牌黄）、
        // `app:tint=@color/white`、`src=@drawable/ic_new`。
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () => _openEditor(null),
            backgroundColor: palette.primaryBold,
            foregroundColor: Colors.white,
            tooltip: s(PortForwardsActions.newPortForwardKey),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  /// 空状态 —— `port_forwards.xml` 的 `@id/empty`。
  ///
  /// 结构：0.3 权重的空白 + 0.7 权重的文字块（两块都是 `h=0dp` +
  /// `layout_weight`）；文字块 `padding=@dimen/activity_padding`(16dp)；
  /// 标题 `@dimen/text_heading`(36sp) / `@color/text_heading`，
  /// 文案 `@string/no_port_forwards`；副标题距标题 5dp、
  /// `@color/text_subheading`，文案 `@string/you_do_not_have_any_port_forwards`。
  Widget _buildEmptyState(BuildContext context) {
    // 几何交给共享的 `PagerEmptyState`（`tabs` 样式 = `port_forwards.xml` 的
    // `weight 0.3 / 0.7` 结构）。本页的 `@id/empty` **没有**额外 padding，
    // 所以标题落在 994px，与连接页一致（身份页才是 1011px）。
    //
    // 注意：原版对非 Pro 用户显示的是 `@id/problock` 付费墙而不是这个空态
    // （`@id/empty` 默认 `visibility="gone"`）；本复刻按需求把端口转发做成了
    // 可用功能，属有意偏离。
    //
    // `Stack` 的非 Positioned 子项拿到的是松约束，所以这里显式铺满，
    // 否则内部的 `Expanded` 会因为高度无界而报错。
    return SizedBox.expand(
      child: PagerEmptyState(
        title: context.s('no_port_forwards'),
        message: context.s('you_do_not_have_any_port_forwards'),
      ),
    );
  }
}

/// 端口转发行长按菜单的动作 id，取值与
/// `res/menu/port_forward_context_menu.xml` 的 `android:id` 一致。
enum _PortForwardMenuAction { edit, duplicate, homescreen, delete }
