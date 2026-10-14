import 'package:flutter/material.dart';

import '../app/juice_theme.dart';

/// @brief AppCompat `AlertDialog` 的度量还原。
///
/// 原版用的是 `androidx.appcompat.app.AlertDialog`，布局是三段结构
/// `res/layout/abc_alert_dialog_material.xml`：
///
/// ```xml
/// <AlertDialogLayout id=parentPanel>
///   <include layout=abc_alert_dialog_title_material/>   <!-- topPanel    -->
///   <FrameLayout id=contentPanel> … </FrameLayout>        <!-- 列表/正文    -->
///   <include layout=abc_alert_dialog_button_bar_material/>  <!-- buttonPanel -->
/// </AlertDialogLayout>
/// ```
///
/// Flutter 的 `AlertDialog` 也是「标题 + 内容 + 按钮」三段，结构能对上，
/// 但**默认边距差得很远**（实测窗口 870×712 对原版 1024×765），所以这里把
/// 每个数字都按实测或框架资源还原。
///
/// 长度单位说明：420dpi，1dp = 2.625px。注释里同时给出 px 便于对照截图。
abstract final class JuiceDialogMetrics {
  /// @brief 9-patch 背景的内缩 = `appcompat_dialog_background_inset`（16dp）。
  ///
  /// 原版对话框**窗口**是 1024×765（`[28,850][1052,1615]`），但**可见白底**
  /// 只有 `[70,892][1010,1573]` = 940×681 —— 差的正好是四周各 16dp，
  /// 那 16dp 里是 9-patch 的柔和阴影（实测 `#666666`→`#616161` 渐变）。
  /// 所以：窗口 = 面板 + 2×16dp，本实现的 `Dialog` 盒子按**面板**取，
  /// 阴影交给 Flutter 自己的 elevation 画。
  static const double backgroundInset = 16;

  /// @brief 窗口宽度 = 屏幕的 95%（`abc_dialog_min_width_minor` = 95.00001%）。
  /// 实测 1080 × 0.95 = 1026px ≈ 1024px ✔
  static const double windowWidthFraction = 0.95;

  /// @brief 窗口左右外边距 = (屏幕宽 − 95% 屏幕宽)/2 + 9-patch 内缩。
  static double horizontalInsetFor(double screenWidth) =>
      screenWidth * (1 - windowWidthFraction) / 2 + backgroundInset;

  /// @brief 标题内边距：左 24dp = `?dialogPreferredPadding`
  /// （= `abc_dialog_padding_material`）；实测标题盒左缘 133px，
  /// 133 − 70(面板左) = 63px = 24dp ✔
  static const double titlePaddingLeft = 24;

  /// @brief 标题上内边距 18dp = `abc_dialog_padding_top_material`；
  /// 实测 939 − 892(面板顶) = 47px = 17.9dp ✔
  /// （`title_template` 节点实测 `[70,892][1010,1010]`，高 118px = 47 + 71 ✔）
  static const double titlePaddingTop = 18;

  /// @brief 标题下内边距。原版这里是 `@id/titleDividerNoCustom`：一个
  /// `android.widget.Space`，高 `abc_dialog_title_divider_material` = 8dp，
  /// **透明**（实测 y1010..1031 整条 100% 纯色，没有任何分隔线像素）。
  static const double titlePaddingBottom = 8;

  /// @brief 标题字号：`?android:windowTitleStyle` =
  /// `TextAppearance.AppCompat.Title`，
  /// 20sp。实测文字盒 71px = 20sp × 1.362 ✔（和 ListView 行盒同一个系数）
  static const double titleFontSize = 20;

  /// @brief 内容左右内边距：**0**。实测列表 `[70,1031][1010,1409]` 与面板同宽 ✔
  /// （老实现写 16dp，是把 9-patch 内缩算了两遍）
  static const double contentPaddingHorizontal = 0;

