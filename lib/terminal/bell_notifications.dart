import 'dart:async';

import 'package:flutter/services.dart';

/// @brief 终端响铃（`terminal:bell_mode = 2`）的通知桥。
///
/// 原版把响铃做成一条普通通知：标题 `@string/terminal_bell`
/// （"Terminal Bell"）、正文 `@string/terminal_bell_received`
/// （"Terminal bell received!"），并另有一句 `@string/x_terminal_bells`
/// （"%d terminal bells"）。消费方在 `zi0.smali` / `Config.smali`。
///
/// 这里用**固定 id 更新同一条通知**（原生侧 `bellNotificationId`），
/// 所以连续响铃是覆盖文案而不是堆一串通知。
///
/// 诚实说明：`x_terminal_bells` 到底按「同一条通知累积」还是「跨会话聚合」，
/// 我只从字符串本身读到它存在，没有从 smali 里读实聚合口径，这里按前者实现。
class BellNotifications {
  /// @brief 私有构造：全部能力都是静态方法。
  BellNotifications._();

  /// @brief 与端口转发共用同一个原生通知桥。
  ///
  /// （`MainActivity` 里的 MethodChannel）。
  static const MethodChannel _channel =
      MethodChannel('com.juicessh.juice_ssh_flutter/port_forwards');

  /// @brief 本次连接累计收到的响铃次数。
  static int _count = 0;

  /// @brief 当前累计的响铃次数。
  static int get count => _count;

  /// @brief 新会话开始时清零 —— 响铃计数是「这次连接」的概念。
  static void reset() => _count = 0;

  /// @brief 发一条响铃通知。
  ///
  /// 故意是同步签名：调用点就在终端的响铃回调里，
  /// 不该为了通知去 await。
  static void show({
    required String title,
    required String single,
    required String multiple,
  }) {
    _count++;
    final text = _count > 1 ? multiple.replaceFirst('%d', '$_count') : single;
    unawaited(_post(title, text));
  }

  /// @brief 把通知文案送到原生侧。
  static Future<void> _post(String title, String text) async {
    try {
      await _channel.invokeMethod<void>('bell', {'title': title, 'text': text});
    } on PlatformException {
      // 通知失败不该影响终端本身。
    } on MissingPluginException {
      // 单元测试环境没有原生侧。
    }
  }
}
