import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/juice_theme.dart';

// ===========================================================================
// 原版 `TableLayout` 表单的公共度量与组件
// ===========================================================================
//
// 连接编辑页（`res/layout/manage_connection.xml`）和身份编辑页
// （`res/layout/manage_identity.xml`）是同一套写法：
//
//   ScrollView(padding=@dimen/activity_padding = 16dp, clipToPadding=false)
//    └ TableLayout
//       ├ TableRow  → TextView(style=?android:listSeparatorTextViewStyle)  分组标题
//       ├ TableRow  → TextView(wrap, marginRight=5dp) + 控件(0dp, weight=1)
//       └ TableRow  → ...（每行 android:layout_marginTop="8.0dp"）
//
// 所以本文件把「标题 / 标签行 / 输入框 / 按钮」四件事抽出来共用。
// 两个坑都在注释里写清楚了：标题高度、以及 `TableLayout` 的整列等宽。

/// 分组标题高度：实测 84px = 32dp。
///
/// **不是** `?android:listPreferredItemHeightSmall` 的 48dp —— 那会得到 126px，
/// 比原版高 42px 并把下面所有行推下去。
const double juiceFormSectionHeaderHeight = 84 / 2.625;

/// 分组标题的左侧内边距（墨迹起于 66px ⇒ 8dp）。
const double juiceFormSectionHeaderPadding = 8;

/// 标签与控件之间的 `android:layout_marginRight="5.0dp"`。
///
/// 它落在标签盒子的**外面**：原版标签 TextView 是 `[42,249]`，控件从 262 开始，
/// 249→262 正好 13px = 5dp。
const double juiceFormLabelGap = 5;

/// `EditText` 行高度（实测 106px = 40.38dp）。
const double juiceEditRowHeight = 106 / 2.625;

/// `Spinner` 行高度（布局里写死 `android:layout_height="36.0dp"`，实测 95px）。
const double juiceSpinnerRowHeight = 36;

/// 「普通」按钮高度：`manage_identity.xml` 里 `SET (OPTIONAL)` 的 36dp。
const double juiceButtonHeight = 36;

/// 「宽」按钮高度：`@id/generate_snippet` 的 42dp。
const double juiceWideButtonHeight = 42;

/// `@id/identityPasswordButton` 等按钮的 `android:layout_marginLeft="4.0dp"`
/// （实测按钮起于 260，而输入框起于 249，差 11px ≈ 4dp）。
const double juiceButtonLeftMargin = 4;

/// `EditText` 下划线（`@drawable/abc_edit_text_material` 的底边线）。
///
/// 实测：`EditText` 是 `[262,422][1038,528]`（高 106px），线却在 `y=504..507`、
/// 颜色 `#666666`，而且左右各内缩 10px（272..1027）—— **线既不在视图底边，
/// 也不占满整个宽度**。
const Color juiceEditUnderlineColor = Color(0xFF666666);

/// 下划线粗细（1dp）。
const double juiceEditUnderlineHeight = 1;

/// 下划线底边距行底：线的实心部分在 505..506，取线顶 504.9px，
/// 行底 528px ⇒ 528 − 504.9 − 2.625 = 20.5px。
const double juiceEditUnderlineBottom = 20.5 / 2.625;

/// 下划线左右各内缩 10px（9-patch 自带的留白）。
const double juiceEditUnderlineInset = 10 / 2.625;