  /// @brief 按钮栏内边距。`abc_alert_dialog_button_bar_material.xml` 里
  /// `ButtonBarLayout` 自带 12dp 左右、4dp 上下：
  /// * 右：面板右 1010 − 按钮右 978 = 32px = 12.2dp ✔
  /// * 上：1420 − 1409 = 11px = 4.2dp ✔
  /// * 下：1573 − 1562 = 11px = 4.2dp ✔
  static const double actionsPaddingLeft = 0;
  /// @brief 按钮栏右内边距 12dp（ButtonBarLayout 自带）。
  static const double actionsPaddingRight = 12;
  /// @brief 按钮栏上内边距 4dp（ButtonBarLayout 自带）。
  static const double actionsPaddingTop = 4;
  /// @brief 按钮栏下内边距 4dp（ButtonBarLayout 自带）。
  static const double actionsPaddingBottom = 4;

  /// @brief 按钮（`?buttonBarButtonStyle`）。API 28+ 被 `values-v28/styles.xml`
  /// 覆盖成 `Widget.MaterialComponents.Button.TextButton.Dialog`：
  /// 最小宽度 `mtrl_btn_dialog_btn_min_width` = 64dp（= 168px，实测
  /// SAVE 按钮正好 168px ✔）。实测按钮盒高 142px，两个按钮**紧贴无间隙**
  /// （SAVE 左边 = CANCEL 右边）。
  ///
  /// 左右内边距实测 **12dp**：CANCEL 按钮盒 202px，文字盒约 140px，
  /// (202 − 140) / 2 = 31px = 11.8dp ✔。写 8dp（`mtrl_btn_text_btn_padding_*`）
  /// 会让文字整体右移 11px，实测对不上。
  static const double buttonMinWidth = 64;
  /// @brief 按钮左右内边距 12dp（实测，不是 Material 默认的 8dp）。
  static const double buttonPaddingHorizontal = 12;
  /// @brief 按钮高度，实测 142px。
  static const double buttonHeight = 142 / 2.625;
  /// @brief 按钮字号 14sp。
  static const double buttonFontSize = 14;

  /// @brief 单选列表行（`res/layout/select_dialog_singlechoice_material.xml`）：
  /// `minHeight = ?listPreferredItemHeightSmall` = 48dp（实测 126px ✔）、
  /// 起始内边距 `abc_select_dialog_padding_start_material` = 20dp、
  /// `android:drawablePadding` = 20dp，文字 16sp
  /// （`?android:textAppearanceMedium`）。
  static const double listItemHeight = 48;
  /// @brief 列表行起始内边距 20dp（abc_select_dialog_padding_start_material）。
  static const double listItemPaddingStart = 20;
  /// @brief 标记与文字之间的间隔 20dp（android:drawablePadding）。
  static const double listItemDrawablePadding = 20;

  /// @brief 单选标记的**槽宽**。`android:drawableLeft` 的固有宽度实测 32dp：
  /// 格子左缘 122px = 70 + 20dp(52px)，文字起于 259px
  /// = 122 + 32dp(84px) + 20dp(52px) + 字形左边距 ✔
  static const double listItemIndicatorWidth = 32;

  /// @brief 单选标记本身的直径。实测选中/未选中标记的墨迹都是 52px = 19.8dp，
  /// 且在 32dp 槽里**居中**（左右各 16px ≈ 6.1dp）。
  static const double listItemIndicatorSize = 20;

  /// @brief 单选标记的描边宽度与选中时的内点直径（Material 单选按钮规格）。
  static const double listItemIndicatorStroke = 2;
  /// @brief 选中时内点直径 10dp。
  static const double listItemIndicatorDot = 10;

  /// @brief 列表文字字号。
  ///
  /// 布局文件写的是 `?android:textAppearanceMedium`（平台主题下是 16sp），
  /// 但**实测是 18sp**：拿 Roboto 的字形度量反推，
  /// "Light" 的墨迹高（cap 1456 + descender 500，共 0.955em）
  /// 原版 45px → 47.1px/em → 17.9sp，而复刻按 16sp 渲染只有 41px。
  /// 逐个字形也一致（原版 L/g/h/t 墨迹宽 20/21/20/14 对 16sp 的 19/19/18/12）。
  /// 按钮 14sp（"CANCEL" 两边都是 136px）与标题 20sp 都对得上，
  /// 所以不是全局缩放，就是这一处取到了 18sp 的外观
  /// （API 36 的 `?android:textAppearanceMedium` 落到 DeviceDefault 家族，
  /// 那一支的 Medium 历来是 18sp）。
  static const double listItemFontSize = 18;

