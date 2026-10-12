import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../terminal/terminal_page.dart';
import '../widgets/juice_alert_dialog.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_form.dart';
import '../widgets/juice_popup_menu.dart';
import 'address_book_screen.dart';
import 'settings_screen.dart';

/// 原版 `MainActivity`（LAUNCHER）——启动后的卡片式首页。
///
/// 布局来源 `res/layout/card_list.xml` + `res/layout/card_list_item.xml`。
///
/// ## 卡片顺序（重要，与 smali 里的建立顺序不同）
///
/// 原版在 `MainActivity.q()` 里依次建卡，但第 3 张（Manage Connections）之后
/// 调用了 `pi0.j()` 查询购买状态，**回调里的 `n()` / `o()` 才决定后面插入哪几张**：
///
/// * 未登录 / 未购买（绝大多数首屏）：Quick Connect → Frequently Used →
///   Manage Connections → **Unlock Pro Features** → Settings → Help → Plugins →
///   Tech Library。共 8 张。
/// * 已登录且本地 session 有效且已购 Pro：CloudSync + TeamShare 取代
///   Unlock Pro Features，插在 Manage Connections 之后。
///
/// 本复刻没有账号体系与内购，因此恒按**未登录**这一支渲染，与真机实测的
/// 8 张卡片（`uiautomator` 导出核对过）完全一致。
///
/// ## 度量（420dpi 真机实测换算）
///
/// ListView `padding=16dp`、`dividerHeight=16dp`（卡片间距）、卡片圆角 2dp、
/// 卡片内边距 16dp、标题 16sp、副标题 12sp、右侧 FontAwesome 图标 32dp。
/// 卡片高度是 `wrap_content`，实测 70.1dp（16 + 21.7 + 16.4 + 16），
/// 而不是 `@dimen/list_item_height` 的 72dp —— 列表页才用 72dp。
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

/// 「常用连接」卡片里每一页放几项（`MainActivity.smali:654` 写死 3）。
const int _frequentPerPage = 3;

/// 单行高度 `@dimen/...`：`frequently_used_item.xml` 写死 55dp。
const double _frequentRowHeight = 55.0;

/// 本复刻未实现的功能（Pro / 云端 / 账号）：原版这些入口背后分别是
/// PurchaseActivity / ManageCloudSyncActivity / TeamShareActivity /
/// PluginsActivity / BookclubActivity，都需要服务端配合，属于用户明确要求
/// 推迟的 Pro 范围。提示文案统一由 [JuiceDialogs.notInThisBuild] 给出 ——
/// 原版字符串表里自然没有「本复刻未提供」这类文案，这是一处**有意的、可见的
/// 偏离**，好过假装成功或谎报错误。

class _MainScreenState extends State<MainScreen> {
  final JuiceDatabase _db = JuiceDatabase.instance;

  List<Identity> _identities = const [];

  /// 按使用次数降序排列的「常用连接」，与原版 `FrequentlyUsedListAdapter`
  /// 的排序口径一致（`connectioncounter.count DESC`）。
  List<({Connection connection, int count})> _frequent = const [];

  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final connections = await _db.connections();
      final counters = await _db.connectionCounters();
      final identities = await _db.identities();

      final byId = {for (final c in connections) c.id: c};
      final frequent = <({Connection connection, int count})>[];
      // `connectionCounters()` 返回的是 connectionId -> count 的映射。
      for (final entry in counters.entries) {
        final connection = byId[entry.key];
        if (connection != null && entry.value > 0) {
          frequent.add((connection: connection, count: entry.value));
        }
      }
      frequent.sort((a, b) => b.count.compareTo(a.count));

