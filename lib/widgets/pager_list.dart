import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../app/juice_colors.dart';
import '../app/juice_theme.dart';

/// `res/layout/address_list.xml` 的 Flutter 复刻（通讯录「Connections」页）。
///
/// 原版结构（`RelativeLayout`）：
/// * `@id/list_container`
///   * `@id/expandable_list` —— `ExpandableListView`（连接分组 + 连接），
///     `divider="@drawable/highlight"`、`dividerHeight="0.5dp"`。注意
///     `@drawable/highlight` 是一个**空的 `<selector/>`**，也就是说分隔线占
///     0.5dp 却什么都不画，视觉上就是一条 0.5dp 的透明间隙；
///   * `@id/empty` —— 空状态，见 [PagerEmptyState] 的 `tabs` 样式；
///   * `@id/fab_new_connection` —— 右下角 `FloatingActionButton`，
///     `layout_margin="16.0dp"`、`backgroundTint="@color/primary_bold"`（品牌黄）、
///     `tint="@color/white"`、`src="@drawable/ic_new"`（一个加号）。
///
/// 另外两页用的是各自的布局，几何略有差别，所以空状态要么显式传
/// `emptyOuterPadding: true`（身份页），要么另用 [PagerEmptyStyle.centered]
/// （片段等独立列表页）：
///
/// | 页面 | 布局 | 空态样式 | 外层内边距 |
/// |---|---|---|---|
/// | Connections | `address_list.xml` | `tabs` | 无 |
/// | Identities | `identity_list.xml` | `tabs` | **有**（`@id/empty` 自带 `padding`） |
/// | Port Forwards | `port_forwards.xml` | `tabs` | 无 |
/// | Snippets 等 | `pager_list.xml` | `centered` | 无 |
class PagerList extends StatelessWidget {
  const PagerList({
    super.key,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.itemCount,
    required this.itemBuilder,
    required this.onNew,
    this.emptyOuterPadding = false,
    this.newTooltip,
  });

  /// 空状态标题文案（例如 `no_connections`）。
  final String emptyTitle;

  /// 空状态正文文案（例如 `you_do_not_have_any_connections`）。
  final String emptyMessage;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// 点黄色 FAB 的动作：新建当前标签页对应的对象。
  final VoidCallback onNew;

  /// 空状态是否再套一层 16dp 内边距。
  ///
  /// 只有 `identity_list.xml` 的 `@id/empty` 自己带了
  /// `android:padding="@dimen/activity_padding"`，另外两页没有。
  /// 这一层会让标题从 994px 下移到 1011px（实测值）。
  final bool emptyOuterPadding;

  /// FAB 的无障碍描述文案键。
  ///
  /// 原版三个标签页的 FAB（`fab_new_connection` / `fab_new_identity` /
  /// `fab_new_portforward`）都**没有**内容描述，uiautomator 抓到的
  /// `content-desc` 是空的。这里按各自语义补上，纯无障碍、不影响像素。
  final String? newTooltip;

  /// 空状态标题字号，来自 `@dimen/text_heading`。
  static const double emptyTitleSize = 36;

  /// `activity_padding`，空状态的内边距。
  static const double padding = 16;