  /// @brief 对话框圆角：`abc_dialog_corner_radius_material` = 2dp。
  static const double cornerRadius = 2;
}

/// @brief 对话框配色。
///
/// **不是** JuiceSSH 自己的 `text_*` 资源 —— `AlertDialog` 会被
/// `ThemeOverlay.AppCompat.Dialog.Alert` 包一层，文字色回到框架取值。
/// 实测（420dpi，主题选择对话框）：
///
/// | 取样 | 亮色 | 暗色 |
/// |---|---|---|
/// | 对话框底 | `#FFFFFF` | `#424242` |
/// | 标题 | `#212121` | `#FFFFFF` |
/// | 列表文字 | `#212121` | `#FFFFFF` |
/// | 单选标记（未选中） | `#666666` | `#C7C7C7` |
/// | 单选标记（选中）/ 按钮文字 | `#586E75` | `#D5BA31` |
///
/// `#212121` 就是 `#DE000000`（87% 黑）叠在白底上的结果，`#666666` 是
/// 60% 黑叠白，`#C7C7C7` 是 `@android:color/secondary_text_dark`
/// （`#B3FFFFFF`，70% 白）叠在 `#424242` 上的结果 —— 三个都能对上公式。
class JuiceDialogColors {
  /// @brief 用五个颜色分量构造一套对话框配色。
  const JuiceDialogColors({
    required this.background,
    required this.title,
    required this.body,
    required this.indicatorUnchecked,
    required this.accent,
  });

  /// @brief 对话框底色（亮色 #FFFFFF / 暗色 #424242）。
  final Color background;
  /// @brief 标题文字色。
  final Color title;
  /// @brief 正文与列表文字色。
  final Color body;
  /// @brief 未选中单选标记的颜色（60% 黑 / 70% 白）。
  final Color indicatorUnchecked;

  /// @brief 选中标记与按钮文字共用的强调色（= `@color/accent_bold`）。
  final Color accent;

  /// @brief 按当前主题取一整套对话框配色。
  factory JuiceDialogColors.of(BuildContext context) {
    final palette = context.palette;
    return JuiceDialogColors(
      background: palette.isDark ? const Color(0xFF424242) : Colors.white,
      title: palette.isDark ? const Color(0xFFFFFFFF) : const Color(0xDE000000),
      body: palette.isDark ? const Color(0xFFFFFFFF) : const Color(0xDE000000),
      indicatorUnchecked:
          palette.isDark ? const Color(0xB3FFFFFF) : const Color(0x99000000),
      accent: palette.accentBold,
    );
  }

  /// @brief 遮罩。实测亮色下背景 `#FFFFFF` 被压到 `#666666`
  /// （1 − 102/255 = 0.6），即 60% 黑。
  static const Color barrier = Color(0x99000000);

  /// @brief 正文样式：`@android:id/message` 用的是
  /// `TextAppearance.AppCompat.Subhead` = 16sp。
  ///
  /// 行高用 Roboto 的**自然**行高 1.171em，不是别处那个 1.362em：
  /// 实测原版 "Clear known hosts" 确认框的正文行间距 = 49px
  /// = 16sp × 1.166 ✔，四行 + 一个空行正好排成 1082/1131/(空)/1229/1278。
  /// 1.362em 是 `includeFontPadding` 把**单行**盒子撑高的效果（标题盒
  /// 71px = 20sp × 1.362 ✔、列表行盒 71px ✔），它只影响行盒不影响行距，
  /// 多行正文按 1.362 排会每行多 8px。
  TextStyle get bodyStyle =>
      TextStyle(fontSize: 16, height: 1.171, color: body);
}