      if (!mounted) return;
      setState(() {
        _identities = identities;
        _frequent = frequent;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------------ 操作 --

  /// `Connection.w()`：昵称优先，其次地址，再次 localhost / Invalid Connection。
  String _connectionName(Connection connection) {
    if (connection.nickname.isNotEmpty) return connection.nickname;
    if (connection.address.isNotEmpty) return connection.address;
    if (connection.type == ConnectionType.local) return 'localhost';
    return 'Invalid Connection';
  }

  Future<void> _openAddressBook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddressBookScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openConnection(
    Connection connection, {
    String? quickConnectUsername,
  }) async {
    // 原版把 Quick Connect 里 `[username@]hostname[:port]` 的用户名挂在一个
    // 临时身份上（`Connection.temporaryQuickConnectIdentity`，transient、不入库），
    // 只用于这一次会话。少了它，认证会以空用户名进行，服务端必然拒绝。
    // 连接自己关联的身份必须排在前面：`ssh_service` 取用户名用的是"第一个非空"，
    // 若把地址簿里的全部身份按原顺序平铺下去，别的身份会把用户名抢走（实测：快速
    // 连接存下的 `juicequick` 被 `lab-key` 身份的 `juice` 顶掉，服务端日志
    // `user='juice'`）。原版同样先按连接关联的身份尝试。
    final linkedIds = connection.id == 0
        ? const <int>[]
        : await _db.connectionIdentityIds(connection.id);
    final identities = <Identity>[
      if (quickConnectUsername != null && quickConnectUsername.isNotEmpty)
        Identity(
          nickname: quickConnectUsername,
          username: quickConnectUsername,
        ),
      ..._identities.where((identity) => linkedIds.contains(identity.id)),
      ..._identities.where((identity) => !linkedIds.contains(identity.id)),
    ];
    // `portforward.connection` 指向本连接的转发，随会话一起启动。
    final forwards = connection.id == 0
        ? const <PortForward>[]
        : (await _db.portForwards())
            .where((forward) => forward.connectionId == connection.id)
            .toList();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalPage(
          connection: connection,
          identities: identities,
          portForwards: forwards,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _launchExternal(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = context.s;
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(s('there_are_no_browsers_available'))),
      );
    }
  }

  Future<void> _openFaq() => _launchExternal('https://sonelli.com/faq');

  Future<void> _rateApp() =>
      _launchExternal('market://details?id=com.sonelli.juicessh');

  /// `res/menu/menu_home.xml`：两项都是 `showAsAction="never"`，即溢出菜单。
  Future<void> _showHomeMenu() async {
    final s = context.s;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // 把菜单锚在右上角动作按钮上。原版那个 `ImageView` 实测
    // `[985,138][1080,264]`，即距右边缘 36.2dp、高 48dp，在 56dp 的
    // ActionBar 里上下居中（(147-126)/2 = 10.5px）。
    final anchor = Rect.fromLTWH(
      overlay.size.width - 36,
      MediaQuery.paddingOf(context).top + 4,
      36,
      48,
    );
    final action = await showJuicePopupMenu<_HomeMenuAction>(
      context: context,
      anchor: anchor,
      items: [
        JuicePopupItem<_HomeMenuAction>(
          value: _HomeMenuAction.faq,
          label: s('view_our_faq'),
        ),
        JuicePopupItem<_HomeMenuAction>(
          value: _HomeMenuAction.rate,
          label: s('rate_juicessh'),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _HomeMenuAction.faq:
        await _openFaq();
      case _HomeMenuAction.rate:
        await _rateApp();
      case null:
        break;
    }
  }

  Future<void> _showNotInBuild(String title) =>
      JuiceDialogs.notInThisBuild(context, title: title);

  /// `com.sonelli.util.QuickConnectPrompt`：类型下拉 + `[username@]hostname[:port]`
  /// + `save_for_future_use` 复选框，按钮 ok / cancel。
  Future<void> _quickConnect() async {
    final result =
        await showDialog<({Connection connection, bool save, String? username})>(
      context: context,
      builder: (_) => const _QuickConnectDialog(),
    );
    if (result == null || !mounted) return;

    // `save_for_future_use` 勾选时把这条连接真正落库（原版行为）。
    if (result.save) {
      // Quick Connect 里 `[username@]hostname[:port]` 的用户名原本只挂在临时身份上
      // （transient、不入库）。勾选保存后这条连接会留在地址簿和首页「常用」里，
      // 用户名必须**跟着一起落库**：否则再次打开时 `ssh_service` 找不到带用户名的
      // 身份，密码框会退化成「请输入 @address 的密码」，并且拿空用户名去认证 ——
      // 密码输多少次都连不上。同名身份复用一份，避免反复快速连接堆出重复身份。
      // 只建一个"纯用户名"身份（不带密码、不带私钥），对应原版的临时身份。
      // 不能按用户名去复用已有身份：地址簿里可能已有用户名相同的**带私钥**身份
      // （实测 `keylab` / `lab-key` 的用户名都是 `juice`），复用会把新连接链到
      // 那把私钥上，认证方式都被改掉（连接列表里出现 `keylab: Used by 2
      // connections` 就是这么来的）。
      var identityIds = const <int>[];
      final quickUsername = result.username?.trim() ?? '';
      if (quickUsername.isNotEmpty) {
        final identityId = await _db.saveIdentity(
          Identity(nickname: quickUsername, username: quickUsername),
        );
        identityIds = <int>[identityId];
      }
      // saveConnection 返回自增主键，落库后重新读回带 id 的实体。
      final id = await _db.saveConnection(result.connection);
      if (identityIds.isNotEmpty) {
        await _db.setConnectionIdentities(id, identityIds);
      }
      final saved = await _db.connection(id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await _openConnection(
        saved ?? result.connection,
        quickConnectUsername: result.username,
      );
      return;
    }
    await _openConnection(
      result.connection,
      quickConnectUsername: result.username,
    );
  }

  // ------------------------------------------------------------------ 渲染 --

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(s('juicessh')),
        actions: [
          // 原版 ActionBar 的动作按钮实测 `[985,138][1080,264]`：
          // 宽 36.2dp、高 48dp（在 56dp 的条里上下居中）。Flutter 的
          // IconButton 默认最小 48dp，这里显式收紧约束才对齐。
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            iconSize: 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 48),
            // 原版这个按钮的无障碍描述 "More options" 来自 AppCompat 框架资源，
            // 不在 JuiceSSH 自己的 strings.xml 里，因此走字面量。
            tooltip: 'More options',
            onPressed: () => unawaited(_showHomeMenu()),
          ),
        ],
      ),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(JuiceStrings s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: '$_error');

    final cards = <Widget>[
      _HomeCard(
        title: s('quick_connect'),
        subtitle: s('connect_to_a_new_host'),
        icon: 0xF0E7, // icon_bolt
        onTap: _quickConnect,
      ),
      _HomeCard(
        title: s('frequently_used'),
        subtitle: s('quick_access_to_your_frequent_connections'),
        icon: 0xF005, // icon_star
        // 原版这一张卡**没有**点击监听，只有内嵌列表可点。
        content: _FrequentlyUsedContent(
          items: _frequent,
          nameOf: _connectionName,
          countLabel: (count) => switch (count) {
            1 => s('connected_once'),
            2 => s('connected_twice'),
            _ => s.format('connected_x_times', [count]),
          },
          onTap: _openConnection,
        ),
        contentHeight: _FrequentlyUsedContent.heightFor(_frequent.length) +
            _FrequentlyUsedContent.verticalPadding,
      ),
      _HomeCard(
        title: s('manage_connections'),
        subtitle: s('manage_your_connections_and_identities'),
        icon: 0xF0AC, // icon_globe
        onTap: _openAddressBook,
      ),
      _HomeCard(
        title: s('unlock_pro_version_capitals'),
        subtitle: s('click_to_find_out_more'),
        icon: 0xF09C, // icon_unlock
        onTap: () => _showNotInBuild(s('unlock_pro_version_capitals')),
      ),
      _HomeCard(
        title: s('menu_settings'),
        subtitle: s('personalise_your_sessions'),
        icon: 0xF085, // icon_cogs
        onTap: _openSettings,
      ),
      _HomeCard(
        title: s('help'),
        subtitle: s('view_our_faq'),
        icon: 0xF128, // icon_question
        onTap: _openFaq,
      ),
      _HomeCard(
        title: s('plugins'),
        subtitle: s('extend_juicessh_with_third_party_extensions'),
        icon: 0xF12E, // icon_puzzle_piece
        onTap: () => _showNotInBuild(s('plugins')),
      ),
      _HomeCard(
        title: s('bookclub'),
        subtitle: s('find_and_recommend_books'),
        icon: 0xF02D, // icon_book
        onTap: () => _showNotInBuild(s('bookclub')),
      ),
    ];

    return ListView.separated(
      // ListView 的 padding 与 dividerHeight 都是 16dp：
      // 16dp 外边距 + 卡片之间 16dp 间隙。
      // 原版写了 clipToPadding=false，Flutter 的 ListView 默认就不裁剪到
      // padding 内边（没有对应参数）。
      padding: const EdgeInsets.all(16),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, index) => cards[index],
    );
  }
}

