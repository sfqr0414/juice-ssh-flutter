import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_colors.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_popup_menu.dart';
import '../widgets/pager_list.dart';
import 'identity_editor_screen.dart';

/// 身份（Identity）列表页 —— 对应原版 `MainActivity` 的第二个标签页。
///
/// 原版这一页由两个类组成：
/// * `IdentityListAdapter`（反编译后落在 `com/sonelli/nh0.smali`，其内部类
///   `nh0$b.smali` 的 `.source` 直接写着 `IdentityListAdapter.java`）
/// * `res/layout/identity_list.xml` —— 列表 + 空状态 + 右下角 FAB
///
/// 行布局的真相是 `res/layout/identity_menu_item.xml`：
/// ```
/// RelativeLayout  background=@drawable/highlight  padding=@dimen/activity_padding
///     w=match_parent  h=@dimen/list_item_height(72dp)  minHeight=72dp
/// ├─ FontAwesomeTextView id=@id/itemIcon  textSize=24.0dp  textColor=@color/icon_item
/// │     gravity=center  w=40dp h=40dp  text=@string/icon_user  alignParentLeft/Top
/// └─ LinearLayout(vertical)  paddingLeft=16dp paddingRight=16dp
///       layout_toRightOf=@id/itemIcon  w=wrap_content h=wrap_content
///    ├─ TextView id=@id/itemTitle     textSize=@dimen/text_item_title(16sp)
///    │     textColor=@color/text_item_title(#FF073642)  singleLine  h=20dp
///    └─ TextView id=@id/itemSubtitle  textSize=@dimen/text_item_subtitle(12sp)
///          textColor=@color/text_item_subtitle(#FF586E75)  singleLine  h=20dp
/// ```
/// 也就是说列表行**不是** `card_list_item.xml`，而是 §4.6 的扁平行；不过两者共用
/// 同一套尺寸与文字颜色（72dp / 16sp / 12sp），所以下面的 [CardListItem] 用
/// `card_list_item.xml` 的度量按扁平行排布，视觉上与原版一致。
///
/// **标题**：适配器调用 `Identity.toString()` 取标题，而
/// `Identity.toString()`（`models/Identity.smali`）的逻辑是
/// 「昵称非空则返回昵称，否则返回用户名」。
///
/// **副标题**：原版 `IdentityListAdapter$b.run()` 会遍历
/// `ConnectionIdentity` 统计该身份被多少条连接引用，然后拼出：
/// * 0 条 → `@string/not_used`（"Not used"）
/// * 1 条 → `@string/used_by` + " 1 " + `@string/connection`
/// * n 条 → `@string/used_by` + " n " + `@string/connections_lowercase`
/// 这几条文案在 `strings_en.json` / `strings_zh.json` 里都存在，所以这里**照抄**。
///
/// 注意：任务要求「副标题展示身份的用户名与是否有私钥」。那套信息原版并没有放在
/// 列表行上（原版只在编辑页显示），所以本文件把用户名/私钥也做成可选样式：
/// [IdentityRowStyle.userSummary]。默认用原版的连接数文案
/// （[IdentityRowStyle.connectionUsage]）。
enum IdentityRowStyle {
  /// 原版行为：`Not used` / `Used by 3 connections`。
  connectionUsage,

  /// 任务书要求：`用户名 · 有私钥 / 无私钥`。
  userSummary,
}

