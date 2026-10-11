import 'package:flutter/services.dart';

import '../data/models.dart';

/// 端口转发常驻通知的原生桥。
///
/// 原版 JuiceSSH 每条活动转发都会挂一个通知（`gi0.smali`）：
/// 带计时器（`setUsesChronometer(true)`）、带一个停止动作
/// （`addAction`，文案是 `@string/disconnect`）。
/// 点开通知的去向由 [PortForward.openInBrowser] 决定 —— 为真就
/// `ACTION_VIEW http://localhost:<localPort>`，否则回到应用本体。
///
/// 注意 `openInBrowser` **不是**「建立后自动打开浏览器」：原版只在构造通知的
/// `contentIntent` 时读它，转发本身不会主动拉起浏览器。
class ForwardNotifications {
  ForwardNotifications._();

  static const MethodChannel _channel =
      MethodChannel('com.juicessh.juice_ssh_flutter/port_forwards');

  /// 转发 id → 通知上「停止」被按下时该做什么。
  static final Map<int, void Function()> _stoppers = <int, void Function()>{};

  static bool _attached = false;

  static void _attach() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onStopForward') {
        final id = call.arguments;
        if (id is int) _stoppers[id]?.call();
      }
      return null;
    });
  }

  /// 挂一条转发的通知。[onStop] 是通知上「停止」被按下时的回调。
  static Future<void> show(
    PortForward forward, {
    required String disconnectLabel,
    required String text,
    required void Function() onStop,
  }) async {
    final id = forward.id;
    if (id <= 0) return;
    _attach();
    _stoppers[id] = onStop;
    try {
      await _channel.invokeMethod<void>('show', <String, Object?>{
        'id': id,
        'title': forward.name,
        'text': text,
        'url': forward.openInBrowser
            ? 'http://localhost:${forward.localPort ?? 0}'
            : null,
        'disconnectLabel': disconnectLabel,
      });
    } on PlatformException {
      // 通知失败不影响转发本身。
    } on MissingPluginException {
      // 测试环境没有原生实现。
    }
  }

  /// 撤掉一条转发的通知。
  static Future<void> cancel(int forwardId) async {
    if (forwardId <= 0) return;
    _stoppers.remove(forwardId);
    try {
      await _channel.invokeMethod<void>(
        'cancel',
        <String, Object?>{'id': forwardId},
      );
    } on PlatformException {
      // 忽略。
    } on MissingPluginException {
      // 忽略。
    }
  }
}
