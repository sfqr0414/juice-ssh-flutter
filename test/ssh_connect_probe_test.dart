// 宿主机侧 SSH 连接隔离探测（第 20 轮加入）。
//
// 目的：模拟器里应用连 `10.0.2.2:2222` 时，服务端日志一律是
// `连接异常: EOFError()` —— 也就是"TCP 连上了，客户端连自己的 banner 都没发就关闭"。
// 而 UI 把这层异常统一包装成"连接超时"，真因被吞掉。
//
// 所以这里把 **应用自己的 SSH 层**（`SshConnector.connect`）拿到宿主机上直接跑：
// 直连 `127.0.0.1:2222`（该端口在宿主侧已验证可用），用内存假 `HostKeyStore` 与
// 自动同意的主机密钥回调，把真实异常原文打出来。
//
// 不碰插件：身份自带口令，所以不会走安全存储；主机密钥走内存实现，不碰数据库。
//
// 运行：flutter test test/ssh_connect_probe_test.dart
// 前置：python tools/_sshd.py 2222 --many-lines
// 没有夹具时会**自动跳过**（见 `_fixtureListening`），不会让 `flutter test` 常态变红。
// 想验协议完整性（exec/退出码）可以换成 tools/_sshd_asyncssh.py —— 但注意它的 pty 会话
// 带行缓冲，不含换行的输入会被它吞掉，验"客户端写了什么"必须用 `_sshd.py`。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_ssh_flutter/data/models.dart';
import 'package:juice_ssh_flutter/ssh/ssh_service.dart';

class _MemoryHostKeys implements HostKeyStore {
  @override
  Future<KnownHost?> find(String hostname) async => null;

  @override
  Future<void> remember(KnownHost host) async {}
}

/// 夹具是否在本机监听。没有夹具时这个用例必然失败（TCP 拒连 → `connect` 超时），
/// 但那是**缺少前置**，不是产品缺陷 —— 直接跳过，免得 `flutter test` 常态两片红、
/// 把真正的问题淹掉（本仓库只有这一个用例依赖外部进程）。
Future<bool> _fixtureListening() async {
  try {
    final socket = await Socket.connect('127.0.0.1', 2222,
        timeout: const Duration(milliseconds: 800));
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

void main() {
  test('宿主机直连探测服务器：打印真实异常', () async {
    if (!await _fixtureListening()) {
      // ignore: avoid_print
      print('PROBE 跳过：本机 2222 没有夹具，先跑 '
          'python tools/_sshd.py 2222 --many-lines');
      return;
    }
    const connection = Connection(
      nickname: 'probe',
      address: '127.0.0.1',
      port: 2222,
    );
    const identity = Identity(
      nickname: 'probe-id',
      username: 'juice',
      password: 'juice',
    );

    try {
      final session = await SshConnector.connect(
        connection: connection,
        identities: const [identity],
        hostKeyStore: _MemoryHostKeys(),
        onHostKey: (challenge) async {
          // ignore: avoid_print
          print('PROBE 主机密钥 ${challenge.hostname} ${challenge.keyType} '
              '${challenge.fingerprint} changed=${challenge.changed}');
          return HostKeyVerdict.accepted;
        },
        onPassword: (prompt, echo) async {
          // ignore: avoid_print
          print('PROBE 口令提示 $prompt');
          return 'juice';
        },
        onProgress: (message) {
          // ignore: avoid_print
          print('PROBE 进度 $message');
        },
        timeout: const Duration(seconds: 10),
      );
      // ignore: avoid_print
      print('PROBE 连接成功');
      final out = await session.execute('echo hello');
      // ignore: avoid_print
      print('PROBE 执行结果=${out.trim()}');
      await session.close();
    } catch (error, stack) {
      // ignore: avoid_print
      print('PROBE 失败: $error');
      // ignore: avoid_print
      print(stack.toString().split('\n').take(8).join('\n'));
      rethrow;
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
