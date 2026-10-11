import 'dart:async';

import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_popup_menu.dart';
import '../widgets/pager_tab_strip.dart';
import 'connections_screen.dart';
import 'identities_screen.dart';
import 'port_forwards_screen.dart';

/// 「通讯录」三标签页 —— 对应原版
/// `com.sonelli.juicessh.activities.AddressBookActivity`。
///
/// 结构与原版 `res/layout/address_book.xml` 一致：一个横向可滑动的
/// ViewPager，顶部带 `PagerTabStrip`。原版把 `PagerTabStrip` 放在 ViewPager
/// 内部并加 `layout_gravity="top"`，ViewPager 的 `onMeasure` 会从
/// `mTopPageBounds` 里扣掉条带高度，所以**页面内容从条带下方开始**、
/// 不会钻到条带底下（实测：条带 275..359px，内容 359..2337px）。
/// 因此这里用 `Column[条带, Expanded(页面)]` 是与原版等价的。
///
/// ## 标签顺序与默认页（反编译确认，曾一度写反）
///
/// `eh0`（PagerAdapter）的构造里，`b` 这个 `ArrayList<Integer>` 的装入顺序是：
/// 先按 `kj0.a().t()` 决定是否加 `0`，然后**固定**加 `1`、`2`；
/// `getPageTitle` 把 `0/1/2` 分别映射到 `port_forwards` /
/// `connections_capital_c` / `identities`。
/// 而 `kj0.t()` 恒返回 `true`（`kj0.smali:589`），所以：
///
/// | 页序 | 标签 | 页面 |
/// |---|---|---|
/// | 0 | Port Forwards | `port_forwards` |
/// | 1 | Connections | `address_list` |
/// | 2 | Identities | `identity_list` |
///
/// `AddressBookActivity.j()` 用的是 `setCurrentItem(Q.h(1))`，
/// 即 `b.indexOf(1)` = **1**，所以打开时停在中间的 **Connections**。
/// 420dpi 实测也正是这个顺序（Port Forwards 贴左、Connections 居中、
/// Identities 贴右）。
///
/// ## 溢出菜单（**每个标签页各有一个菜单文件**）
///
/// 这里曾经写错过：以为 `onCreateOptionsMenu` 无条件 inflate 同一个菜单、
/// 于是「New Group 三页都在」。真机实测把它推翻了 —— **身份页根本没有溢出按钮**。
/// 真相是三个标签页各自 inflate 一个菜单：
///
/// | 页 | 菜单资源 | 内容 | 结果 |
/// |---|---|---|---|
/// | 0 Port Forwards | `menu_addressbook_portforwards` | `menu_item_new_portforward`（`visible="false"`） | 无可见项 → **没有溢出按钮** |
/// | 1 Connections | `menu_addressbook_connections` | `menu_item_new_connection`（`visible="false"`）+ `menu_item_new_group` | 只有 New Group |
/// | 2 Identities | `menu_addressbook_identities` | `menu_item_new_identity`（`visible="false"`） | 无可见项 → **没有溢出按钮** |
///
/// 三个 `menu_item_new_*` 都写了 `android:visible="false"`，而全工程没有任何一处
/// 调用 `setVisible` —— 所以那三个「新建」菜单项都是**死代码**（`onOptionsItemSelected`
/// 里却老老实实处理了它们），新建动作实际由右下角各家自己的 FAB 承担。
///
/// AppCompat 在**没有任何可见菜单项时会连溢出按钮一起隐藏**，这就是身份页和
/// 端口转发页看不到三个点、而溢出按钮位置又恰好是 `LinearLayoutCompat` 在
/// ActionBar 里占位的原因。实测佐证：原版连接页有 `ImageView "More options"`
/// `[985,138][1080,264]`，身份页与端口转发页的 `action_bar` 下**只有**返回按钮。
///
/// 另外注意：端口转发页对非 Pro 用户显示的是 `@id/problock` 付费墙
/// （见 `port_forwards.xml`，正常列表的 `@id/empty` 默认 `visibility="gone"`），
/// 本复刻按需求把端口转发做成了可用功能，属有意偏离。
class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  /// 默认停在 Connections（页序 1），见类文档。
  static const int _initialPage = 1;

  final PageController _controller =
      PageController(initialPage: _initialPage);
  int _index = _initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 新建分组。对应溢出菜单里的 `new_group`。
  Future<void> _newGroup() async {
    final s = context.s;
    final name = await JuiceDialogs.promptForText(
      context,
      title: s('new_group'),
    );
    if (name == null || name.trim().isEmpty) return;
    await JuiceDatabase.instance.saveGroup(ConnectionGroup(name: name.trim()));
  }

  /// 溢出菜单。只有 Connections 页有可见项，见类文档。
  ///
  /// `menu_item_new_connection` 是 `android:visible="false"` 的死项，
  /// 所以展开后只剩 `new_group` 一项。
  Future<void> _showOverflowMenu() async {
    final s = context.s;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // 锚在右上角动作按钮上；原版 `ImageView` 实测 `[985,138][1080,264]`，
    // 即距右边缘 36.2dp、高 48dp。
    final anchor = Rect.fromLTWH(
      overlay.size.width - 36,
      MediaQuery.paddingOf(context).top + 4,
      36,
      48,
    );
    final action = await showJuicePopupMenu<String>(
      context: context,
      anchor: anchor,
      items: [
        JuicePopupItem<String>(value: 'new_group', label: s('new_group')),
      ],
    );
    if (!mounted) return;
    if (action == 'new_group') await _newGroup();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // 顺序必须与 eh0 的 b 列表一致，见类文档。
    final titles = [
      s('port_forwards'),
      s('connections_capital_c'),
      s('identities'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(s('juicessh')),
        actions: [
          // 只有 Connections 页（页序 1）的菜单里存在可见项，
          // 其余两页 AppCompat 会把溢出按钮一起隐藏。
          if (_index == 1)
            IconButton(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert),
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 48),
              onPressed: () => unawaited(_showOverflowMenu()),
            ),
        ],
      ),
      body: Column(
        children: [
          JuicePagerTabStrip(
            titles: titles,
            controller: _controller,
            index: _index,
            textColor: context.palette.textHeading,
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (index) => setState(() => _index = index),
              children: const [
                PortForwardsScreen(),
                ConnectionsScreen(),
                IdentitiesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
