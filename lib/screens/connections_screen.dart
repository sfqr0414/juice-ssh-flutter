import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../terminal/terminal_page.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/pager_list.dart';
import 'connection_editor_screen.dart';
import 'groups_screen.dart';
import '../widgets/juice_popup_menu.dart';

/// @brief 连接列表 —— `AddressBookActivity` 的第一个标签页。
///
/// 数据来源与原版一致：`connection` 表 + `connectiongroup` 分组 +
/// `connectionidentity` 多对多关联（用来取用户名）+ `connectioncounter`
/// 使用次数。
///
/// 行内副标题：第 70 轮实测推翻了"按 `用户名@地址:端口` 与 `connected_x_times`
/// 拼装"的早期推断 —— 原版连接列表行里**没有**这段文案，实际显示的是
/// **关联身份的显示名**（见 `_subtitleFor` / `_identityLabelFor`）。
class ConnectionsScreen extends StatefulWidget {
  /// @brief 创建连接列表页 widget。
  const ConnectionsScreen({super.key});

  /// @brief 创建连接列表页的状态对象。
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

/// @brief 连接列表页的状态：分组折叠与身份关联缓存。
class _ConnectionsScreenState extends State<ConnectionsScreen> {
  /// @brief 数据库单例。
  JuiceDatabase get _db => JuiceDatabase.instance;

  /// @brief 全部连接，按数据库返回顺序展示。
  List<Connection> _connections = const [];
  /// @brief 全部真实分组（不含后追加的 All 伪分组）。
  List<ConnectionGroup> _groups = const [];
  /// @brief 全部身份，用于解析连接行的副标题。
  List<Identity> _identities = const [];
  /// @brief 连接 id → 关联身份 id 列表，取自 connectionidentity 表。
  Map<int, List<int>> _identityLinks = const {};
  /// @brief 是否仍在加载数据，加载中显示进度圈。
  bool _loading = true;

  /// @brief 已折叠的分组。
  ///
  /// 原版的 `connectiongroup` 表里**没有**展开状态字段，
  /// 所以展开/折叠只存在于内存中，这里同样只放在界面状态里，不落库。
  final Set<int> _collapsed = <int>{};

  /// @brief 初始化并触发首次数据加载。
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// @brief 读取连接、分组、身份与身份关联后刷新界面。
  Future<void> _load() async {
    final connections = await _db.connections();
    final groups = await _db.groups();
    final identities = await _db.identities();
    // 这里原先还取了 `_db.connectionCounters()` 用于行内「Connected N times」。
    // 第 70 轮实测证明原版**连接列表行里没有这段文案**（见 `_subtitleFor`），
    // 使用次数只出现在首页「Frequently Used」卡片上，故不再需要。
    final links = <int, List<int>>{};
    for (final connection in connections) {
      links[connection.id] = await _db.connectionIdentityIds(connection.id);
    }
    if (!mounted) return;
    setState(() {
      _connections = connections;
      _groups = groups;
      _identities = identities;
      _identityLinks = links;
      _loading = false;
    });
  }

  // ---------------------------------------------------------- 展示辅助 --

  /// @brief 该连接第一个身份的用户名，用于副标题。
  ///
  /// 没有身份时返回 null。
  String? _usernameFor(Connection connection) {
    for (final id in _identityLinks[connection.id] ?? const <int>[]) {
      for (final identity in _identities) {
        if (identity.id == id && (identity.username ?? '').isNotEmpty) {
          return identity.username;
        }
      }
    }
    return null;
  }

  /// @brief 连接行副标题 = 关联身份的**显示名**（`Identity.toString()` 口径：
  /// 昵称非空取昵称，否则取用户名），与 Identities 页那一行的标题同一个值
  /// （`identities_screen.dart:512-517` 的 `_titleOf`）。
  ///
  /// 第 70 轮实测（`.research/cnt_o2.png`，地址簿打开后 4 次采样、跨 28 秒完全
  /// 一致）：原版连接行只有**两行** —— `10.0.2.2` `[189,591][342,644]` 与
  /// `juice` `[189,644][257,696]`（第二行只有 68px 宽，就一个词）。原版既没有
  /// `user@host:port` 这一行，也没有 `Connected N times · Connection: ssh`。
  /// 原版库里 `identity` 行是 `username='juice'`、`nickname=None`，正好说明这个
  /// `juice` 取的就是身份显示名。
  ///
  /// 没有关联身份时用 `@string/no_identity`（"No identity" / "无认证"）。依据
  /// `hh0.smali:219-245`，逐字对应：取到 identity 就调
  /// `Identity;->toString()`，为 null 则 `getString(0x7f11030e)` =
  /// `@string/no_identity`，随后 `HashMap.put(connectionId, 文本)` 缓存起来供
  /// 适配器取用 —— 与身份列表 `nh0$b` 是同一套「后台算好、缓存、再刷新」写法。
  String _identityLabelFor(Connection connection) {
    for (final id in _identityLinks[connection.id] ?? const <int>[]) {
      for (final identity in _identities) {
        if (identity.id != id) continue;
        final nickname = identity.nickname;
        if (nickname.isNotEmpty) return nickname;
        return identity.username ?? '';
      }
    }
    return context.s('no_identity');
  }

