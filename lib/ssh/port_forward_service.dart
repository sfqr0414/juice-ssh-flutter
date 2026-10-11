import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'forward_notifications.dart';
import 'ssh_service.dart';

/// 一条转发占用的运行时资源。
class _RunningForward {
  _RunningForward(this.forward);

  final PortForward forward;
  final List<StreamSubscription<Object?>> subscriptions =
      <StreamSubscription<Object?>>[];
  final List<ServerSocket> listeners = <ServerSocket>[];
  final List<SSHRemoteForward> remoteForwards = <SSHRemoteForward>[];
  final List<SSHDynamicForward> socksForwards = <SSHDynamicForward>[];

  Future<void> close() async {
    final subs = List<StreamSubscription<Object?>>.of(subscriptions);
    subscriptions.clear();
    for (final sub in subs) {
      await sub.cancel();
    }
    final sockets = List<ServerSocket>.of(listeners);
    listeners.clear();
    for (final socket in sockets) {
      await socket.close();
    }
    for (final forward in remoteForwards) {
      forward.close();
    }
    remoteForwards.clear();
    for (final forward in socksForwards) {
      await forward.close();
    }
    socksForwards.clear();
  }
}

/// 端口转发的运行时。
///
/// 原版把转发挂在连接上（`portforward.connection`），连接建立后由
/// `PortForwardListAdapter$c` 这个开关做真实的建立/断开；会话断开时统一回收。
/// 这里实现同一件事：会话建立后按 [PortForward.mode] 起本地监听（`-L`）、
/// 远端监听（`-R`）或 SOCKS5（`-D`），并且**每条转发都能单独启停**，
/// 供列表页那个开关使用。
///
/// 三种模式的字段约定（与 `PortForward.t(Context)` 的文案一致）：
///
/// * [PortForwardMode.local] —— 在本机 `127.0.0.1:localPort` 监听，
///   每条接入的连接经 SSH 服务器连到 `host:remotePort`；
/// * [PortForwardMode.remote] —— 请求服务器在 `host:remotePort` 监听，
///   接入的连接转回本机 `127.0.0.1:localPort`；
/// * [PortForwardMode.dynamic] —— 在本机 `127.0.0.1:localPort` 起 SOCKS5。
///
/// 原版接受 Android 的安全限制，动态转发不会注册成系统级代理，调用方需要
/// 自己把代理指向 `127.0.0.1:<port>`。
class PortForwardService extends ChangeNotifier {
  PortForwardService({
    required this.session,
    required this.connection,
    this.disconnectLabel = 'Disconnect',
  });

  /// 已经建立的 SSH 会话；转发通道都从它上面拨。
  final JuiceSshSession session;

  /// 转发所属的连接，`host` 缺省时用它自己的地址。
  final Connection connection;

  /// 通知上「停止」动作的文案（原版是 `@string/disconnect`）。
  ///
  /// 由界面层注入（只有那里拿得到本地化文案），默认英文。
  String disconnectLabel;

  /// 正在转发的条目，**按主键**索引。
  ///
  /// 不能用 `Map<PortForward, _>`：列表页的实例是从数据库重新读出来的，
  /// 与这里持有的实例不是同一个对象，而 `Map` 默认按对象标识比较 ——
  /// 那样「这条转发现在通没通」永远查不到，开关会一直显示关闭。
  final Map<int, _RunningForward> _running = <int, _RunningForward>{};

  var _closed = false;

  /// 当前处于活动状态的转发，用于列表页的开关状态。
  List<PortForward> get active =>
      List<PortForward>.unmodifiable(_running.values.map((r) => r.forward));

  bool get isClosed => _closed;

  /// 这一条是否正在转发。
  bool isActive(PortForward forward) => _running.containsKey(forward.id);

  /// 启动一条转发，成功返回 true。
  Future<bool> start(PortForward forward) async {
    if (_closed || _running.containsKey(forward.id)) return false;
    final running = _RunningForward(forward);
    try {
      final started = switch (forward.mode) {
        PortForwardMode.local => await _startLocal(forward, running),
        PortForwardMode.remote => await _startRemote(forward, running),
        PortForwardMode.dynamic => await _startDynamic(forward, running),
      };
      if (!started) {
        await running.close();
        return false;
      }
      _running[forward.id] = running;
      _publishNotification(forward);
      notifyListeners();
      return true;
    } catch (_) {
      // 端口被占用、服务器拒绝等都属于"这条转发起不来"，不影响会话本身。
      await running.close();
      return false;
    }
  }

  /// 停掉一条正在转发的项。
  Future<void> stop(PortForward forward) async {
    final running = _running.remove(forward.id);
    if (running == null) return;
    await running.close();
    unawaited(ForwardNotifications.cancel(forward.id));
    notifyListeners();
  }

  /// 开关：正在转发就停掉，否则启动。返回操作后是否处于转发状态。
  Future<bool> toggle(PortForward forward) async {
    if (isActive(forward)) {
      await stop(forward);
      return false;
    }
    return start(forward);
  }

  /// 批量启动，返回成功条数。
  Future<int> startAll(Iterable<PortForward> forwards) async {
    var started = 0;
    for (final forward in forwards) {
      if (await start(forward)) started++;
    }
    return started;
  }