/// `style="?android:listSeparatorTextViewStyle"` 分组标题。
///
/// 该样式 = 14sp + **加粗** + **`textAllCaps=true`** + `gravity=center_vertical`，
/// 原版在标题上覆写了 `android:textColor="@color/text_form_heading"`。
///
/// 注意大小写：这里**必须**自己做大写转换（字符串资源是 "Basic Settings"
/// 这种词形）。别和设置页的 `PreferenceCategory` 搞混 —— 那个不做大写，
/// 实测渲染出来就是 "General" / "App Security"。
class JuiceFormSectionHeader extends StatelessWidget {
  const JuiceFormSectionHeader({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: juiceFormSectionHeaderHeight,
      // 原版 `?android:listSeparatorTextViewStyle` 标题下方还有一条整宽分隔线：
      // 亮色实测 `#E0E0E0`（`o_id.png` 的 y 396..400 与 987..991，各 5px
      // @density 2.625 ≈ 2dp，两侧 x 42..1037 整宽）。
      // 暗色值**无可用参照**（`.research` 里没有暗色编辑页），按 Android 惯例取
      // 12% 白 —— 属"按惯例取值、未经实测"，见 docs/IMPLEMENTATION-NOTES.md。
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 2,
            color: context.palette.formDivider,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: juiceFormSectionHeaderPadding),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.362,
              fontWeight: FontWeight.bold,
              color: context.palette.textFormHeading,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行「标签 + 控件」，对应 `TableRow` 里
/// `TextView(wrap_content, marginRight=5dp)` + `控件(0dp, weight=1)` 的组合。
///
/// [labelWidth] 必须按**整列**传：`TableLayout` 的第 0 列宽度由这一列里最宽的
/// 标签决定，不是每个标签各算各的。连接编辑页是 207px（"Backspace:" 那一列），
/// 身份编辑页是 194px（"Private Key:"）。
class JuiceFormRow extends StatelessWidget {
  const JuiceFormRow({
    super.key,
    required this.label,
    required this.labelWidth,
    required this.child,
    this.height,
  });

  final String label;
  final double labelWidth;
  final Widget child;

  /// 整行高度。`EditText` 行 106px、`Spinner`/按钮行 95px，两者不一样。
  final double? height;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.362,
              color: context.palette.textForm,
            ),
          ),
        ),
        const SizedBox(width: juiceFormLabelGap),
        // 用 `Align` 而不是直接 `Expanded(child: child)`：`Expanded` 给的是
        // **紧**宽度约束，`@id/port_value` 那种窄控件会被拉满整行
        // （实测端口框的下划线横贯整行，而原版只到 477）。
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ],
    );
    return height == null ? row : SizedBox(height: height, child: row);
  }
}

/// 表单输入框：`EditText` + 自绘下划线。
///
/// 行高固定 106px，输入框在其中垂直居中（这样文字墨迹位置与原版一致）。
class JuiceFormTextField extends StatelessWidget {
  const JuiceFormTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.autocorrect = true,
    this.height = juiceEditRowHeight,
    this.fontSize = 14,
    this.underlineColor = juiceEditUnderlineColor,
    this.underlineHeight = juiceEditUnderlineHeight,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// `inputType=textVisiblePassword` 的字段要关掉自动联想/纠错。
  final bool autocorrect;

  /// 行高。表单里是 106px；对话框里的 `EditText` 实测 **118px**（45dp），
  /// 下划线跟着行底下移。
  final double height;

  final double fontSize;

