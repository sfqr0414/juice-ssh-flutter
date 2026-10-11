import 'package:flutter/foundation.dart';

import 'terminal_session.dart';

/// 进程级的活动会话宿主。
///
/// 原版 JuiceSSH 把 SSH 会话放在前台 Service 里，终端界面只是「附着」到会话上：
/// 返回键选「保持后台」之后界面销毁而会话继续跑，端口转发也继续工作 ——
/// 这正是通讯录里那个端口转发开关能生效的前提。
///
/// 本项目原先由 `TerminalPage` 的 State 私有持有会话控制器，路由一 pop 就被
/// `dispose()` 掉，「保持后台」是假的。这里把持有权搬到进程级单例：
/// 页面只负责**附着/脱离**，会话由 [acquire] 建、由 [close] 回收。
class SessionHost extends ChangeNotifier {
  SessionHost._();

  static final SessionHost instance = SessionHost._();

  final Map<int, TerminalSessionController> _sessions =
      <int, TerminalSessionController>{};

  /// 当前进程里活着的会话（连接 id → 控制器）。
  Map<int, TerminalSessionController> get sessions =>
      Map<int, TerminalSessionController>.unmodifiable(_sessions);

  /// 某个连接当前的会话；没有则为 null。
  TerminalSessionController? operator [](int? connectionId) =>
      connectionId == null ? null : _sessions[connectionId];

  /// 取某个连接的活动会话；没有就调用 [create] 新建一个。
  ///
  /// 返回 `created` 表明这次是不是新建 —— 页面据此决定要不要发起建连
  /// （重新附着到一个已经在跑的会话时不应该再连一次）。
  ({TerminalSessionController controller, bool created}) acquire(
    int connectionId,
    TerminalSessionController Function() create,
  ) {
    final existing = _sessions[connectionId];
    if (existing != null) {
      return (controller: existing, created: false);
    }
    final controller = create();
    _sessions[connectionId] = controller;
    controller.addListener(notifyListeners);
    notifyListeners();
    return (controller: controller, created: true);
  }

  /// 主动断开并回收某个连接的会话。
  Future<void> close(int connectionId) async {
    final controller = _sessions.remove(connectionId);
    if (controller == null) return;
    controller.removeListener(notifyListeners);
    notifyListeners();
    await controller.disconnect();
    controller.dispose();
  }

  /// 回收全部会话（测试或退出时用）。
  Future<void> closeAll() async {
    for (final id in List<int>.of(_sessions.keys)) {
      await close(id);
    }
  }
}
