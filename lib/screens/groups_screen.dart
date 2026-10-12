import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_popup_menu.dart';
import '../widgets/pager_list.dart';
import 'identities_screen.dart';

/// 连接分组管理页。
///
/// ### 原版事实：**没有独立的"分组列表"页**
/// 反编译资源里没有 group 列表的布局/Activity。原版的分组管理分散在两处：
/// * 新建：`AddressBookActivity` 的 Connections 页溢出菜单
///   `res/menu/menu_addressbook_connections.xml` 的 `menu_item_new_group`
///   → `@string/new_group`，`app:showAsAction="never"`；
///   弹出的对话框是 `com/sonelli/util/NewGroupPrompt.smali`：
///   * 布局 `res/layout/new_group_prompt.xml` ——
///     `EditText id=@id/text1 hint=@string/group_name`，
///     外层 `paddingLeft/Right=@dimen/dialog_padding_left/right`、
///     `paddingTop=@dimen/dialog_padding_top`、
///     `paddingBottom=@dimen/dialog_padding_bottom`；
///   * 标题 `@string/new_group`（`vk0.i(0x7f110300)`）；
///   * 正文 `@string/please_enter_a_name_for_this_group`
///     （`vk0.g(0x7f110339)`）；
///   * 按钮 `@string/ok`（0x7f11031b）/ `@string/cancel`（0x7f110059）；
///   * `setCancelable(true)`。
/// * 重命名 / 分享 / 删除：连接列表里分组标题的长按菜单
///   `res/menu/group_context_menu.xml`（`AddressBookActivity.smali`
///   第 2354-2363 行以 `@string/manage_group` 作菜单标题）：
///   1. `edit`（0x7f0900a1）→ 打开 `ManageGroupActivity`，即改名；
///   2. `share`（0x7f0901c5）→ TeamShare 分享（Pro 功能，本文件不实现）；
///   3. `delete`（0x7f090090）→ **直接删库，没有任何确认框**
///      （`AddressBookActivity.onContextItemSelected` 的 `cond_b` 分支，
///      第 1354-1407 行）。
///
/// 所以本页是"新增的外壳"，但里面每个动作都对应上面某个真实入口；
/// 只有一处**故意偏离原版**：删除分组前加了确认框 —— 任务书要求
/// 「删除分组前用 [JuiceDialogs.confirm] 确认」，而原版不确认。
/// 确认正文取 `@string/are_you_sure_you_want_to_remove_x`
/// （"Are you sure you want to remove %s?"，值为分组名）。这个键在原版里
/// 属于 TeamShare 的移除成员流程（`com/sonelli/wh0.smali:504`），
/// 因为分组删除本身在原版里没有确认文案可用。
///
/// ### 改名
/// 原版的改名入口是 `ManageGroupActivity`：
/// * 布局 `res/layout/manage_group.xml` —— 分组标题 `@string/connection_group`，
///   字段标签 `@string/group_name_colon`（"Group Name:"），
///   输入框 `id=@id/groupName_value`；
/// * 编辑已有分组时 ActionBar 标题被设成
///   `@string/update_group`（`ManageGroupActivity.smali:373`），
///   新建时是 Manifest 里的 `@string/new_group`；
/// * 名称为空时的提示是 `@string/you_must_enter_a_group_name`
///   （`ManageGroupActivity.smali:531`）。
/// 这里把"整个 Activity + 保存菜单"简化为一个单行输入框对话框
/// （标题 `update_group`、hint `group_name`），与 [JuiceDialogs.promptForText]
/// 的能力对齐；空名提示仍用原版那条 `you_must_enter_a_group_name`。
///
/// ### 列表行的副标题
/// 原版没有分组列表，因此没有"分组行副标题"可抄。这里借用
/// `IdentityListAdapter` 的计数文案结构（见 `identities_screen.dart`）：
/// * 0 条 → `@string/not_used`
/// * 1 条 → `@string/used_by` + " 1 " + `@string/connection`
/// * n 条 → `@string/used_by` + " n " + `@string/connections_lowercase`
/// 计数的口径是 `connectiongroupmembership` 表（原版把连接与分组的多对多关系
/// 放在这张表里，见 `JuiceDatabase._schema`）。
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  /// 新建分组的入口图标键。
  ///
  /// `menu_item_new_group` 在原版菜单里没有 `android:icon`；
  /// 这里用 Material 的加号作等价表达（与同项目其它"新建"入口一致）。
  static const IconData newGroupIcon = Icons.add;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  JuiceDatabase get _db => JuiceDatabase.instance;

  List<ConnectionGroup> _groups = const <ConnectionGroup>[];

  /// 分组 id → 该分组下的连接条数。
  Map<int, int> _memberCounts = const <int, int>{};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final groups = await _db.groups();
    final counts = await _memberCountsByGroup();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _memberCounts = counts;
      _loading = false;
    });
  }

  /// 一次查询统计出每个分组下有多少条连接。
  ///
  /// `connectiongroupmembership` 的列名是 `"group"` / `connection`
  /// （`group` 是 SQL 关键字，建表时加了双引号，见 `JuiceDatabase._schema`），
  /// 所以分组列要写成 `"group"`。做法与 `identities_screen.dart` 的
  /// `_identityUsage()` 一致。
  Future<Map<int, int>> _memberCountsByGroup() async {
    final rows = await _db.raw.query(
      'connectiongroupmembership',
      columns: ['"group"', 'COUNT(*) AS total'],
      groupBy: '"group"',
    );
    return {
      for (final row in rows)
        (row['group'] as num).toInt(): (row['total'] as num).toInt(),
    };
  }

  // ------------------------------------------------------------ 展示辅助 --

  /// 分组行的副标题，借用 `IdentityListAdapter` 的计数文案结构。
  String _usageSubtitle(BuildContext context, ConnectionGroup group) {
    final s = context.s;
    final count = _memberCounts[group.id] ?? 0;
    if (count == 0) return s('not_used');
    final noun = count == 1 ? s('connection') : s('connections_lowercase');
    return '${s('used_by')} $count $noun';
  }

  // ------------------------------------------------------------------ 动作 --

  /// 新建分组 —— 对应 `@string/new_group`（`NewGroupPrompt`）。
  Future<void> _create() async {
    final s = context.s;
    // `NewGroupPrompt` 的标题是 `@string/new_group`，
    // 输入框 hint 是 `new_group_prompt.xml` 里的 `@string/group_name`。
    final name = await JuiceDialogs.promptForText(
      context,
      title: s('new_group'),
      hint: s('group_name'),
    );
    if (!mounted || name == null) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      // `NewGroupPrompt` 里这条文案是对话框正文
      // （`vk0.g(@string/please_enter_a_name_for_this_group)`）；
      // [JuiceDialogs.promptForText] 不支持正文，所以这里把它当作
      // "名字为空"的提示语使用。
      _warn(s('please_enter_a_name_for_this_group'));
      return;
    }

    await _db.saveGroup(ConnectionGroup(name: trimmed));
    if (!mounted) return;
    await _reload();
  }

  /// 重命名分组 —— 对应 `group_context_menu.xml` 的 `edit`，
  /// 也就是原版的 `ManageGroupActivity`（ActionBar 标题 `@string/update_group`）。
  Future<void> _rename(ConnectionGroup group) async {
    final s = context.s;
    final name = await JuiceDialogs.promptForText(
      context,
      title: s('update_group'),
      hint: s('group_name'),
      initialValue: group.name,
    );
    if (!mounted || name == null) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      // `ManageGroupActivity.smali:531` 用这条文案拒绝空名字。
      _warn(s('you_must_enter_a_group_name'));
      return;
    }
    if (trimmed == group.name) return;

    await _db.saveGroup(group.copyWith(name: trimmed));
    if (!mounted) return;
    await _reload();
  }

  /// 删除分组 —— 对应 `group_context_menu.xml` 的 `delete`。
  ///
  /// **偏离原版**：原版直接删库、不确认（见类注释）；
  /// 这里按任务书要求先弹 [JuiceDialogs.confirm]。
  /// 级联由数据库外键负责 —— 建表时 `connection."group"` 是
  /// `ON DELETE SET NULL`、`connectiongroupmembership."group"` 是
  /// `ON DELETE CASCADE`，且 `onConfigure` 里开了 `PRAGMA foreign_keys = ON`。
  Future<void> _delete(ConnectionGroup group) async {
    final s = context.s;
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('delete'),
      message: s.format('are_you_sure_you_want_to_remove_x', [group.name]),
      confirmLabel: s('delete'),
    );
    if (!confirmed || !mounted) return;

    await _db.deleteGroup(group.id);
    if (!mounted) return;
    await _reload();
  }

  /// 长按分组 → 上下文菜单。
  ///
  /// `group_context_menu.xml` 有三项（`edit` → `@string/edit`、
  /// `share` → `@string/share`、`delete` → `@string/delete`）；`share` 属
  /// TeamShare（Pro），本项目未实现，故不列出（原版非 Pro 时也会把它移掉）。
  ///
  /// 表头文案来自第 60 轮那套 smali + `public.xml` 反查：
  /// `AddressBookActivity.smali:2361` 先 `const p2, 0x7f1102c5` 再
  /// `setHeaderTitle`，而 `0x7f1102c5` = `manage_group`（"Manage Group"），
  /// 紧随其后 `inflate(0x7f0d0002)` = `group_context_menu`。同一方法里
  /// `0x7f1102c3`→`manage_connection`、`0x7f1102c6`→`manage_identity` 已在设备上
  /// 实测吻合，故方法可信。
  ///
  /// 第一项文案是 `@string/edit`（"Edit"），**不是** `@string/update_group` ——
  /// 后者是分组编辑页的标题（对应连接编辑页的 "Update Connection"）。
  Future<void> _showContextMenu(ConnectionGroup group, Rect anchor) async {
    final s = context.s;
    final action = await showJuicePopupMenu<_GroupMenuAction>(
      context: context,
      anchor: anchor,
      anchorAtTouch: true,
      title: s('manage_group'),
      items: [
        JuicePopupItem<_GroupMenuAction>(
          value: _GroupMenuAction.rename,
          label: s('edit'),
        ),
        JuicePopupItem<_GroupMenuAction>(
          value: _GroupMenuAction.delete,
          label: s('delete'),
        ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _GroupMenuAction.rename:
        await _rename(group);
      case _GroupMenuAction.delete:
        await _delete(group);
    }
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ 视图 --

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        // 原版没有这一页；资源里 `@string/connection_groups`
        // （"Connection Groups"）是语义最贴切的键。
        title: Text(s('connection_groups')),
        actions: [
          IconButton(
            icon: const Icon(GroupsScreen.newGroupIcon),
            tooltip: s('new_group'),
            onPressed: _create,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                if (_groups.isEmpty)
                  _buildEmptyState(context)
                else
                  ListView.separated(
                    itemCount: _groups.length,
                    // 与其它列表页一致：分隔线沿用 `@drawable/highlight`
                    // （空 selector）的 0.5dp 透明间隙。
                    separatorBuilder: (_, _) => const SizedBox(height: 0.5),
                    itemBuilder: (context, index) {
                      final group = _groups[index];
                      // 原版浮动菜单以**触点**为锚点（第 58/59 轮实测：底色框
                      // 左上角 = 触点坐标）。记下按下的位置，同时保留行自身的
                      // 按压反馈。
                      Offset? lastTouch;
                      return Listener(
                        onPointerDown: (event) => lastTouch = event.position,
                        child: CardListItem(
                          title: group.name,
                          subtitle: _usageSubtitle(context, group),
                          // 原版连接列表里的分组行是展开/折叠箭头；
                          // 这一页是管理页，用文件夹图标更贴切（属于推断）。
                          leadingIcon: Icons.folder,
                          // 点击 = 改名（对应菜单里的 `edit`），
                          // 长按 = 上下文菜单，与同项目其它列表页一致。
                          onTap: () => _rename(group),
                          onLongPress: () {
                            final at = lastTouch;
                            _showContextMenu(
                              group,
                              at == null
                                  ? juiceContextMenuAnchor(context)
                                  : Rect.fromLTWH(at.dx, at.dy, 0, 0),
                            );
                          },
                        ),
                      );
                    },
                  ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    heroTag: null,
                    onPressed: _create,
                    backgroundColor: palette.primaryBold,
                    foregroundColor: Colors.white,
                    tooltip: s('new_group'),
                    child: const Icon(GroupsScreen.newGroupIcon),
                  ),
                ),
              ],
            ),
    );
  }

  /// 空状态。
  ///
  /// 度量沿用 `port_forwards.xml` / `pager_list.xml` 的写法
  /// （标题 `@dimen/text_heading` = 36sp / `@color/text_heading`，
  /// 正文距标题 5dp、`@color/text_subheading`，
  /// 整块 `padding=@dimen/activity_padding` = 16dp），
  /// 因为原版没有这一页、没有专属布局可抄。
  ///
  /// 文案说明：资源里没有 `no_groups` 这类键，取
  /// `@string/new_group` 作标题、`@string/add_group`（"Add Group"）作正文 ——
  /// 两者都是真实键，语义上就是"还没有分组，去新建一个"。
  Widget _buildEmptyState(BuildContext context) {
    // 本页在原版里没有独立界面（分组是在通讯录里通过长按菜单管理的），
    // 属于本复刻新增的可达入口；空态沿用 `pager_list.xml` 那套独立列表页
    // 的通用样式（整块居中），与片段页保持一致。
    return SizedBox.expand(
      child: PagerEmptyState(
        style: PagerEmptyStyle.centered,
        title: context.s('new_group'),
        message: context.s('add_group'),
      ),
    );
  }
}

/// 分组行长按菜单的动作 id。
///
/// 取值对应 `res/menu/group_context_menu.xml` 的两项
/// `edit`（这里叫 `rename`，因为它就是改名）与 `delete`；
/// 该菜单还有第三项 `share`，属于 TeamShare（Pro），未实现。
enum _GroupMenuAction { rename, delete }