/// @brief 对话框外壳，还原 AppCompat 的三段布局与边距。
///
/// 用法与 `AlertDialog` 一致，但 [title] 是字符串、[actions] 用
/// [JuiceDialogAction]（已按实测高度/最小宽度/大写处理）。
///
/// 这里**不用** Flutter 的 `AlertDialog`：它内部会套一层 `IntrinsicWidth`，
/// 而列表内容（`ListView`）不支持固有宽度，会直接报
/// "does not support returning intrinsic dimensions" 并把对话框画成空白
/// （只剩遮罩）。自己用 [Dialog] + `Column` 反而更贴合原版的三段结构，
/// 边距也能逐项写死。
class JuiceAlertDialog extends StatelessWidget {
  /// @brief 构造「标题 + 内容 + 按钮」三段式对话框外壳。
  const JuiceAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const <Widget>[],
    this.contentPadding,
    this.showTitleDivider = true,
  });

  /// @brief 标题文案；null 表示不画标题行。
  final String? title;
  /// @brief 内容区：列表或正文。
  final Widget? content;
  /// @brief 右下角按钮栏，按传入顺序从左到右排。
  final List<Widget> actions;

  /// @brief 标题下的 8dp 空白（`@id/titleDividerNoCustom`）是否保留。
  ///
  /// 实测规则：**用了 custom view 就没有这一条**。
  /// 主题选择框（title + ListView）里它是可见节点
  /// `[70,1010][1010,1031]`（21px）；Quick Connect（title + 自定义内容）
  /// 的 `topPanel` 到 1009 就直接接 `customPanel`，没有这 21px。
  final bool showTitleDivider;

  /// @brief 内容内边距。默认按**列表**场景（左右各 16dp，等于只有背景内缩）；
  /// **消息框**要传 [messageContentPadding]，因为
  /// `abc_alert_dialog_material.xml` 里 `@android:id/message` 自己带
  /// `?dialogPreferredPadding` = 24dp。两者实测不同，别混。
  final EdgeInsets? contentPadding;

  /// @brief 消息框（`@android:id/message`）的内容内边距。
  static const EdgeInsets messageContentPadding =
      EdgeInsets.symmetric(horizontal: 24);

  /// @brief 上下留白（原版由 AlertDialog 窗口自己按屏幕高度决定，这里取一个
  /// 不会碰到边的小值；真正决定纵向位置的是 `insetPadding` 的上下不对称）。
  static const double _verticalMargin = 24;

  /// @brief 纵向居中的修正量。
  ///
  /// 第 67 轮实测（420dpi，字号对话框，整行 `#424242` 面板色扫描）：
  /// 原版面板 y 730..1733（高 1004px，中心 **1231.5** = 应用窗口中心
  /// (128+2337)/2 ≈ 1232.5）；克隆面板 y 795..1797（高 **1003px** 已吻合，
  /// 但中心 **1296**）—— 也就是整体低了 64.5px = **24.6dp**。
  /// 面板高度与 x 范围（69..1010 对 70..1009）都已对齐，只有纵向居中偏了。
  ///
  /// 居中位置只取决于 `(top − bottom)`：center = (H + top − bottom) / 2，
  /// 所以补在**下**边距上时要补两倍，即 2 × 24.6 = 49.2dp。
  static const double _bottomCenterCorrection = 49.2;

  /// @brief 按「标题 / 内容 / 按钮」三段拼出对话框外壳。
  @override
  Widget build(BuildContext context) {
    final colors = JuiceDialogColors.of(context);
    final media = MediaQuery.of(context);
    // 不能用 `MediaQuery.padding`：对话框路由外面套了 `SafeArea`，
    // `MediaQueryData.removePadding` 会把 `padding` **和** `viewPadding`
    // 一起减掉（实测两者都是 zero），拿到的状态栏高度会变成 0。
    // `FlutterView` 上的值才是平台原始值，这里按物理像素换算回逻辑像素。
    final view = View.of(context);
    final statusBar = view.viewPadding.top / view.devicePixelRatio;
    final navBar = view.viewPadding.bottom / view.devicePixelRatio;
    return Dialog(
      backgroundColor: colors.background,
      // 去掉 Material 3 的着色叠加：原版是纯色 9-patch。
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JuiceDialogMetrics.cornerRadius),
      ),
      // 原版对话框窗口是在**应用窗口**里居中的：
      // 面板 `[70,892][1010,1573]`，中心 y = 1232.5 = (128 + 2337) / 2，
      // 也就是「状态栏之下、导航栏之上」那一段的中心。
      // Flutter 默认在整块 2400px 画布里居中（中心 1200），会整体高 32px。
      //
      // 居中位置只取决于「上边距 − 下边距」：让上边距带上状态栏高度、
      // 下边距带上导航栏高度，(top − bottom) 就正好是两者的差 24.76dp
      // = 65px，中心正好落到 1232.5。
      insetPadding: EdgeInsets.only(
        left: JuiceDialogMetrics.horizontalInsetFor(media.size.width),
        right: JuiceDialogMetrics.horizontalInsetFor(media.size.width),
        top: statusBar + _verticalMargin,
        // `statusBar > 0` 说明应用窗口是 edge-to-edge（本机 Pixel 6 AVD 带挖孔，
        // 实测就是这种状态），此时只按 `(top − bottom)` 的原式会让对话框整体
        // 低 24.6dp（见 [_bottomCenterCorrection]）。若 `viewPadding.top` 为 0，
        // 说明视图本身就等于应用窗口，原式已经正确，补正反而会把它顶高同样多
        // —— 所以只在 edge-to-edge 状态下补。两个对话框（字号、Dark Theme）
        // 在本机实测都落在原版 ±0.5px 内。
        bottom:
            navBar + _verticalMargin + (statusBar > 0 ? _bottomCenterCorrection : 0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: EdgeInsets.only(
                left: JuiceDialogMetrics.titlePaddingLeft,
                top: JuiceDialogMetrics.titlePaddingTop,
                right: JuiceDialogMetrics.titlePaddingLeft,
                bottom: showTitleDivider
                    ? JuiceDialogMetrics.titlePaddingBottom
                    : 0,
              ),
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: JuiceDialogMetrics.titleFontSize,
                  height: 1.362,
                  color: colors.title,
                ),
              ),
            ),
          if (content != null)
            Padding(
              padding: contentPadding ??
                  const EdgeInsets.symmetric(
                    horizontal: JuiceDialogMetrics.contentPaddingHorizontal,
                  ),
              child: content!,
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: JuiceDialogMetrics.actionsPaddingLeft,
                top: JuiceDialogMetrics.actionsPaddingTop,
                right: JuiceDialogMetrics.actionsPaddingRight,
                bottom: JuiceDialogMetrics.actionsPaddingBottom,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// @brief 对话框按钮。可点区域 64dp×54.1dp，文案全大写
/// （Material 按钮的 `android:textAllCaps` 默认为真）。
class JuiceDialogAction extends StatelessWidget {
  /// @brief 用按钮文案与点击回调构造一个对话框按钮。
  const JuiceDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /// @brief 按钮文案，渲染时统一转大写。
  final String label;
  /// @brief 点击回调；null 表示按钮禁用。
  final VoidCallback? onPressed;

  /// @brief 构建 64dp×54.1dp 的大写文字按钮。
  @override
  Widget build(BuildContext context) {
    final colors = JuiceDialogColors.of(context);
    return SizedBox(
      height: JuiceDialogMetrics.buttonHeight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: JuiceDialogMetrics.buttonMinWidth,
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colors.accent,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(
              horizontal: JuiceDialogMetrics.buttonPaddingHorizontal,
            ),
            minimumSize: const Size(0, JuiceDialogMetrics.buttonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
            textStyle: const TextStyle(
              fontSize: JuiceDialogMetrics.buttonFontSize,
              fontWeight: FontWeight.w500,
              height: 1.362,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// @brief 单选列表行：`[20dp 起始内边距][32dp 标记槽][20dp 间隔][文字][24dp]`，
/// 行高 48dp，文字 16sp。整行可点。
class JuiceDialogListItem extends StatelessWidget {
  /// @brief 用行文案、选中状态与点击回调构造一行单选项。
  const JuiceDialogListItem({
    super.key,
    required this.label,
    required this.checked,
    required this.onTap,
  });

  /// @brief 行文字。
  final String label;
  /// @brief 是否为当前选中行。
  final bool checked;
  /// @brief 点击整行的回调。
  final VoidCallback onTap;

  /// @brief 构建 48dp 高的单选列表行。
  @override
  Widget build(BuildContext context) {
    final colors = JuiceDialogColors.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: JuiceDialogMetrics.listItemHeight,
        child: Row(
          children: <Widget>[
            const SizedBox(width: JuiceDialogMetrics.listItemPaddingStart),
            SizedBox(
              width: JuiceDialogMetrics.listItemIndicatorWidth,
              child: Center(
                child: _JuiceDialogRadio(checked: checked, colors: colors),
              ),
            ),
            const SizedBox(width: JuiceDialogMetrics.listItemDrawablePadding),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: JuiceDialogMetrics.listItemFontSize,
                  height: 1.362,
                  color: colors.body,
                ),
              ),
            ),
            // paddingRight = ?dialogPreferredPadding = 24dp。
            const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}

/// @brief Material 单选按钮：外圈 20dp（描边 2dp），选中时内点 10dp。
class _JuiceDialogRadio extends StatelessWidget {
  /// @brief 用选中状态与配色构造一个单选标记。
  const _JuiceDialogRadio({required this.checked, required this.colors});

  /// @brief 是否选中；选中时画内点。
  final bool checked;
  /// @brief 当前主题的对话框配色。
  final JuiceDialogColors colors;

  /// @brief 构建 20dp 的 Material 单选圈。
  @override
  Widget build(BuildContext context) {
    final color = checked ? colors.accent : colors.indicatorUnchecked;
    return SizedBox(
      width: JuiceDialogMetrics.listItemIndicatorSize,
      height: JuiceDialogMetrics.listItemIndicatorSize,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color,
            width: JuiceDialogMetrics.listItemIndicatorStroke,
          ),
        ),
        child: checked
            ? Center(
                child: Container(
                  width: JuiceDialogMetrics.listItemIndicatorDot,
                  height: JuiceDialogMetrics.listItemIndicatorDot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// @brief 单选列表对话框：标题 + 若干 48dp 行 + 一个 CANCEL。
///
/// 对应原版 `ListDBPreference` 弹出的 `AlertDialog`
/// （`setSingleChoiceItems` + 负向按钮）。
class JuiceListDialog extends StatelessWidget {
  /// @brief 用标题、候选条目与当前下标构造单选列表对话框。
  const JuiceListDialog({
    super.key,
    required this.title,
    required this.entries,
    required this.selectedIndex,
    required this.cancelLabel,
    this.maxVisibleItems = 7,
  });

  /// @brief 对话框标题。
  final String title;
  /// @brief 候选条目文案。
  final List<String> entries;
  /// @brief 当前选中项下标。
  final int selectedIndex;
  /// @brief 负向按钮文案（原版是 CANCEL）。
  final String cancelLabel;

  /// @brief 超过这个条数就让列表自己滚（原版由 `AlertController` 按屏幕高度决定）
  /// 。
  final int maxVisibleItems;

  /// @brief 构建 标题 + 单选列表 + CANCEL 的对话框。
  @override
  Widget build(BuildContext context) {
    final itemCount = entries.length;
    final maxHeight =
        JuiceDialogMetrics.listItemHeight * maxVisibleItems.toDouble();
    final list = ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: (context, index) => JuiceDialogListItem(
        label: entries[index],
        checked: index == selectedIndex,
        onTap: () => Navigator.of(context).pop(index),
      ),
    );
    return JuiceAlertDialog(
      title: title,
      // `shrinkWrap` 让列表按内容定高，`ConstrainedBox` 只兜住上限，
      // 超了才滚 —— 原版是 AlertController 按屏幕高度决定这个上限。
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: list,
      ),
      actions: <Widget>[
        JuiceDialogAction(
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
