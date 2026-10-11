import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_theme.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_alert_dialog.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/juice_popup_menu.dart';
import '../widgets/pager_list.dart';
import 'identities_screen.dart';

/// 代码片段（Snippet）管理页 —— 对应原版 `activities.ManageSnippetsActivity`。
///
/// 依据：
/// * `AndroidManifest.xml`：`ManageSnippetsActivity` 的 `android:label`
///   是 `@string/snippets`，`parentActivityName` 是 `SettingsActivity`。
/// * `res/menu/menu_manage_snippets.xml`：只有一项
///   `menu_item_new_snippet` → `@string/new_snippet`，图标 `@drawable/ic_new`，
///   `app:showAsAction="ifRoom"`。
/// * `res/menu/snippet_context_menu.xml`：两项，无图标、
///   `android:orderInCategory="100"`：
///   1. `edit` → `@string/edit`
///   2. `delete` → `@string/delete`
/// * 新增/编辑用 `res/layout/snippet_dialog.xml` 的结构：
///   ```
///   LinearLayout(vertical)
///       paddingLeft/Right = @dimen/dialog_padding_left/right (16dp)
///       paddingTop        = @dimen/dialog_padding_top (16dp)
///       paddingBottom     = @dimen/dialog_padding_bottom (0dp)
///    ├─ EditText id=@id/nickname        hint=@string/nickname
///    └─ EditText id=@id/snippet_content gravity=top  minLines=7
///          hint=@string/example_snippet
///          inputType=textMultiLine|textNoSuggestions
///   ```
///   注意第一个输入框的 hint 是 `@string/nickname`（"Nickname"/"昵称"），
///   但它在对话框里代表**片段名称**（写库时进 `snippet.name`）。
///
/// 列表行复用 [CardListItem]：72dp 行高、16sp 标题、12sp 副标题，
/// 与原版列表行同一套 `dimen`。
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  JuiceDatabase get _db => JuiceDatabase.instance;

  List<Snippet> _snippets = const <Snippet>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final snippets = await _db.snippets();
    if (!mounted) return;
    setState(() {
      _snippets = snippets;
      _loading = false;
    });
  }

  // ------------------------------------------------------------ 新增 / 编辑 --

  /// 新增片段 —— 对应 `@id/menu_item_new_snippet` / `@string/new_snippet`。
  Future<void> _create() async {
    final result = await _snippetDialog(title: context.s('new_snippet'));
    if (!mounted || result == null) return;

    final name = result.name.trim();
    if (name.isEmpty) {
      // 原版对空片段的提示是 `@string/cant_save_an_empty_snippet`。
      _warn(context.s('cant_save_an_empty_snippet'));
      return;
    }

    await _db.saveSnippet(Snippet(name: name, content: result.content));
    if (!mounted) return;
    await _reload();
  }

  /// 编辑片段 —— 对应上下文菜单的 `edit`（`@string/edit`）。
  Future<void> _edit(Snippet snippet) async {
    final result = await _snippetDialog(
      title: context.s('edit_snippet'),
      initialName: snippet.name,
      initialContent: snippet.content,
    );
    if (!mounted || result == null) return;

    final name = result.name.trim();
    if (name.isEmpty) {
      _warn(context.s('cant_save_an_empty_snippet'));
      return;
    }

    await _db.saveSnippet(
      snippet.copyWith(name: name, content: result.content),
    );
    if (!mounted) return;
    await _reload();
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// `snippet_dialog.xml` 的对话框。
  ///
  /// 返回 `(name, content)`；取消返回 null。
  /// 名称对应 `@id/nickname`，内容对应 `@id/snippet_content`。
  Future<({String name, String content})?> _snippetDialog({
    required String title,
    String initialName = '',
    String initialContent = '',
  }) {
    final s = context.s;
    final nameController = TextEditingController(text: initialName);
    final contentController = TextEditingController(text: initialContent);

    return showDialog<({String name, String content})>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => JuiceAlertDialog(
        title: title,
        // 自定义内容（`customPanel`），所以没有标题分隔条。
        showTitleDivider: false,
        // 内边距对应 `dialog_padding_left/top/right/bottom` = 16/16/16/0。
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `@id/nickname`，hint `@string/nickname`。
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(hintText: s('nickname')),
              ),
              // `@id/snippet_content`：`gravity=top`、`minLines=7`、
              // `inputType=textMultiLine|textNoSuggestions`。
              TextField(
                controller: contentController,
                minLines: 7,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(hintText: s('example_snippet')),
              ),
            ],
          ),
        ),
        actions: [
          JuiceDialogAction(
            label: s('cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          JuiceDialogAction(
            label: s('ok'),
            onPressed: () => Navigator.of(context).pop((
              name: nameController.text,
              content: contentController.text,
            )),
          ),
        ],
      ),
    ).whenComplete(() {
      nameController.dispose();
      contentController.dispose();
    });
  }

  // ------------------------------------------------------------------ 删除 --

  /// 删除片段 —— 对应上下文菜单的 `delete`（`@string/delete`），
  /// 删除前用 [JuiceDialogs.confirm] 确认。
  Future<void> _delete(Snippet snippet) async {
    final s = context.s;
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('delete'),
      message: s.format('are_you_sure_you_want_to_remove_x', [snippet.name]),
      confirmLabel: s('delete'),
    );
    if (!confirmed || !mounted) return;
    await _db.deleteSnippet(snippet.id);
    if (!mounted) return;
    await _reload();
  }

  // ------------------------------------------------------------ 上下文菜单 --

  /// 长按行 → 上下文菜单，条目与 `snippet_context_menu.xml` 一一对应。
  ///
  /// 第 59 轮实测（原版 Snippets 页长按 `Restart nginx`，触点 313,343）：
  ///
  /// ```
  /// Snippet   [355,380][786,431]
  /// Edit      [355,503][786,560]
  /// Delete    [355,657][786,686]
  /// ```
  ///
  /// 与连接/身份长按菜单是同一套浮动菜单几何：底色框左边缘 = 触点 x（313px）、
  /// 顶边 = 触点 y、每项 48dp（126px）。首行表头是 `@string/snippet`（"Snippet"，
  /// **不是** `@string/snippets`），由运行时代码加上（XML 里只有 edit/delete）。
  /// 此处最宽文案没超过 `MenuPopupWindow` 的 196dp 宽下限，所以底色框只有 515px。
  Future<void> _showContextMenu(Snippet snippet, Rect anchor) async {
    final s = context.s;
    final action = await showJuicePopupMenu<_SnippetMenuAction>(
      context: context,
      anchor: anchor,
      anchorAtTouch: true,
      title: s('snippet'),
      items: [
        JuicePopupItem<_SnippetMenuAction>(
          value: _SnippetMenuAction.edit,
          label: s('edit'),
        ),
        JuicePopupItem<_SnippetMenuAction>(
          value: _SnippetMenuAction.delete,
          label: s('delete'),
        ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _SnippetMenuAction.edit:
        await _edit(snippet);
      case _SnippetMenuAction.delete:
        await _delete(snippet);
    }
  }

  // ------------------------------------------------------------------ 视图 --

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        title: Text(s('snippets')),
        actions: [
          // `menu_manage_snippets.xml`：`menu_item_new_snippet` → `@string/new_snippet`，
          // 图标 `@drawable/ic_new`（白色加号）→ Material 的 `Icons.add`。
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: s('new_snippet'),
            onPressed: _create,
          ),
        ],
      ),
      // 原版这个页面除了 ActionBar 右上角的 `@drawable/ic_new`，底部还有一个黄色 FAB：
      // 实测截图 1820..2200 带内有 (216,192,65)x5070 —— 与通讯录那个 FAB 的像素数完全
      // 相同，即同一套 FAB 样式。第 65 轮补上（此前只有右上角动作，底部是空的）。
      floatingActionButton: FloatingActionButton(
        // 取色必须与 `port_forwards_screen` / `identities_screen` / `groups_screen`
        // 的 FAB 保持一致：`palette.primaryBold` + 白色图标。实测原版片段页 FAB 是
        // (216,192,65) = `#D8C041`（暗色的 `primaryBold`），而主题里的
        // `floatingActionButtonTheme` 给的是 `primaryDarker`（#D5BA31 =
        // (213,186,49)），照主题默认取色会差 3/255。
        backgroundColor: context.palette.primaryBold,
        foregroundColor: Colors.white,
        onPressed: _create,
        tooltip: s('new_snippet'),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _snippets.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                  itemCount: _snippets.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 1,
                    color: context.palette.cardItemDivider,
                  ),
                  itemBuilder: (context, index) {
                    final snippet = _snippets[index];
                    // 原版浮动菜单以**触点**为锚点（第 59 轮实测：底色框左上角
                    // = 触点坐标）。记下按下的位置，同时保留行自身的长按反馈。
                    Offset? lastTouch;
                    return Listener(
                      onPointerDown: (event) => lastTouch = event.position,
                      child: CardListItem(
                        title: snippet.name,
                        subtitle: snippet.content,
                        leadingIcon: Icons.code,
                        onTap: () => _edit(snippet),
                        onLongPress: () {
                          final at = lastTouch;
                          _showContextMenu(
                            snippet,
                            at == null
                                ? juiceContextMenuAnchor(context)
                                : Rect.fromLTWH(at.dx, at.dy, 0, 0),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }

  /// 副标题显示片段内容。
  ///
  /// 这一条是**实测确认**的，不再是推断：把原版解开 Pro 门禁后新建了一条
  /// 「Restart nginx」片段，`uiautomator` 层级里
  /// `@id/itemSubtitle` 的 `text` 就是片段正文
  /// （`sudo systemctl restart nginx`），`@id/itemTitle` 是名称。
  /// 两个 `TextView` 都是 `layout_height="20dp"` + `singleLine` + `ellipsize=end`，
  /// 所以正文长了会被截断，不再另外拼文案。

  /// 空状态：标题 `@string/no_snippets`，说明 `@string/you_do_not_have_any_snippets`。
  ///
  /// 度量沿用 `identity_list.xml` 的 `@id/empty`
  /// （`@dimen/text_heading` 36sp + `@color/text_subheading`），
  /// 也是全应用统一的空状态写法（`pager_list.xml` / `simple_list_activity.xml` 同构）。
  Widget _buildEmptyState(BuildContext context) {
    // 片段页是 `ManageSnippetsActivity`，基类 `xh0` 用 `setContentView` 加载的是
    // **`pager_list.xml`**（已用资源 id `0x7f0c0091` 在 smali 里核对过），
    // 那套空态是「整块居中 + 标题 `layout_marginTop="-40dp"` + 与正文间距 8dp」，
    // 和通讯录三页的 `weight 0.3/0.7` **不是同一个布局**，
    // 所以要显式指定 `centered` 样式。
    return SizedBox.expand(
      child: PagerEmptyState(
        style: PagerEmptyStyle.centered,
        title: context.s('no_snippets'),
        message: context.s('you_do_not_have_any_snippets'),
      ),
    );
  }
}

/// 片段行长按菜单的动作 id，取值与 `snippet_context_menu.xml` 的 `android:id` 一致。
enum _SnippetMenuAction { edit, delete }