  /// @brief 连接行副标题，当前等于关联身份的显示名。
  String _subtitleFor(Connection connection) => _identityLabelFor(connection);

  /// @brief 原版的 `All` 伪分组：没有数据库实体，成员是**全部**连接。
  ///
  /// `hh0$a.smali:345-387`（连接列表的 `AsyncTask`）：真实分组处理完之后，只要连接
  /// 表非空就再构造一个名字为 `@string/all` 的 `ConnectionGroup`，成员取
  /// `HashMap.values()` —— 即全部连接；随后对每个分组的成员
  /// `Collections.sort()`（`hh0$a.smali:421`，即模型自身的比较口径，本克隆沿用
  /// 数据库返回顺序）。它没有实体，`id` 用模型默认值 0（真实分组是 SQLite 自增、
  /// 从 1 开始），折叠状态照旧按 `id` 记。
  ConnectionGroup get _allGroup => ConnectionGroup(name: context.s('all'));

  /// @brief 组装成「分组标题 + 其下连接」的扁平结构，末尾追加原版的
  /// `All` 伪分组。
  List<Object> get _entries {
    final result = <Object>[];
    for (final group in _groups) {
      final members =
          _connections.where((c) => c.groupId == group.id).toList();
      if (members.isEmpty) continue;
      result.add(group);
      if (!_collapsed.contains(group.id)) result.addAll(members);
    }
    if (_connections.isNotEmpty) {
      final all = _allGroup;
      result.add(all);
      if (!_collapsed.contains(all.id)) result.addAll(_connections);
    }
    return result;
  }

  // ---------------------------------------------------------- 交互 --

  /// @brief 组装身份、snippet 与端口转发后进入终端页。
  Future<void> _connect(Connection connection) async {
    final identities = <Identity>[];
    for (final id in _identityLinks[connection.id] ?? const <int>[]) {
      for (final identity in _identities) {
        if (identity.id == id) identities.add(identity);
      }
    }
    Snippet? snippet;
    if (connection.snippetId != null) {
      final all = await _db.snippets();
      for (final item in all) {
        if (item.id == connection.snippetId) snippet = item;
      }
    }
    // `portforward.connection` 指向本连接的转发（`-L` / `-R` / `-D`），
    // 随会话建立一起启动。
    final forwards = <PortForward>[];
    if (connection.id != 0) {
      final all = await _db.portForwards();
      for (final forward in all) {
        if (forward.connectionId == connection.id) forwards.add(forward);
      }
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalPage(
          connection: connection,
          identities: identities,
          snippet: snippet,
          portForwards: forwards,
        ),
      ),
    );
    // 会话结束后刷新使用次数。
    await _load();
  }