  /// FAB 外边距，来自 `layout_margin="16.0dp"`。
  static const double fabMargin = 16;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Stack(
      children: [
        if (itemCount == 0)
          PagerEmptyState(
            title: emptyTitle,
            message: emptyMessage,
            outerPadding: emptyOuterPadding,
          )
        else
          ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
            // 原版分隔线是空 selector，所以这里放一条透明的 0.5dp 间隔，
            // 保留原版的间距观感而不画线。
            separatorBuilder: (context, index) =>
                const SizedBox(height: 0.5),
          ),
        Positioned(
          right: fabMargin,
          bottom: fabMargin,
          child: FloatingActionButton(
            onPressed: onNew,
            backgroundColor: palette.primaryBold,
            foregroundColor: Colors.white,
            elevation: 6,
            tooltip: newTooltip ?? context.s('new_connection'),
            // `ic_new` 是一个加号图标。
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

/// 原版里空状态有**两套**互不相同的布局，两套都复刻在这里。
///
/// 之所以要区分，是因为它们在竖直方向的行为完全不同：
/// `tabs` 用权重把内容压在屏幕下方 70% 处，`centered` 则是整块居中。
enum PagerEmptyStyle {
  /// 通讯录三页（`address_list.xml` / `identity_list.xml` / `port_forwards.xml`）：
  /// 竖直 `LinearLayout`，一个 `FrameLayout` 占位 `layout_weight="0.3"`，
  /// 内容区 `layout_weight="0.7"`。
  tabs,

  /// 片段等独立列表页（`pager_list.xml`，基类 `xh0` 用 `setContentView` 加载）：
  /// 整块竖直居中，标题带 `layout_marginTop="-40.0dp"`、与正文间距 8dp。
  centered,
}

/// 空状态。
///
/// ## `tabs` 样式，严格照 `res/layout/address_list.xml` 的 `@id/empty`
///
/// ```xml
/// <LinearLayout android:orientation="vertical" android:id="@id/empty"
///               android:layout_width="match_parent" android:layout_height="match_parent">
///     <FrameLayout android:layout_height="0.0dp" android:layout_weight="0.3" />
///     <LinearLayout android:orientation="vertical"
///                   android:padding="@dimen/activity_padding"
///                   android:layout_height="0.0dp" android:layout_weight="0.7">
///         <TextView android:id="@id/title" android:textSize="@dimen/text_heading"
///                   android:textColor="@color/text_heading"
///                   android:gravity="center_horizontal"
///                   android:layout_width="wrap_content" ... />
///         <TextView android:id="@id/subtitle" android:textColor="@color/text_subheading"
///                   android:gravity="center_horizontal"
///                   android:layout_marginTop="5.0dp"
///                   android:layout_width="wrap_content" ... />
///     </LinearLayout>
/// </LinearLayout>
/// ```
///
/// 420dpi 实测逐项吻合：内容区 359..2337px，`0.3 × 1978 = 593` → 内层从 952px 开始，
/// 加 16dp 内边距 → 标题 top = 994px；标题框高 127px，加 5dp → 副标题 top = 1134px。
/// 身份页因为 `@id/empty` 自带一层 `padding`，标题落在 **1011px**（差 16dp），
/// 所以要用 [outerPadding] 打开那一层。
///
/// ## `centered` 样式，照 `res/layout/pager_list.xml`
///
/// ```xml
/// <LinearLayout android:layout_gravity="center" android:id="@id/empty" match_parent>
///     <LinearLayout android:gravity="center" android:orientation="vertical"
///                   android:padding="@dimen/activity_padding" match_parent>
///         <TextView android:id="@id/emptyTitle" textSize="@dimen/text_heading"
///                   android:paddingLeft/Right="@dimen/activity_padding"
///                   android:layout_width="match_parent"
///                   android:layout_marginTop="-40.0dp" />
///         <TextView android:id="@id/emptyMessage" textColor="@color/text_subheading"
///                   android:paddingLeft/Right="@dimen/activity_padding"
///                   android:layout_width="match_parent"
///                   android:layout_marginTop="8.0dp" />
///     </LinearLayout>
/// </LinearLayout>
/// ```
///
/// 负上边距的净效果可以精确推导：设标题框高 `T`、正文框高 `M`、两者间距 8dp、
/// 外层上下各 16dp。Android 里内容组高度是 `T+8+M-40`，居中后标题框顶 =
/// `(可用高 - (T+M-32)) / 2 - 40`；Flutter 里居中一个 `T+8+M` 的组、再加
/// 16dp 内边距，标题框顶 = `(可用高 - (T+M+32)) / 2 + 16`。两者相减恒等于
/// **-20dp**，与文字高度无关 —— 所以「居中 + 整体上移 20dp」是精确等价，
/// 不是近似。
class PagerEmptyState extends StatelessWidget {
  const PagerEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.style = PagerEmptyStyle.tabs,
    this.outerPadding = false,
  });

  final String title;
  final String message;
  final PagerEmptyStyle style;

  /// 只对 [PagerEmptyStyle.tabs] 有意义：是否再套一层 16dp 内边距
  /// （`identity_list.xml` 的 `@id/empty` 自带 `android:padding`）。
  final bool outerPadding;

  /// 标题字号，来自 `@dimen/text_heading`。
  static const double titleSize = PagerList.emptyTitleSize;

  /// 副标题在原版里没有写 `textSize`，用的是主题默认值 14sp
  /// （实测字形带高 36px ≈ 0.95em × 14sp）。
  static const double messageSize = 14;

  /// Android 单行 `TextView` 的框高系数：行高 1.172em + `includeFontPadding`
  /// 约 0.19em ≈ **1.362em**（36sp 实测框高 127px）。
  static const double lineBoxHeight = 1.362;

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      PagerEmptyStyle.tabs => _buildTabs(context),
      PagerEmptyStyle.centered => _buildCentered(context),
    };
  }