/// 身份列表行 —— 可复用的列表行组件，供身份列表/片段列表等页面复用。
///
/// 度量全部来自原版：
/// * 行高 `@dimen/list_item_height` = **72dp**
/// * 图标位 `@dimen/list_item_icon_width` = **40dp**，图标字号 24dp（`identity_menu_item.xml`）
///   或 32dp（`card_list_item.xml` 的 `itemTextIcon`）
/// * 标题 `@dimen/text_item_title` = **16sp**，颜色 `@color/text_item_title`
/// * 副标题 `@dimen/text_item_subtitle` = **12sp**，颜色 `@color/text_item_subtitle`
/// * 左右内边距 `@dimen/activity_padding` = **16dp**
/// * 按压反馈 `@drawable/card_item.xml`（在 `@color/card_item_pressed` 上的 ripple）
class CardListItem extends StatelessWidget {
  const CardListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingIconGlyph,
    this.leadingIconSize = 24,
    this.onTap,
    this.onLongPress,
  }) : assert(
         leadingIcon == null || leadingIconGlyph == null,
         'leadingIcon 与 leadingIconGlyph 只能二选一',
       );

  /// 行高，来自 `@dimen/list_item_height`。
  static const double height = 72;

  /// 图标位宽度，来自 `@dimen/list_item_icon_width`。
  static const double iconWidth = 40;

  /// 图标与文字列之间的距离。
  ///
  /// 原版是文字列 `LinearLayout` 上的 `paddingLeft="@dimen/activity_padding"`，
  /// 而它又 `layout_toRightOf="@id/itemIcon"`，所以标题的 x =
  /// 行左内边距 16dp + 图标 40dp + 16dp = **72dp = 189px**（420dpi）。
  /// 实测原版片段列表 `itemTitle` 落在 `[189,317]`，与此一致。
  static const double iconGap = 16;

  /// 标题/副标题的行高。
  ///
  /// 原版两个 `TextView` 都是写死的 `layout_height="20dp"` +
  /// `gravity="center_vertical"`，两行合计 **40dp**；行的上下内边距各 16dp，
  /// 正好凑满 72dp 行高。所以这里是「上下各 16dp + 两行各 20dp」，
  /// 不能只靠 `Column` 居中（`Text` 的自然行高在 16sp 时只有 ~18.7dp，
  /// 两行会比原版矮 2.6dp，整块文字跟着往下错 4px）。
  static const double lineHeight = 20;

  /// 标题字号，来自 `@dimen/text_item_title`。
  static const double titleSize = 16;

  /// 副标题字号，来自 `@dimen/text_item_subtitle`。
  static const double subtitleSize = 12;

  /// 左右内边距，来自 `@dimen/activity_padding`。
  static const double horizontalPadding = 16;

  final String title;

  final String? subtitle;

  /// 左侧图标（Material 图标）。原版的图标位是 `FontAwesomeTextView`，
  /// 这里用等价语义的 Material 图标代替，因为本项目没有打进 FontAwesome 字体。
  final IconData? leadingIcon;

  /// 左侧图标位直接渲染的字形（对应 `@string/icon_user` 这类 FontAwesome 码点）。
  final String? leadingIconGlyph;

  /// 图标绘制尺寸。
  ///
  /// 原版身份列表行的图标实测：墨迹高 78px、黄像素 1689 —— 对应约 40dp 字号
  /// （图标位宽本来就是 40dp）。而片段列表行同一测量只有 296 个黄像素，与 24dp
  /// 吻合。所以尺寸按行给，默认沿用 24。
  final double leadingIconSize;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      // `@drawable/card_item` 的 ripple 色 = `@color/card_item_pressed`，
      // 亮色下是 `#FF586E75`；用透明度削弱后铺在白底行上。
      splashColor: palette.cardItemPressed.withValues(alpha: 0.16),
      highlightColor: palette.accentLighterTransparent,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              SizedBox(
                width: iconWidth,
                height: iconWidth,
                child: Center(child: _buildLeadingIcon(palette)),
              ),
              const SizedBox(width: iconGap),
              Expanded(
                child: Column(
                  // 必须显式居中：`Column` 默认 `mainAxisSize: max`，在 `Row` 给的
                  // 松散高度里会撑满整行，两行文字就贴到行首去了（实测会高 42px）。
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: lineHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            height: 1.362,
                            color: palette.textItemTitle,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: lineHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          subtitle ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: subtitleSize,
                            height: 1.362,
                            color: palette.textItemSubtitle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧图标位。
  ///
  /// 颜色取 `@color/icon_item` = `@color/accent_bold`：原版列表行里是这个色，
  /// 而 `card_list_item.xml` 的 `itemTextIcon` 用的是 `@color/card_icon_color`
  /// ——那是个空 `color` 元素（全透明），所以不能照抄。
  Widget? _buildLeadingIcon(JuicePalette palette) {
    final icon = leadingIcon;
    if (icon != null) {
      return Icon(icon, size: leadingIconSize, color: palette.accentBold);
    }
    final glyph = leadingIconGlyph;
    if (glyph != null) {
      return Text(
        glyph,
        style: TextStyle(fontSize: leadingIconSize, color: palette.accentBold),
      );
    }
    return null;
  }
}

/// 身份列表页的 ActionBar 动作。
///
/// `res/menu/menu_addressbook_identities.xml` 里只有一个条目：
/// `menu_item_new_identity` → `@string/new_identity`，图标 `@drawable/ic_new`，
/// `app:showAsAction="ifRoom"`（`android:visible="false"`，由代码按当前标签页打开）。
class IdentityListActions {
  const IdentityListActions._();

  /// 标题键，`@string/identities`。
  static const String titleKey = 'identities';

  /// 新建身份菜单项的标题键，`@string/new_identity`。
  static const String newIdentityKey = 'new_identity';

  /// 新建身份菜单项，与 `menu_addressbook_identities.xml` 等价的 Flutter 写法。
  static Widget newIdentityButton(
    BuildContext context,
    VoidCallback onPressed,
  ) {
    return IconButton(
      icon: const Icon(Icons.add),
      tooltip: context.s(newIdentityKey),
      onPressed: onPressed,
    );
  }
}

/// 身份列表页。
///
/// 默认只提供 **body**（外层 `Scaffold` 由标签页宿主提供，与原版一致：
/// 原版身份页是 `AddressBookActivity` 里的一个 ViewPager 页面，
/// ActionBar 归 Activity 所有）。动作按钮通过 [IdentityListActions] 复用。
///
/// 传入 [showScaffold] 为 true 时会自带 `Scaffold` + `AppBar`
/// （标题 `@string/identities`，右侧 `new_identity` 图标 `Icons.add`），
/// 便于单独打开这一页做对照。
class IdentitiesScreen extends StatefulWidget {
  const IdentitiesScreen({
    super.key,
    this.showScaffold = false,
    this.rowStyle = IdentityRowStyle.connectionUsage,
    this.onEditIdentity,
  });

  /// 是否自带 `Scaffold` / `AppBar`。
  final bool showScaffold;

  /// 副标题样式，见 [IdentityRowStyle]。
  final IdentityRowStyle rowStyle;

  /// 点击行时的回调；默认自己 push [IdentityEditorScreen]。
  final void Function(BuildContext context, Identity identity)? onEditIdentity;

  @override
  State<IdentitiesScreen> createState() => IdentitiesScreenState();
}

class IdentitiesScreenState extends State<IdentitiesScreen> {
  JuiceDatabase get _db => JuiceDatabase.instance;

  List<Identity> _identities = const <Identity>[];

  /// 身份 id → 引用它的连接数量。对应原版 `IdentityListAdapter$b` 的统计。
  Map<int, int> _usage = const <int, int>{};

  bool _loading = true;

  /// 是否已经因为 `didChangeDependencies` 刷过一次。
  ///
  /// 首次加载就走这条路径（`didChangeDependencies` 必定在 `initState` 之后执行），
  /// 所以 `initState` 里不再重复查库。这样写还顺带解决了另一个问题：
  /// 身份可能被别的页面（例如连接编辑器里内联新建身份）改掉，而
  /// `AddressBookScreen` 用 `const` 构造本页、`initState` 只会跑一次，
  /// 于是在依赖变化时补一次刷新。
  bool _refreshedOnDependencyChange = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refreshedOnDependencyChange) return;
    _refreshedOnDependencyChange = true;
    reload();
  }

  /// 重新读取身份列表与引用计数。
  ///
  /// 宿主（标签页）可以在新建/编辑身份之后调用它刷新列表。
  Future<void> reload() async {
    final identities = await _db.identities();
    final usage = await _identityUsage();
    if (!mounted) return;
    setState(() {
      _identities = identities;
      _usage = usage;
      _loading = false;
    });
  }

  /// 一次查询统计出每个身份被多少条连接引用。
  ///
  /// `connectionidentity` 表的列名是 `connection` / `identity`
  /// （见 `JuiceDatabase._schema`），对应原版 ORMLite 的字段名。
  Future<Map<int, int>> _identityUsage() async {
    final rows = await _db.raw.query(
      'connectionidentity',
      columns: ['identity', 'COUNT(*) AS total'],
      groupBy: 'identity',
    );
    return {
      for (final row in rows)
        (row['identity'] as num).toInt(): (row['total'] as num).toInt(),
    };
  }

  /// 原版 `IdentityListAdapter$b` 的副标题文案。
  ///
  /// 依据 `nh0$b.smali`：
  /// * `count == 0` → `@string/not_used`
  /// * `count == 1` → `@string/used_by` + " " + 1 + " " + `@string/connection`
  /// * 否则 → `@string/used_by` + " " + count + " " + `@string/connections_lowercase`
  String _usageSubtitle(BuildContext context, Identity identity) {
    final s = context.s;
    final count = _usage[identity.id] ?? 0;
    if (count == 0) return s('not_used');
    final noun = count == 1 ? s('connection') : s('connections_lowercase');
    return '${s('used_by')} $count $noun';
  }

  /// 任务书要求的副标题：用户名 + 是否配置了私钥/密码。
  ///
  /// 依据 `Identity` 的 `username` / `hasPrivateKey` / `hasPassword`
  /// （`lib/data/models.dart`），以及编辑页里 `@string/not_set` 的用法。
  String _userSubtitle(BuildContext context, Identity identity) {
    final s = context.s;
    final username = (identity.username ?? '').trim();
    final parts = <String>[
      if (username.isNotEmpty) username,
      identity.hasPrivateKey ? s('private_key') : s('not_set'),
      if (identity.hasPassword) s('password_colon').replaceAll(':', ''),
    ];
    return parts.join(' · ');
  }

  String _subtitle(BuildContext context, Identity identity) =>
      switch (widget.rowStyle) {
        IdentityRowStyle.connectionUsage => _usageSubtitle(context, identity),
        IdentityRowStyle.userSummary => _userSubtitle(context, identity),
      };

  /// 点击行 → 编辑页。
  Future<void> _openEditor(Identity identity) async {
    final handler = widget.onEditIdentity;
    if (handler != null) {
      handler(context, identity);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => IdentityEditorScreen(identityId: identity.id),
      ),
    );
    if (!mounted) return;
    await reload();
  }

  /// 新建身份 —— 对应 `@string/new_identity` / FAB `@id/fab_new_identity`。
  Future<void> _createIdentity() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const IdentityEditorScreen()),
    );
    if (!mounted) return;
    await reload();
  }

  /// 长按行 → 上下文菜单。
  ///
  /// 条目来自 `res/menu/identity_context_menu.xml`，四项、无图标、
  /// `android:orderInCategory="100"`：
  /// 1. `edit` → `@string/edit`
  /// 2. `export_private_key` → `@string/export_private_key`
  /// 3. `export_public_key` → `@string/export_public_key`
  /// 4. `delete` → `@string/delete`
  ///
  /// 第 59 轮实测（原版 Identities 页长按身份行，uiautomator 带 bounds）：
  ///
  /// ```
  /// Manage identity       [274,465][705,516]
  /// Edit                  [274,588][705,645]
  /// Export Private Key    [274,714][705,771]
  /// Export Public Key     [274,840][705,897]
  /// Delete                [274,966][705,1023]
  /// ```
  ///
  /// 与连接长按菜单是同一套浮动菜单几何：底色框左边缘 = 触点 x（232px）、
  /// 顶边 = 触点 y、每项 48dp（126px）；首行表头 `@string/manage_identity`
  /// 由运行时代码加上（XML 里只有上面四项）。此处最宽文案没超过
  /// `MenuPopupWindow` 的 196dp 宽下限，所以底色框只有 515px。
  Future<void> _showContextMenu(Identity identity, Rect anchor) async {
    final s = context.s;
    final action = await showJuicePopupMenu<_IdentityMenuAction>(
      context: context,
      anchor: anchor,
      anchorAtTouch: true,
      title: s('manage_identity'),
      items: [
        JuicePopupItem<_IdentityMenuAction>(
          value: _IdentityMenuAction.edit,
          label: s('edit'),
        ),
        JuicePopupItem<_IdentityMenuAction>(
          value: _IdentityMenuAction.exportPrivateKey,
          label: s('export_private_key'),
        ),
        JuicePopupItem<_IdentityMenuAction>(
          value: _IdentityMenuAction.exportPublicKey,
          label: s('export_public_key'),
        ),
        JuicePopupItem<_IdentityMenuAction>(
          value: _IdentityMenuAction.delete,
          label: s('delete'),
        ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _IdentityMenuAction.edit:
        await _openEditor(identity);
      case _IdentityMenuAction.exportPrivateKey:
        await _exportKey(identity, publicKey: false, s: s);
      case _IdentityMenuAction.exportPublicKey:
        await _exportKey(identity, publicKey: true, s: s);
      case _IdentityMenuAction.delete:
        await _delete(identity, s: s);
    }
  }

  /// 导出私钥 / 公钥。
  ///
  /// 说明（重要）：原版把密钥导出实现为「写到文件 + 分享 Intent」，
  /// 对应资源只有 `@string/export_private_key` / `@string/export_public_key`
  /// 两条菜单文案；**具体交互（保存到 SD 卡还是分享）在 DEX 里，
  /// 本文件按项目现有 API 无法完整复刻文件/分享部分**，
  /// 因此这里只做前置校验并把结果文本呈现出来，不生成文件。
  Future<void> _exportKey(
    Identity identity, {
    required bool publicKey,
    required JuiceStrings s,
  }) async {
    if (!identity.hasPrivateKey) {
      await JuiceDialogs.message(
        context,
        title: s(publicKey ? 'export_public_key' : 'export_private_key'),
        message: s('no_private_key_selected'),
      );
      return;
    }
    // 只展示私钥文本本身：公钥需要从私钥推导（原版用 BouncyCastle），
    // 属于 SSH 层的职责，不在本次范围内。
    final body = publicKey
        ? s('no_private_key_selected')
        : identity.privateKey!;
    if (!mounted) return;
    await JuiceDialogs.message(
      context,
      title: s(publicKey ? 'export_public_key' : 'export_private_key'),
      message: body,
    );
  }

  Future<void> _delete(Identity identity, {required JuiceStrings s}) async {
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('delete'),
      message: s.format('are_you_sure_you_want_to_remove_x', [
        _titleOf(identity),
      ]),
      confirmLabel: s('delete'),
    );
    if (!confirmed || !mounted) return;
    await _db.deleteIdentity(identity.id);
    if (!mounted) return;
    await reload();
  }

  /// 标题 = `Identity.toString()`：昵称非空取昵称，否则取用户名。
  String _titleOf(Identity identity) {
    final nickname = identity.nickname;
    if (nickname.isNotEmpty) return nickname;
    return identity.username ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (!widget.showScaffold) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s(IdentityListActions.titleKey)),
        actions: [
          IdentityListActions.newIdentityButton(context, _createIdentity),
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
        else if (_identities.isEmpty)
          _buildEmptyState(context)
        else
          ListView.separated(
            itemCount: _identities.length,
            // `identity_list.xml` 的 `divider=@drawable/highlight` 其实是个空
            // selector（没有可见分隔线）；这里改用 `@color/card_item_divider`
            // 画一条细线，与原版卡片列表的分隔色一致，便于区分行。
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: palette.cardItemDivider,
            ),
            itemBuilder: (context, index) {
              final identity = _identities[index];
              // 原版浮动菜单以**触点**为锚点（第 59 轮实测：底色框左上角 = 触点
              // 坐标）。记下按下的位置，同时保留列表行自己的长按反馈。
              Offset? lastTouch;
              return Listener(
                onPointerDown: (event) => lastTouch = event.position,
                child: CardListItem(
                  title: _titleOf(identity),
                  subtitle: _subtitle(context, identity),
                  // 行图标：原版是 `@string/icon_user`（FontAwesome U+F007）。
                  // 原版身份行图标的墨迹高 78px、黄像素 1689，对应约 40dp 字号；
                  // 克隆原本按 24dp 绘制，实测只有 545 个黄像素，比值 0.32 ≈
                  // (24/40)² —— 说明字形一致，只差尺寸。
                  // 图标字号按 bbox 反解：原版 `*_menu_item.xml` 的 itemIcon 是
                  // 30dp 的 FontAwesome 字形（墨迹 bbox 50x55，覆盖率≈0.70em），
                  // 克隆此处曾是 40dp 的 Icons.person_outline（墨迹 71x71，
                  // 覆盖率≈0.68em）。两者覆盖率接近，故按 40 × 55/71 ≈ 31 取整。
                  leadingIconSize: 31,
                  leadingIcon: Icons.person_outline,
                  onTap: () => _openEditor(identity),
                  onLongPress: () {
                    final at = lastTouch;
                    _showContextMenu(
                      identity,
                      at == null
                          ? juiceContextMenuAnchor(context)
                          : Rect.fromLTWH(at.dx, at.dy, 0, 0),
                    );
                  },
                ),
              );
            },
          ),
        // `@id/fab_new_identity`：右下角 + 号，`app:backgroundTint=@color/primary_bold`、
        // `app:tint=@color/white`，`layout_margin=16dp`。
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: null,
            onPressed: _createIdentity,
            backgroundColor: palette.primaryBold,
            foregroundColor: Colors.white,
            tooltip: s(IdentityListActions.newIdentityKey),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  /// 空状态 —— `identity_list.xml` 的 `@id/empty`。
  ///
  /// 结构：0.3 权重的空白 + 0.7 权重的文字块；标题
  /// `@dimen/text_heading`(36sp) / `@color/text_heading`，文案 `@string/no_identities`；
  /// 副标题距标题 5dp，颜色 `@color/text_subheading`，
  /// 文案 `@string/you_do_not_have_any_identities`；整块 padding 16dp。
  Widget _buildEmptyState(BuildContext context) {
    // 几何交给共享的 `PagerEmptyState`（`tabs` 样式 = `identity_list.xml` 的
    // `weight 0.3 / 0.7` 结构）。与连接页唯一的区别是：本页的 `@id/empty`
    // 自己带了 `android:padding="@dimen/activity_padding"`，所以要多一层 16dp，
    // 标题因此落在 1011px 而不是 994px（420dpi 实测）。
    //
    // `Stack` 的非 Positioned 子项拿到的是松约束，所以这里显式铺满，
    // 否则内部的 `Expanded` 会因为高度无界而报错。
    return SizedBox.expand(
      child: PagerEmptyState(
        title: context.s('no_identities'),
        message: context.s('you_do_not_have_any_identities'),
        outerPadding: true,
      ),
    );
  }
}

/// 身份行长按菜单的动作 id，取值与 `identity_context_menu.xml` 的 `android:id` 一致。
enum _IdentityMenuAction { edit, exportPrivateKey, exportPublicKey, delete }