  /// 下划线颜色与粗细。默认值是**未聚焦**态：1dp、`#666666`（编辑器里实测）。
  /// 对话框里的输入框在原版是**聚焦**态 —— Material 规范下变成 2dp 的
  /// `colorControlActivated`。实测 `.research/id_o2.png`：Quick Connect 输入框的
  /// 下划线是 `accentBold` (213,186,49)、5px = 2dp、x 135..957（左右各内缩约
  /// 4dp，与 [juiceEditUnderlineInset] 的 10px 完全吻合），克隆当时只有 1dp 的
  /// `#666666`，所以在截图里根本看不到强调色。
  final Color underlineColor;
  final double underlineHeight;

  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: height,
      // `StackFit.expand` 让 Stack 取满可用宽度（在 `JuiceFormRow` 的 `Align`
      // 之下是松约束，`double.infinity` 用不了）。
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                autocorrect: autocorrect,
                autofocus: autofocus,
                onSubmitted: onSubmitted,
                enableSuggestions: autocorrect,
                style: TextStyle(fontSize: fontSize, color: palette.textForm),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: TextStyle(
                    fontSize: fontSize,
                    // 原版的提示文字是 Android 的 `textColorHint`
                    // （= `textColorSecondary` = 70% 白）。克隆原来用调色板里扁平的
                    // `textFormHeading` (#BEBEBE)：它叠在卡片底色 `#212121` 上正好是
                    // 190（所以卡片上的表单看不出问题），但叠在**对话框**的 `#424242`
                    // 上应该更亮。实测 `.research/id_o2.png` 原版提示文字是
                    // (199,199,199)、克隆是 (190,190,190)：0.7×255 + 0.3×66 ≈ 198 ✔。
                    // 只改暗色主题：亮色主题的对话框底色是 `#FAFAFA`，与卡片接近，
                    // 且没有实测依据，保持原值。
                    color: palette.isDark
                        ? const Color(0xB3FFFFFF)
                        : palette.textFormHeading,
                  ),
                  // 下划线自绘，去掉 Flutter 自带的那条。
                  //
                  // 注意**不能只写 `border: InputBorder.none`**：
                  // `InputDecoration.applyDefaults()` 会先把
                  // `InputDecorationTheme.enabledBorder` / `focusedBorder`
                  // 合并进来，而 `_getDefaultBorder()` 的判断顺序是
                  // `enabledBorder ?? border ?? 默认`，主题那条会先命中。
                  // 结果就是屏幕下多出一条 `#BCCACF` 的浅线（实测证实）。
                  // 所以五种状态的边都得显式置空。
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ),
          Positioned(
            left: juiceEditUnderlineInset,
            right: juiceEditUnderlineInset,
            bottom: juiceEditUnderlineBottom,
            child: Container(
              height: underlineHeight,
              color: underlineColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// `CheckBox` + 文字（`layout_weight=1` 撑满），行高按调用方给。
///
/// 原版是 `CheckBox w=0dp layout_weight=1 layout_marginRight=5dp`，
/// 文字即复选框自身的 `android:text`，`textAppearance=?android:textAppearanceSmall`、
/// `textColor=@color/text_form`。（API 36 上 DeviceDefault 家族的 Small = 14sp，
/// 与 Medium = 18sp 同一套刻度，所以正文字号取 14。）
///
/// 实测（端口转发编辑页 `[42,1162][1038,1246]`，行高 **84px** = 32dp）：
/// * 方框 `x=61..107 y≈1180..1227` → 距行左 **19px**、边长 46px（≈17.5dp）；
/// * 文字墨迹从 `x=128` 起 → 距行左 **86px**，与方框右缘（107）相隔 21px。
///
/// Flutter 侧实测下来：`Checkbox`（`shrinkWrap` + `VisualDensity(-4,-4)`）
/// 的**控件盒**是 24dp = 63px，18dp 的方框居中、离控件左边 8px。所以
/// 前面补 11px 让方框落到 61px，方框到文字再留 12px（控件右缘 116 → 文字 128）。
class JuiceCheckRow extends StatelessWidget {
  const JuiceCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.height,
    this.fontSize = 14,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 行高。原版复选框行 84px，比输入框行（106px）矮。
  final double? height;

  final double fontSize;

  /// 方框距行左 19px，而控件内方框自带 8px 左边距 ⇒ 前面补 11px。
  static const double _boxLead = 11 / 2.625;

  /// 控件右缘（116px）到文字墨迹（128px）之间的距离。
  ///
  /// 实测 Flutter 侧留 12px 时文字落在 130px（比原版晚 2px），改成 10px。
  static const double _labelGap = 10 / 2.625;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        const SizedBox(width: _boxLead),
        Checkbox(
          value: value,
          onChanged: (checked) => onChanged(checked ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        ),
        const SizedBox(width: _labelGap),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.362,
              color: context.palette.textForm,
            ),
          ),
        ),
      ],
    );
    return InkWell(
      onTap: () => onChanged(!value),
      child: height == null ? row : SizedBox(height: height, child: row),
    );
  }
}

/// `@drawable/button` —— 圆角 2dp、1dp 描边、实心 `@color/button_background`，
/// 文字 `@color/button_text`、字号 `@dimen/text_button`（16sp）。
///
/// 原版是 `Button` 且 `background=@drawable/button`，所以按钮的**视图边界就是
/// 可见边界**（没有 Material 默认背景那圈内缩）；`gravity=center` 让文字居中。
///
/// 文案**一律转大写**：Material 主题的 `Button` 带 `textAllCaps=true`，
/// 资源里写的是 "Set (optional)" / "Generate snippet"，屏幕上却渲染成
/// "SET (OPTIONAL)" / "GENERATE SNIPPET"（uiautomator 层级里也是大写的）。
class JuiceFormButton extends StatelessWidget {
  const JuiceFormButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = juiceButtonHeight,
  });

  final String label;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: palette.buttonBackground,
          foregroundColor: palette.buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          side: BorderSide(color: palette.buttonStroke),
          textStyle: const TextStyle(fontSize: 16),
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
