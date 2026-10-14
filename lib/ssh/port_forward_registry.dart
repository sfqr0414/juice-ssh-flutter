import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'port_forward_service.dart';

/// @brief 活动会话的端口转发服务注册表。
///
/// 端口转发列表页（`AddressBook` 的 Port Forwards 标签）需要在**别的路由**上
/// 知道自己那条转发现在通没通，原版是靠 `PortForwardListAdapter` 持有
/// `Service`/`Connection` 引用 + `g(PortForward, boolean)` 刷新开关状态做到的。
/// Flutter 这边用一个进程级注册表把「连接 id → 该连接的转发服务」串起来，
/// 并作为 [ChangeNotifier] 让列表页能重建。
///
/// 生命周期：会话建立时由 `TerminalSessionController` 注册，
/// 会话断开时注销；注册表本身不持有会话。
class PortForwardRegistry extends ChangeNotifier {
  /// @brief 私有构造：单例，只能内部创建。
  PortForwardRegistry._();

  /// @brief 进程级单例。
  static final PortForwardRegistry instance = PortForwardRegistry._();

  /// @brief 连接 id → 该连接当前的转发服务。
  final Map<int, PortForwardService> _byConnection = <int, PortForwardService>{};

  /// @brief 某个连接当前是否有活动会话。
  bool hasSession(int? connectionId) =>
      connectionId != null && _byConnection.containsKey(connectionId);

  /// @brief 某个连接的转发服务；没有活动会话时为 null。
  PortForwardService? serviceFor(int? connectionId) =>
      connectionId == null ? null : _byConnection[connectionId];

  /// @brief 这一条转发现在是否正在转发。
  bool isActive(PortForward forward) =>
      serviceFor(forward.connectionId)?.isActive(forward) ?? false;

  /// @brief 注册某连接的转发服务，并转发它的变更通知。
  void register(int connectionId, PortForwardService service) {
    final previous = _byConnection[connectionId];
    if (identical(previous, service)) return;
    previous?.removeListener(notifyListeners);
    _byConnection[connectionId] = service;
    service.addListener(notifyListeners);
    notifyListeners();
  }

  /// @brief 注销某连接的转发服务。
  void unregister(int connectionId, PortForwardService service) {
    if (!identical(_byConnection[connectionId], service)) return;
    _byConnection.remove(connectionId);
    service.removeListener(notifyListeners);
    notifyListeners();
  }
}
