import 'package:flutter/services.dart';

/// 音量键改字号的原生通道。
///
/// 原版 `TerminalEmulatorActivity.dispatchKeyEvent` 在终端页里把 keycode 24/25
/// 变成字号 +1 / -1（见 `docs/terminal-behaviour-spec.md` 里 `terminal:font_size`
/// 那一行），并且**吃掉**事件，所以系统音量条不会动。Flutter 侧拿不到这个拦截点，
/// 因此由原生 `MainActivity.dispatchKeyEvent` 转发过来。
///
/// 只在终端页声明"我在前台"时才会拦截，这样连接列表等页面里音量键仍然是正常的。
class HardwareKeys {
  const HardwareKeys._();

  static const MethodChannel _channel =
      MethodChannel('com.juicessh.juice_ssh_flutter/hardware_keys');

  static void Function(int delta)? _onVolumeKey;

  /// 告诉原生侧当前是否处于终端页。原生侧据此决定要不要拦截音量键。
  static Future<void> setVolumeKeysActive(bool active) async {
    try {
      await _channel.invokeMethod<void>(
        'setActive',
        <String, Object?>{'active': active},
      );
    } on PlatformException {
      // 原生侧未注册（例如单元测试环境）时静默忽略。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// 注册音量键回调；传 null 取消注册。
  static void handleVolumeKey(void Function(int delta)? handler) {
    _onVolumeKey = handler;
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey') {
        _onVolumeKey?.call((call.arguments as int?) ?? 0);
      }
      return null;
    });
  }
}