enum _HomeMenuAction { faq, rate }

/// 卡片外框：`androidx.cardview.widget.CardView` + 2dp 圆角 + `card_item` 涟漪。
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.content,
    this.contentHeight,
  });

  final String title;
  final String subtitle;

  /// FontAwesome 码点（原版从 `@string/icon_*` 取，已逐个实测）。
  final int icon;

  final VoidCallback? onTap;

  /// `@id/itemContent` —— 目前只有「常用连接」卡片用到。
  final Widget? content;

  /// `content` 连同其上下 padding 的完整高度。
  ///
  /// 原版给 `itemContent` 设了 `layout_marginTop="-20dp"`，让它上移、压住标题区
  /// 底部的空白。Flutter 的 `RenderPadding` 断言 padding 必须非负，不能用负
  /// margin，所以这里用「占位高度 −20dp + `OverflowBox` 按原高绘制」等效实现。
  final double? contentHeight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Android 的 TextView 默认带 includeFontPadding，行高约为字号的 1.36 倍；
    // Flutter 默认约 1.17 倍。不显式指定的话卡片会比原版矮 5dp
    // （实测 65.1dp vs 70.1dp）。
    const lineHeight = 1.36;

    final header = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 两个 TextView 都写了 paddingRight=32dp，避免文字压到图标。
                Padding(
                  padding: const EdgeInsets.only(right: 32),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: lineHeight,
                      color: palette.textItemTitle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 32),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: lineHeight,
                      color: palette.textItemSubtitle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _FontAwesomeGlyph(codePoint: icon, size: 32, color: palette.secondaryText),
        ],
      ),
    );

    final Widget body;
    if (content == null) {
      body = header;
    } else {
      final height = contentHeight ?? 0;
      // MainActivity 把 itemContent 的 padding 改成 left0 / top16dp / right0 /
      // bottom8dp，并加了 -20dp 的 marginTop，让内嵌列表紧贴卡片标题。
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          SizedBox(
            height: height - 20,
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              maxHeight: height,
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: content,
              ),
            ),
          ),
        ],
      );
    }

    // 原版布局里 clickable=false，是靠 `r(listener)` 才变成可点；
    // 「常用连接」那张没有 listener，因此没有涟漪。
    return Material(
      color: palette.cardItemBackground,
      elevation: 2,
      borderRadius: BorderRadius.circular(2),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              splashColor: palette.cardItemPressed.withValues(alpha: 0.35),
              highlightColor: palette.cardItemPressed.withValues(alpha: 0.12),
              child: body,
            ),
    );
  }
}