  /// 关闭所有转发。会话断开时必须调用。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    final all = List<_RunningForward>.of(_running.values);
    _running.clear();
    for (final running in all) {
      await running.close();
      unawaited(ForwardNotifications.cancel(running.forward.id));
    }
    notifyListeners();
  }

  /// 原版每条活动转发都挂一个常驻通知：带计时器 + 一个停止动作
  /// （`gi0.smali`）。通知的 `contentIntent` 由 `openInBrowser` 决定。
  void _publishNotification(PortForward forward) {
    unawaited(
      ForwardNotifications.show(
        forward,
        disconnectLabel: disconnectLabel,
        text: _describe(forward),
        onStop: () => unawaited(stop(forward)),
      ),
    );
  }

  /// 通知副标题：把这条转发在做什么写清楚。
  String _describe(PortForward forward) {
    final local = 'localhost:${forward.localPort ?? 0}';
    final remote = '${_effectiveHost(forward)}:${forward.remotePort ?? 0}';
    return switch (forward.mode) {
      PortForwardMode.local => '$local → $remote',
      PortForwardMode.remote => '$remote → $local',
      PortForwardMode.dynamic => 'SOCKS5 $local',
    };
  }

  // ------------------------------------------------------------ 三种模式 --

  /// `-L`：本机监听，接入即经服务器拨到 `host:remotePort`。
  Future<bool> _startLocal(
    PortForward forward,
    _RunningForward running,
  ) async {
    final localPort = forward.localPort ?? 0;
    final remotePort = forward.remotePort ?? 0;
    if (localPort <= 0 || remotePort <= 0) return false;
    if (_running.values
        .any((other) => other.listeners.any((s) => s.port == localPort))) {
      return false;
    }

    final host = _effectiveHost(forward);
    final listener = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      localPort,
    );
    running.listeners.add(listener);
    running.subscriptions.add(
      listener.listen(
        (Socket socket) {
          socket.setOption(SocketOption.tcpNoDelay, true);
          unawaited(_pumpLocal(socket, host, remotePort, running));
        },
        onError: (Object _) {},
        cancelOnError: false,
      ),
    );
    return true;
  }

  /// 把一条本地接入的 socket 与一条转发通道对接起来。
  Future<void> _pumpLocal(
    Socket socket,
    String host,
    int port,
    _RunningForward running,
  ) async {
    SSHForwardChannel channel;
    try {
      channel = await session.dialForward(host, port);
    } catch (_) {
      socket.destroy();
      return;
    }
    _bridge(socket, channel, running);
  }

  /// `-R`：请服务器监听，接入的连接转回本机 `localPort`。
  Future<bool> _startRemote(
    PortForward forward,
    _RunningForward running,
  ) async {
    final remotePort = forward.remotePort ?? 0;
    final localPort = forward.localPort ?? 0;
    if (remotePort <= 0 || localPort <= 0) return false;

    final host = _effectiveHost(forward);
    final bound = await session.requestRemoteForward(
      host: host,
      port: remotePort,
    );
    if (bound == null) return false;

    running.remoteForwards.add(bound);
    running.subscriptions.add(
      bound.connections.listen(
        (SSHForwardChannel channel) {
          unawaited(_pumpRemote(channel, localPort, running));
        },
        onError: (Object _) {},
        cancelOnError: false,
      ),
    );
    return true;
  }

  /// 把服务器转回来的一条通道接到本机 `localPort` 上的服务。
  Future<void> _pumpRemote(
    SSHForwardChannel channel,
    int localPort,
    _RunningForward running,
  ) async {
    Socket socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, localPort);
    } catch (_) {
      channel.destroy();
      return;
    }
    _bridge(socket, channel, running);
  }

  /// `-D`：本机 SOCKS5，由 dartssh2 自己接管。
  Future<bool> _startDynamic(
    PortForward forward,
    _RunningForward running,
  ) async {
    final localPort = forward.localPort ?? 0;
    final socks = await session.startSocksProxy(
      bindPort: localPort > 0 ? localPort : null,
    );
    running.socksForwards.add(socks);
    return true;
  }

  // -------------------------------------------------------------- 工具 --

  /// 双向对拷。任一侧结束就关掉另一侧，避免留下半开连接。
  void _bridge(
    Socket socket,
    SSHForwardChannel channel,
    _RunningForward running,
  ) {
    running.subscriptions.add(
      socket.listen(
        (List<int> data) => channel.sink.add(data),
        // 这里必须关 **sink** 而不是 `channel.close()`：
        // `SSHForwardChannel.sink` 是 StreamController，数据是异步流进底层通道的，
        // 直接关通道会让"还在排队"的字节丢掉。`echo x | nc` 这类发完就关的
        // 客户端每次都会踩到这一点（现象是通道建起来了但一个字节都不过去）。
        onDone: () => unawaited(channel.sink.close()),
        onError: (Object _) => channel.destroy(),
        cancelOnError: true,
      ),
    );
    running.subscriptions.add(
      channel.stream.listen(
        (Uint8List data) => socket.add(data),
        onDone: () => socket.destroy(),
        onError: (Object _) => socket.destroy(),
        cancelOnError: true,
      ),
    );
  }

  /// 与 `PortForward.t(Context)` 一致：`host` 为空时用连接自身的地址。
  String _effectiveHost(PortForward forward) {
    final host = forward.host ?? '';
    return host.isNotEmpty ? host : connection.address;
  }
}
