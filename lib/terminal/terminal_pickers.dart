import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../widgets/juice_alert_dialog.dart';
import 'terminal_fonts.dart';
import 'terminal_themes.dart';

/// 终端配色方案与字体的选择列表。
///
/// 条目布局严格按原版：
/// * 配色方案 —— `res/layout/terminal_theme_item.xml`：左侧名称
///   （12sp、高 48dp、单行、`weight=1`），右侧 4 列 × 2 行的色块，
///   每块 **24dp × 8dp**，两行间距 4dp+4dp（即行内下/上各 4dp 外边距），
///   左右整体留白 16dp；
/// * 字体 —— `res/layout/terminal_font_item.xml`：只有一个名称，
///   12sp、高 48dp、左右留白 16dp。
///
/// 字体条目按原版习惯用**该字体自身**渲染，这样能直接看出字形差异。
class TerminalPickers {
  const TerminalPickers._();

  /// 色块尺寸，来自 `terminal_theme_item.xml`。
  static const double swatchWidth = 24;
  static const double swatchHeight = 8;

  /// 条目高度，来自两个布局里 TextView 的 `48.0dp`。
  static const double itemHeight = 48;

  /// 左右留白，来自两个布局的 `paddingLeft/Right="16.0dp"`。
  static const double itemPadding = 16;

  /// 配色方案选择框。返回选中的索引；取消返回 null。
  static Future<int?> pickTheme(BuildContext context, int current) {
    final s = context.s;
    return showDialog<int>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => JuiceAlertDialog(
        // 设置项的真实标题键是 `theme_slash_colors`；
        // `terminal_theme` 这个键在原版字符串表里**不存在**。
        title: s('theme_slash_colors'),
        // 列表是自定义行（`terminal_theme_item.xml`），有 custom view
        // 就没有标题分隔条。
        showTitleDivider: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: JuiceTerminalThemes.count,
          itemBuilder: (context, index) => _ThemeRow(
            index: index,
            name: JuiceTerminalThemes.names[index],
            selected: index == current,
            onTap: () => Navigator.of(context).pop(index),
          ),
        ),
        actions: [
          JuiceDialogAction(
            label: s('cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 字体选择框。返回选中的显示名；取消返回 null。
  static Future<String?> pickFont(BuildContext context, String current) {
    final s = context.s;
    return showDialog<String>(
      context: context,
      barrierColor: JuiceDialogColors.barrier,
      builder: (context) => JuiceAlertDialog(
        title: s('font'),
        showTitleDivider: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: TerminalFonts.displayOrder.length,
          itemBuilder: (context, index) {
            final name = TerminalFonts.displayOrder[index];
            return InkWell(
              onTap: () => Navigator.of(context).pop(name),
              child: Container(
                height: itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: itemPadding),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: TerminalFonts.familyOf(name),
                        ),
                      ),
                    ),
                    if (name == current) const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          JuiceDialogAction(
            label: s('cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// 单条配色方案。
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
    required this.index,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final swatches = JuiceTerminalThemes.swatches(index);

    // 名称在左、色块网格在右；网格是 4 列 × 2 行，每块 24×8dp。
    Widget gridRow(int start) => Padding(
          padding: EdgeInsets.only(
            bottom: start == 0 ? 4 : 0,
            top: start == 0 ? 0 : 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: TerminalPickers.swatchWidth,
                  height: TerminalPickers.swatchHeight,
                  color: swatches[start + i],
                ),
            ],
          ),
        );

    return InkWell(
      onTap: onTap,
      child: Container(
        height: TerminalPickers.itemHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: TerminalPickers.itemPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (selected) const Icon(Icons.check, size: 18),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [gridRow(0), gridRow(4)],
            ),
          ],
        ),
      ),
    );
  }
}