/// 用原版自带的 FontAwesome 字体渲染图标（`assets/fonts/fontawesome-webfont.ttf`）。
class _FontAwesomeGlyph extends StatelessWidget {
  const _FontAwesomeGlyph({
    required this.codePoint,
    required this.size,
    required this.color,
  });

  final int codePoint;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      String.fromCharCode(codePoint),
      semanticsLabel: context.s('icon'),
      style: TextStyle(
        fontFamily: 'JuiceFontAwesome',
        fontSize: size,
        height: 1,
        color: color,
      ),
    );
  }
}

/// 「常用连接」卡片的内容区：一个有左右箭头的分页列表，空态是 Welcome。
///
/// 对应 `res/layout/indicated_page.xml` + `res/layout/frequently_used_page.xml`
/// + `res/layout/frequently_used_item.xml`。
class _FrequentlyUsedContent extends StatefulWidget {
  const _FrequentlyUsedContent({
    required this.items,
    required this.nameOf,
    required this.countLabel,
    required this.onTap,
  });

  final List<({Connection connection, int count})> items;
  final String Function(Connection) nameOf;
  final String Function(int) countLabel;
  final void Function(Connection) onTap;

  /// `kh0.h()`：没有数据、或超过一页时固定 3 行高；否则按实际行数收缩。
  static double heightFor(int itemCount) =>
      (itemCount == 0 || itemCount > _frequentPerPage)
          ? _frequentRowHeight * _frequentPerPage
          : _frequentRowHeight * itemCount;

