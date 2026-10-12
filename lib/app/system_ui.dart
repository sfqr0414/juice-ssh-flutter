import 'dart:io';

import 'package:flutter/services.dart';

/// 状态栏底色的设置入口。
///
/// **为什么不直接用 `SystemUiOverlayStyle.statusBarColor`**：设备实测（模拟器
/// API 36 + Flutter 3.47.7）里 Flutter 侧这个字段**不生效**。判定方式是颜色探针：
/// 把主题级 overlay 设成纯红、终端页设成纯绿，再截图三个页面 —— 状态栏全都仍是
/// Android 主题里的黄色 `(240,210,53)`，红与绿都没有出现。原因是 Flutter 默认使用
/// `SystemUiMode.edgeToEdge`（见框架 `services/system_chrome.dart` 的说明），此时
/// 状态栏底色由窗口决定、不由 overlay 决定。
///
/// 而**直接设窗口**是有效的：原版终端页实测 y0..127 = `(7,54,66)`（= 终端配色的
/// ANSI 0），本项目的 Android 主题 `android:statusBarColor` 也确实把主界面染成了
/// `(240,210,53)`。所以这里走平台通道调 `Window.setStatusBarColor`。
///
/// 图标明暗（`statusBarIconBrightness`）仍由 Flutter 侧 overlay 生效，两者不冲突。
class JuiceSystemUi {
  const JuiceSystemUi._();

  static const MethodChannel _channel = MethodChannel('juicessh/system_ui');

  /// 设置状态栏底色。[lightIcons] 为 true 时用深色图标（浅底），否则用白色图标。
  ///
  /// 非 Android 平台直接忽略（本项目只出 Android，桌面端调试时不该抛异常）。
  static Future<void> setStatusBar(
    Color color, {
    bool lightIcons = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setStatusBar', <String, Object>{
        'color': color.toARGB32(),
        'lightIcons': lightIcons,
      });
    } on MissingPluginException {
      // 旧安装包或通道未注册时不致命：状态栏回落 Android 主题的配色。
    } on PlatformException {
      // 同上。
    }
  }
}