  /// @brief 连接行的长按菜单。
  ///
  /// 原版是 Android 的**浮动上下文菜单**，不是底部弹层：底色框左上角落在触点
  /// 上、宽度 = 最宽文案 + 左右各 16dp（实测 793px）、每项 48dp、无 scrim，
  /// 首行是不可点的表头 `@string/manage_connection`。条目与顺序来自
  /// `res/menu/connection_context_menu.xml`（edit / duplicate / share /
  /// clearHistory / homescreen / delete 共 6 项）；`Share` 与
  /// `Homescreen shortcut` 在原版会按 Pro 状态追加 `(Pro users only)`，
  /// 非 Pro 用户下正是实测看到的带括号写法。
  Future<void> _showContextMenu(Connection connection, Rect anchor) async {
    final s = context.s;
    final proSuffix = '(${s('pro_users_only')})';
    final action = await showJuicePopupMenu<String>(
      context: context,
      anchor: anchor,
      anchorAtTouch: true,
      title: s('manage_connection'),
      items: [
        JuicePopupItem<String>(value: 'edit', label: s('edit')),
        JuicePopupItem<String>(value: 'duplicate', label: s('duplicate')),
        JuicePopupItem<String>(
          value: 'share',
          label: '${s('share')} $proSuffix',
        ),
        JuicePopupItem<String>(
          value: 'clear_history',
          label: s('clear_history'),
        ),
        JuicePopupItem<String>(
          value: 'homescreen',
          label: '${s('homescreen_shortcut')} $proSuffix',
        ),
        JuicePopupItem<String>(value: 'delete', label: s('delete')),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await _openEditor(connection);
      case 'duplicate':
        final copy = connection.copyWith(
          id: 0,
          nickname: s.format('copy_of', [connection.nickname]),
        );
        final newId = await _db.saveConnection(copy);
        // 复制时一并复制身份关联，与原版「副本可直接用」的行为一致。
        final links = _identityLinks[connection.id] ?? const <int>[];
        if (links.isNotEmpty) await _db.setConnectionIdentities(newId, links);
        await _load();
      case 'share':
        await SharePlus.instance.share(
          ShareParams(
            text: 'ssh://${_usernameFor(connection) ?? ''}'
                '${connection.address}:${connection.port}',
            subject: connection.nickname,
          ),
        );
      case 'clear_history':
        await _db.clearConnectionCounter(connection.id);
        await _load();
      case 'homescreen':
        // 原版会往桌面添加一个快捷方式，依赖 Android 专有 API。
        // Flutter 侧要真正实现需要写 MethodChannel 原生代码，本次未做。
        if (!mounted) return;
        await JuiceDialogs.message(
          context,
          title: s('homescreen_shortcut'),
          message: s('please_try_again_later'),
        );
      case 'delete':
        if (!mounted) return;
        final confirmed = await JuiceDialogs.confirm(
          context,
          title: s('delete'),
          // 与下方列表项的 `title:` 保持一致：昵称可能为空（例如直接写库造出来的连接），
          // 这时回退到地址，否则确认框会出现 "Are you sure you want to remove ?"。
          message: s.format('are_you_sure_you_want_to_remove_x', [
            connection.nickname.isEmpty ? connection.address : connection.nickname,
          ]),
          confirmLabel: s('delete'),
        );
        if (!confirmed) return;
        await _db.deleteConnection(connection.id);
        await _load();
    }
  }

  /// @brief 打开连接编辑器，保存后刷新列表。
  Future<void> _openEditor(Connection? connection) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ConnectionEditorScreen(connection: connection),
      ),
    );
    if (saved == true) await _load();
  }

  /// @brief 分组行的长按菜单（对应原版 `group_context_menu.xml`）。
  ///
  /// 原版三项 `edit` / `share` / `delete`：`share` 属 TeamShare（Pro），
  /// 本项目未实现；`edit` 进入分组管理页（对应原版 `manage_group.xml` 那一屏），
  /// `delete` 走与原版同样的确认框。
  ///
  /// 表头文案不是猜的：`AddressBookActivity.smali:2361` 先
  /// `const p2, 0x7f1102c5` 再 `ContextMenu.setHeaderTitle`，而 `public.xml` 里
  /// `0x7f1102c5` = `manage_group`（"Manage Group"），紧随其后 `inflate` 的
  /// `0x7f0d0002` = `group_context_menu`。同一方法里
  /// `0x7f1102c3`→`manage_connection`、`0x7f1102c6`→`manage_identity` 已在设备上
  /// 实测吻合，故方法可信（见第 60 轮笔记）。
  Future<void> _showGroupContextMenu(ConnectionGroup group, Rect anchor) async {
    final s = context.s;
    final action = await showJuicePopupMenu<String>(
      context: context,
      anchor: anchor,
      anchorAtTouch: true,
      title: s('manage_group'),
      items: [
        JuicePopupItem<String>(value: 'edit', label: s('edit')),
        JuicePopupItem<String>(value: 'delete', label: s('delete')),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await _openGroups();
      case 'delete':
        if (!mounted) return;
        final confirmed = await JuiceDialogs.confirm(
          context,
          title: s('delete'),
          message: s.format('are_you_sure_you_want_to_remove_x', [group.name]),
          confirmLabel: s('delete'),
        );
        if (!confirmed) return;
        await _db.deleteGroup(group.id);
        await _load();
    }
  }

  /// @brief 打开分组管理页，返回后刷新列表。
  Future<void> _openGroups() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GroupsScreen()),
    );
    if (mounted) await _load();
  }

  /// @brief 折叠/展开一个分组（仅界面状态）。
  void _toggleGroup(ConnectionGroup group) {
    setState(() {
      if (!_collapsed.remove(group.id)) _collapsed.add(group.id);
    });
  }

  // ---------------------------------------------------------- 构建 --

  /// @brief 构建分组标题与连接混排的列表。
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final entries = _entries;
    return PagerList(
      emptyTitle: s('no_connections'),
      emptyMessage: s('you_do_not_have_any_connections'),
      itemCount: entries.length,
      onNew: () => _openEditor(null),
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is ConnectionGroup) {
          final expanded = !_collapsed.contains(entry.id);
          // 原版的浮动菜单以**触点**为锚点（实测底色框左上角 = 触点坐标）。
          Offset? groupTouch;
          return Listener(
            onPointerDown: (event) => groupTouch = event.position,
            child: JuiceListItem(
              title: entry.name,
              // 分组标题的副标题是**共享状态**：`hh0.smali` 引用
              // `@string/not_shared` / `shared_with_one_team` /
              // `shared_with_x_teams`，布局 `connection_menu_group_item.xml` 的
              // `@android:id/text2`（20dp 高、`@color/text_item_subtitle`）。
              // TeamShare 属 Pro，本项目未实现，所以一律显示「未共享」。
              subtitle: s('not_shared'),
              // 指示器色实测 (77,77,77)：原版这里没有自定义图标，是
              // `ExpandableListView` 默认的 groupIndicator
              // （`connection_menu_group_item.xml` 里没有任何 ImageView），
              // 墨迹 x 78..110、y 442..459，正落在 40dp 图标位（42..147）的中线
              // 上；克隆原来画成白色。亮色主题无实测依据，保持原值。
              leading: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
              leadingColor: context.palette.isDark
                  ? const Color(0xFF4D4D4D)
                  : context.palette.textHeading,
              onTap: () => _toggleGroup(entry),
              // 长按分组标题 → 上下文菜单。
              //
              // 原版在 `AddressBookActivity` 里 inflate 了 `group_context_menu.xml`
              // （`AddressBookActivity.smali:2361-2366`：`ContextMenu.setHeaderTitle`
              // + `MenuInflater.inflate(0x7f0d0002, p1)`），三项是 `edit` / `share` /
              // `delete`；其中 `share` 属 TeamShare（Pro），本项目未实现，
              // 与分组管理页的处理保持一致，故不列出。
              //
              // 这里原先直接把长按映射到分组管理页，并在注释里写成"长按原本没有任何
              // 绑定" —— 那个判断是错的：原版确实绑定了这份菜单。现在长按弹出
              // `Edit` / `Delete`；分组管理页仍可从 `Edit` 进入。
              onLongPress: () {
                final at = groupTouch;
                _showGroupContextMenu(
                  entry,
                  at == null
                      ? juiceContextMenuAnchor(context)
                      : Rect.fromLTWH(at.dx, at.dy, 0, 0),
                );
              },
            ),
          );
        }
        final connection = entry as Connection;
        // 原版的浮动菜单以**触点**为锚点（实测底色框左上角 = 触点坐标）。
        // 这里记下按下的位置，同时保留列表行自己的长按反馈。
        Offset? lastTouch;
        return Listener(
          onPointerDown: (event) => lastTouch = event.position,
          child: JuiceListItem(
            title: connection.nickname.isEmpty
                ? connection.address
                : connection.nickname,
            subtitle: _subtitleFor(connection),
            // 图标色实测 (213,186,49) = `accentBold`：原版
            // `connection_menu_item.xml` 的 `itemIcon` 用 `@color/icon_item`，
            // 实测这一格就是强调色（克隆原来落回默认的 `textHeading`，即白色）。
            // 字号同样照资源：`android:textSize="30.0dp"`。第 72 轮实测墨迹面积
            // 原版 2340px vs 克隆 1657px（线性比 1.19），24dp 默认值 ×1.19 ≈ 30dp，
            // 与 30.0dp 字面吻合。
            // 尺寸按 bbox 反解：第 80 轮实测连接行图标原版 bbox 68x68、克隆
            // 30dp 时 59x59 → 30 × 68/59 ≈ 34.6，取 35。（原版是 FontAwesome
            // 字形，覆盖率 0.86em；克隆 Icons.dns 为 0.75em，故同 em 下更小。）
            leading: const Icon(Icons.dns, size: 35),
            leadingColor: context.palette.accentBold,
            // 原版连接行**没有**右侧箭头：`connection_menu_item.xml` 里只有
            // `itemIcon` + `itemTitle` + `itemSubtitle`（外加一个 gone 的分隔线），
            // 实测原版该行墨迹止于 x 339，而克隆的 chevron 落在 x≈1009。
            onTap: () => _connect(connection),
            onLongPress: () {
              final at = lastTouch;
              _showContextMenu(
                connection,
                at == null
                    ? juiceContextMenuAnchor(context)
                    : Rect.fromLTWH(at.dx, at.dy, 0, 0),
              );
            },
          ),
        );
      },
    );
  }
}