  Widget _buildTabs(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: outerPadding
          ? const EdgeInsets.all(PagerList.padding)
          : EdgeInsets.zero,
      child: Column(
        children: [
          // weight 0.3 的占位 FrameLayout。
          const Expanded(flex: 3, child: SizedBox.expand()),
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(PagerList.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _title(palette),
                  const SizedBox(height: 5),
                  _message(palette),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCentered(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -20),
        child: Padding(
          padding: const EdgeInsets.all(PagerList.padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // 原版两个 TextView 都是 `layout_width="match_parent"`，
            // 所以文字盒铺满、靠 `gravity` 居中。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PagerList.padding,
                ),
                child: _title(palette),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PagerList.padding,
                ),
                child: _message(palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(JuicePalette palette) => Text(
    title,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: titleSize,
      height: lineBoxHeight,
      color: palette.textHeading,
    ),
  );

  Widget _message(JuicePalette palette) => Padding(
    // 正文往往是多行：`includeFontPadding` 只加在整段的首行上方与末行下方，
    // 不加在行与行之间，所以这里不能用 `height` 放大行距（那会把两行之间的
    // 间距也撑开）。Flutter 默认行高就是字体度量的 1.172em，与 Android 每行
    // 一致；缺的 0.19em 用上下各 0.095em 的内边距补回来。
    padding: EdgeInsets.symmetric(vertical: 0.095 * messageSize),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: messageSize, color: palette.textSubheading),
    ),
  );
}

/// 首页卡片列表用的行。
///
/// 原版 `res/layout/card_list_item.xml`：整行高 `@dimen/list_item_height`
/// （**72dp**），标题 `@dimen/text_item_title`（**16sp**）/ 颜色
/// `@color/text_item_title`，副标题 `@dimen/text_item_subtitle`（**12sp**）/
/// 颜色 `@color/text_item_subtitle`；左侧是 FontAwesome 图标位，
/// 图标色 `@color/icon_item`。按下反馈是 `card_item_pressed.xml`
/// —— 左右 inset 3dp、上下 4dp、圆角 2dp、实心 `@color/accent_lighter_transparent`。
class JuiceListItem extends StatelessWidget {
  const JuiceListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingColor,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Color? leadingColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 行高，来自 `@dimen/list_item_height`。
  static const double height = 72;

  /// 标题/副标题字号，来自 `@dimen/text_item_title` / `text_item_subtitle`。
  static const double titleSize = 16;
  static const double subtitleSize = 12;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final subtitleText = subtitle;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: palette.accentLighterTransparent,
      highlightColor: palette.accentLighterTransparent,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (leading != null)
              // 图标位宽度来自 `connection_menu_item.xml` 的 `itemIcon`
              // （`android:layout_width="40.0dp"`）。原版文字列 = 16dp 行内边距 +
              // 40dp 图标 + 16dp 间隔（文字容器的 `paddingLeft` 也是
              // `@dimen/activity_padding`）= 72dp = 189px —— 实测原版
              // `All`/`Not shared`/`10.0.2.2`/`juice` 四行的墨迹都起于
              // x 189..192，而写成 32dp 的克隆是 171。图标中线也随之从 84px
              // 回到原版分组指示器所在的 94.5px。
              SizedBox(
                width: 40,
                child: IconTheme(
                  data: IconThemeData(color: leadingColor ?? palette.textHeading),
                  child: leading!,
                ),
              ),
            if (leading != null) const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      // Android 单行 TextView 的框高 = 1.172em 行高
                      // + 0.19em 的 includeFontPadding ≈ 1.362em。
                      height: 1.362,
                      color: palette.textItemTitle,
                    ),
                  ),
                  if (subtitleText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: subtitleSize,
                        height: 1.362,
                        color: palette.textItemSubtitle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 列表行之间的分隔线。
///
/// 原版 `@drawable/highlight` 是空 selector，所以**不画线**；
/// 需要分隔感时由各页面自行决定是否使用 `Divider`。
class JuiceInvisibleDivider extends StatelessWidget {
  const JuiceInvisibleDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 0.5);
}