  /// 上下各 16dp / 8dp 的内边距（`itemContent` 被改过的 padding）。
  static const double verticalPadding = 24;

  @override
  State<_FrequentlyUsedContent> createState() => _FrequentlyUsedContentState();
}

class _FrequentlyUsedContentState extends State<_FrequentlyUsedContent> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;
    final items = widget.items;

    // kh0.h()：没有数据、或超过一页时固定 3 行高；否则按实际行数收缩。
    final pageCount = items.isEmpty
        ? 1
        : (items.length / _frequentPerPage).ceil();
    final height = _FrequentlyUsedContent.heightFor(items.length);

    final Widget centre;
    if (items.isEmpty) {
      // frequently_used_page.xml 的 @id/empty：上下各占一半，0.5 权重。
      centre = Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                s('welcome'),
                style: TextStyle(
                  // 单行 TextView 的框高 = 1.172em 行高 + 0.19em 的
                  // includeFontPadding ≈ 1.362em。不写的话文字会在
                  // 「下对齐 + 居中对齐」的混用下比原版低约 4dp。
                  height: 1.362,
                  color: palette.textHeading,
                ),
              ),
            ),
          ),
          // 原版 `frequently_used_page.xml` 给副标题设了 `layout_marginTop="5dp"`
          // 且两个子视图都是 `layout_weight="1"`。Android 的 LinearLayout 会
          // **先扣掉 margin 再均分剩余空间**，而 Flutter 的 `Expanded` 是先均分、
          // 内边距算在权重内，两者差 6.6px。所以把 5dp 抽成独立的兄弟节点。
          const SizedBox(height: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 10),
              child: Align(
                alignment: Alignment.topCenter,
                child: Text(
                  s('youve_not_connected_yet'),
                  textAlign: TextAlign.center,
                  maxLines: 10,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textItemSubtitle,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      centre = PageView.builder(
        controller: _controller,
        itemCount: pageCount,
        onPageChanged: (value) => setState(() => _page = value),
        itemBuilder: (_, page) {
          final start = page * _frequentPerPage;
          final end = (start + _frequentPerPage).clamp(0, items.length);
          return ListView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: end - start,
            itemBuilder: (_, index) {
              final item = items[start + index];
              return _FrequentRow(
                name: widget.nameOf(item.connection),
                subtitle: widget.countLabel(item.count),
                onTap: () => widget.onTap(item.connection),
              );
            },
          );
        },
      );
    }

    final canPage = pageCount > 1;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          _PageArrow(
            icon: Icons.chevron_left,
            tooltip: s('back'),
            enabled: canPage && _page > 0,
            onTap: () => _controller.previousPage(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
          ),
          Expanded(child: centre),
          _PageArrow(
            icon: Icons.chevron_right,
            tooltip: s('forward'),
            enabled: canPage && _page < pageCount - 1,
            onTap: () => _controller.nextPage(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageArrow extends StatelessWidget {
  const _PageArrow({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 32,
      child: IconButton(
        icon: Icon(icon),
        iconSize: 20,
        tooltip: tooltip,
        onPressed: enabled ? onTap : null,
        color: palette.secondaryText,
        disabledColor: palette.secondaryText.withValues(alpha: 0.3),
      ),
    );
  }
}

/// `frequently_used_item.xml`：55dp 行，左侧 32dp 的固定 globe 图标 + 双行文字。
class _FrequentRow extends StatelessWidget {
  const _FrequentRow({
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _frequentRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标固定为 icon_globe（原版代码从不改它的文字），
            // paddingLeft 8dp / paddingRight 16dp / marginTop 10dp。
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 16, top: 10),
              child: _FontAwesomeGlyph(
                codePoint: 0xF0AC,
                size: 32,
                color: palette.secondaryText,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.36,
                        color: palette.textItemTitle,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.36,
                        color: palette.textItemSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `QuickConnectPrompt`：类型 + `[username@]hostname[:port]` + 保存复选框。
class _QuickConnectDialog extends StatefulWidget {
  const _QuickConnectDialog();

  @override
  State<_QuickConnectDialog> createState() => _QuickConnectDialogState();
}

class _QuickConnectDialogState extends State<_QuickConnectDialog> {
  final TextEditingController _host = TextEditingController();
  ConnectionType _type = ConnectionType.ssh;
  bool _save = true; // 原版 android:checked="true"

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  /// 解析 `[username@]hostname[:port]`。
  ///
  /// 用户名必须保留：`Connection` 表里确实没有用户名列（用户名挂在 Identity 上），
  /// 但原版会把 Quick Connect 里输入的用户名挂在一个**临时身份**上
  /// （`Connection.temporaryQuickConnectIdentity`，transient、不入库）带进会话。
  /// 丢掉它会导致用空用户名认证 —— 服务端一定拒绝，表现为会话永远停在
  /// 「正在进行主机密钥交换」。
  ({String address, int port, String? username})? _parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    String? username;
    final at = text.lastIndexOf('@');
    if (at >= 0) {
      final head = text.substring(0, at).trim();
      if (head.isNotEmpty) username = head;
      text = text.substring(at + 1);
    }
    if (text.isEmpty) return null;

    var port = switch (_type) {
      ConnectionType.telnet => 23,
      ConnectionType.local => 0,
      _ => 22,
    };
    final colon = text.lastIndexOf(':');
    if (colon > 0 && colon < text.length - 1) {
      final tail = text.substring(colon + 1);
      final parsed = int.tryParse(tail);
      if (parsed != null) {
        port = parsed;
        text = text.substring(0, colon);
      }
    }
    if (text.isEmpty) return null;
    return (address: text, port: port, username: username);
  }

  void _submit() {
    final parsed = _parse(_host.text);
    if (parsed == null) return;
    Navigator.of(context).pop((
      connection: Connection(
        nickname: '',
        address: parsed.address,
        port: parsed.port,
        type: _type,
      ),
      save: _save,
      username: parsed.username,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;
    return JuiceAlertDialog(
      title: s('quick_connect'),
      // 这一框用的是自定义内容（`customPanel`），实测没有 8dp 的标题分隔条：
      // `topPanel` 到 1009 就接 `customPanel [70,1009][1010,1410]`。
      showTitleDivider: false,
      contentPadding: EdgeInsets.zero,
      content: Padding(
        // 自定义内容的 16dp 内边距：实测第一行 `[112,1051]` = 面板左 70 + 42px ✔
        padding: const EdgeInsets.only(left: 16, top: 16, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原版 `customPanel` 里面的四段加起来正好 401px：
            // 40dp 行 + 10dp 间隙 + 45dp 输入框 + 10dp 间隙 + 32dp 复选框
            // （实测 105/26/118/26/84 px）。Flutter 的 DropdownButton /
            // TextField / CheckboxListTile 默认都比这高，必须逐行钉死。
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  // 原版这一行的标签 TextView 是 `padding=10dp`：
                  // 实测盒 `[112,1053][253,1156]`、字迹 `x139..224`
                  // （"Type:" 14sp 墨迹 88px + 两侧各 26px ≈ 10dp），
                  // Spinner 紧接着从 253 开始，中间没有额外间隙。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      s('type_colon'),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.362,
                        // 原版这一行的标签是次要文字色（实测 `.research/id_o2.png`
                        // 里 `Type:` 的字迹内部是 (199,199,199) = 70% 白叠在对话框
                        // 的 `#424242` 上），不是纯白。
                        color: palette.isDark
                            ? const Color(0xB3FFFFFF)
                            : palette.textForm,
                      ),
                    ),
                  ),
                  Expanded(
                    child: DropdownButton<ConnectionType>(
                      isDense: true,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      // 原版 Spinner 的箭头墨迹到 918 为止（容器右缘 968）。
                      // 实测：不缩到 950、缩 19dp 到 900，故取 12dp。
                      padding: const EdgeInsets.only(right: 12),
                      value: _type,
                      // 原版 Spinner 的文字比 14sp 大一档：`SSH` 的墨迹在
                      // `.research/id_o2.png` 里是 1089..1120 = 32px，按 cap 高
                      // 0.75em 反推是 16sp；克隆 14sp 只有 26px。同一行的 `Type:`
                      // 标签两边都是 35/34px（= 14sp），所以只改 Spinner。
                      style: TextStyle(fontSize: 16, color: palette.textForm),
                      onChanged: (value) {
                        if (value != null) setState(() => _type = value);
                      },
                      items: [
                        for (final type in ConnectionType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(s(_typeLabelKey(type))),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 字段框在原版是 `[125,1182][968,1300]`（节点实测），左边比同一对话框里的
            // 复选框行（`[112,1326][968,1410]`）多缩进 **13px ≈ 5dp**；克隆此前两行
            // 左边界都是 111，于是下划线比原版宽 16px（克隆 838px、原版 823px）。
            // 这里补上这 5dp，只动左边界（右边界原本吻合）。
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: JuiceFormTextField(
                controller: _host,
                height: 45,
                fontSize: 18,
                // 这一框在原版是**聚焦**态：下划线是 2dp 的 `accentBold`
                // （实测 y 1277..1281 = 5px，x 135..957，颜色 (213,186,49)），
                // 而编辑器里的输入框是未聚焦态的 1dp `#666666`。
                underlineColor: palette.accentBold,
                underlineHeight: 2,
                // 原版不自动聚焦：实测打开后 3 秒它的窗口仍是 `[28,849][1052,1616]`
                // 居中状态，说明没有弹出输入法（有 IME 时窗口会被顶起）。
                onSubmitted: (_) => _submit(),
                hintText: '[username@]hostname[:port]',
              ),
            ),
            const SizedBox(height: 10),
            JuiceCheckRow(
              label: s('save_for_future_use'),
              value: _save,
              onChanged: (value) => setState(() => _save = value),
              height: 32,
            ),
          ],
        ),
      ),
      actions: [
        JuiceDialogAction(
          label: s('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        JuiceDialogAction(label: s('ok'), onPressed: _submit),
      ],
    );
  }
}

String _typeLabelKey(ConnectionType type) => switch (type) {
  ConnectionType.ssh => 'ssh',
  ConnectionType.telnet => 'telnet',
  ConnectionType.mosh => 'mosh',
  ConnectionType.local => 'local_device',
};

/// `card_list.xml` 的 `@id/error_layout`。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FontAwesomeGlyph(
              codePoint: 0xF071, // icon_warning_sign
              size: 50,
              color: palette.accentBold,
            ),
            const SizedBox(height: 8),
            Text(
              s('an_error_has_occurred'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: palette.textItemTitle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s('please_try_again_later'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: palette.textItemSubtitle),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: palette.textItemSubtitle),
            ),
          ],
        ),
      ),
    );
  }
}
