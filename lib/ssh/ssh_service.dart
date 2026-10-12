import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../data/juice_database.dart';
import '../data/models.dart';

/// 主机密钥的确认结果。对应原版「主机密钥已被拒绝 / Host key rejected」这条路径。
enum HostKeyVerdict {
  /// 首次见到该主机密钥，用户或策略选择信任
  accepted,

  /// 用户拒绝，或密钥与已知记录不符
  rejected,
}

/// 主机密钥确认请求。界面层据此弹出确认框。
class HostKeyChallenge {
  const HostKeyChallenge({
    required this.hostname,
    required this.keyType,
    required this.fingerprint,
    required this.changed,
    this.previousFingerprint,
  });

  final String hostname;

  /// 例如 ssh-ed25519、ssh-rsa、ecdsa-sha2-nistp256
  final String keyType;

  /// OpenSSH 风格的 SHA256 指纹，形如 `SHA256:AbC...`
  final String fingerprint;

  /// true 表示该主机此前记录过密钥，但这次收到的密钥不同 —— 中间人风险。
  final bool changed;

  /// 变更前的指纹，仅在 [changed] 为 true 时有值。
  final String? previousFingerprint;

  /// 对应原版 DEX 里的 `Got an unseen host key for ` / `Got a host key change for `。
  bool get isUnseen => !changed;
}

/// 已知主机存储的抽象，便于把 SSH 层与数据库解耦。
abstract class HostKeyStore {
  Future<KnownHost?> find(String hostname);

  Future<void> remember(KnownHost host);
}

/// 用 SQLite 实现的主机密钥存储。
class DatabaseHostKeyStore implements HostKeyStore {
  DatabaseHostKeyStore(this._db);

  final JuiceDatabase _db;

  @override
  Future<KnownHost?> find(String hostname) => _db.knownHost(hostname);

  @override
  Future<void> remember(KnownHost host) async {
    await _db.saveKnownHost(host);
  }
}

/// 密码 / 交互式提问的回调。返回 null 表示跳过该认证方式。
typedef CredentialPrompt = Future<String?> Function(String prompt, bool echo);

/// 主机密钥确认回调。
typedef HostKeyConfirm = Future<HostKeyVerdict> Function(HostKeyChallenge challenge);

/// 连接过程中的进度反馈，供界面显示 "connecting.xml" 里的提示文案。
typedef ProgressReport = void Function(String message);

/// 一个已建立的 SSH 会话。
///
/// 把 dartssh2 的 `SSHClient` + `SSHSession` 包在一起，因为原版的会话概念
/// 同时包含"连接"和"远端 shell"两层：断开连接时两者都要清理。
class JuiceSshSession {
  JuiceSshSession._(this._client, this._session, this._encoder);

  final SSHClient _client;
  final SSHSession _session;
  final Converter<String, List<int>> _encoder;

  bool _closed = false;

  bool get isClosed => _closed || _client.isClosed;

  /// 远端产生的原始字节流（pty 合并了 stdout 与 stderr）。
  Stream<Uint8List> get output => _session.stdout;

  /// 会话结束（远端 shell 退出或连接断开）。
  Future<void> get done => _session.done;

  /// 把用户输入写回远端。
  void write(String data) {
    if (_closed) return;
    final bytes = _encoder.convert(data);
    _session.write(Uint8List.fromList(bytes));
  }

  /// 写入任意字节，供额外键行发送控制序列使用。
  void writeBytes(List<int> bytes) {
    if (_closed) return;
    _session.write(Uint8List.fromList(bytes));
  }

  /// 通知远端终端尺寸变化。对应原版 `TerminalView.OnResizeListener`。
  void resize(int columns, int rows, {int pixelWidth = 0, int pixelHeight = 0}) {
    if (_closed) return;
    _session.resizeTerminal(columns, rows, pixelWidth, pixelHeight);
  }

  /// 在会话中执行一条命令并取得输出，用于 Snippet 与公钥安装脚本。
  Future<String> execute(String command) async {
    if (_closed) throw const SshDisconnected('会话已关闭');
    final session = await _client.execute(command);
    final output = await session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    session.close();
    return output;
  }

  /// 拨通一条到远端 [remoteHost]:[remotePort] 的转发通道（相当于 `-L` 的单条连接）。
  ///
  /// 注意 dartssh2 的 `forwardLocal` 返回的是**一条已建立的转发连接**，
  /// 不是监听套接字。要实现 `-L`，调用方需要自己起本地 `ServerSocket`，
  /// 每来一条连接就调用本方法拨一条通道并把两边对接起来 —— 这也是
  /// dartssh2 自己的 `forwardDynamic` 内部的做法。该逻辑在
  /// `PortForwardService` 里。
  Future<SSHForwardChannel> dialForward(
    String remoteHost,
    int remotePort, {
    String localHost = '127.0.0.1',
    int localPort = 0,
  }) =>
      _client.forwardLocal(
        remoteHost,
        remotePort,
        localHost: localHost,
        localPort: localPort,
      );

  /// 请求远端监听 [host]:[port] 并把接入的连接转回本地（相当于 `-R`）。
  ///
  /// 返回远端实际分配的端口；失败时返回 null。
  Future<SSHRemoteForward?> requestRemoteForward({
    String? host,
    int? port,
  }) =>
      _client.forwardRemote(host: host, port: port);

  /// 启动本地 SOCKS5 代理（相当于 `-D`）。
  ///
  /// 原版在中文提示里明确说明：受 Android 安全限制，动态转发**不会**
  /// 成为系统级代理，应用需要手动指向 `127.0.0.1:<port>`。
  Future<SSHDynamicForward> startSocksProxy({
    String bindHost = '127.0.0.1',
    int? bindPort,
  }) =>
      _client.forwardDynamic(bindHost: bindHost, bindPort: bindPort);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _session.close();
    } catch (_) {
      // 会话可能已被远端关闭，忽略。
    }
    try {
      await _client.close();
    } catch (_) {
      // 同上。
    }
  }
}

/// 建立 SSH 会话。
///
/// 与原版一致的一点：一条连接可以挂多个身份，登录时**按顺序逐个尝试**，
/// 直到某个身份通过认证。dartssh2 在单条连接上只尝试一次密码认证
/// （失败即把 password 方法标记为已穷尽），因此这里对每个候选身份
/// 重新建连来复现该语义。
class SshConnector {
  /// 进程内的密码缓存（键 `user@host`）。第 270 轮用户实测："常用"快速连接第一次
  /// 输了密码进了终端，下一次再连**仍然要求输密码**；预期是记住密码直接进终端。
  /// 只留在内存里（不落 SQLite，避免明文写盘）；服务器改密码时重启应用会重新提示。
  static final Map<String, String> _passwordCache = {};

  const SshConnector._();

  /// 客户端标识。原版由原生 libssh 发布，具体字符串静态读不到，
  /// 这里用应用名 + 版本，属**推断值**。
  static const String clientIdent = 'JuiceSSH_3.2.2';

  /// 判断是否为"凭据不对"。
  ///
  /// 只认 [SSHAuthFailError]（所有认证方式都试完仍失败）。
  /// [SSHAuthAbortError] 表示认证因网络等外部原因中断，不该换下一个身份重试。
  static bool _isAuthFailure(Object error) => error is SSHAuthFailError;

  /// 尝试用 [identities]（按给定顺序）建立到 [connection] 的会话。
  ///
  /// * [onHostKey] 负责确认主机密钥；返回 [HostKeyVerdict.rejected] 会中止连接。
  /// * [onPassword] 在没有可用身份、或服务端只接受密码时被调用，
  ///   用于现场询问密码。
  /// * [onProgress] 用于把连接阶段反馈给界面。
  static Future<JuiceSshSession> connect({
    required Connection connection,
    required List<Identity> identities,
    required HostKeyStore hostKeyStore,
    required HostKeyConfirm onHostKey,
    required CredentialPrompt onPassword,
    ProgressReport? onProgress,
    String terminalType = 'xterm-256color',
    int columns = 80,
    int rows = 24,
    bool useUtf8 = true,
    bool disableHostKeyVerification = false,
    Duration timeout = const Duration(seconds: 30),
    bool agentForwarding = false,
  }) async {
    // 候选凭据顺序：先是带私钥的身份（公钥认证），再是带密码的身份。
    // 原版也是先试密钥再试密码。
    final ordered = <Identity>[
      ...identities.where((identity) => identity.hasPrivateKey),
      ...identities.where((identity) => !identity.hasPrivateKey && identity.hasPassword),
    ];

    Object? lastError;

    Future<JuiceSshSession> attempt({
      // 调用方传进来的就是 dartssh2 的 `SSHKeyPair`（见下方 `SSHKeyPair.fromPem`），
      // 这里如实收窄类型，好把它直接交给 `SSHKeyPairAgent` 做 agent 转发。
      List<SSHKeyPair> keys = const [],
      String? password,
      String? usernameOverride,
      // 服务端可能拒绝 `auth-agent-req@openssh.com`（例如 `AllowAgentForwarding no`），
      // 此时 dartssh2 会抛错中止**整次连接**。转发只是锦上添花，会话不该因此失败，
      // 所以调用方被拒后会带着 `forwardAgent: false` 重试一次。
      bool forwardAgent = true,
    }) async {
      final username = usernameOverride ??
          ordered
              .map((identity) => identity.username)
              .firstWhere((value) => (value ?? '').isNotEmpty,
                  orElse: () => null) ??
          // 兜底：没有任何带凭据的身份时，仍要从 [identities] 里取用户名。
          // Quick Connect 输入的 `user@host` 就是这种情况——原版把用户名挂在一个
          // 临时身份（`Connection.temporaryQuickConnectIdentity`）上带进来。
          // 少了这一步会话会用空用户名认证，永远连不上。
          identities
              .map((identity) => identity.username)
              .firstWhere((value) => (value ?? '').isNotEmpty,
                  orElse: () => null) ??
          '';

      onProgress?.call('正在连接 ${connection.address}:${connection.port}');

      final socket = await SSHSocket.connect(
        connection.address,
        connection.port,
        timeout: timeout,
      );

      String? passwordUsed = password;

      final client = SSHClient(
        socket,
        username: username,
        identities: keys.isEmpty ? null : keys,
        // `ssh:agent`：原版把本机身份"转发"给服务端使用 —— 服务端之后可以通过
        // `auth-agent@openssh.com` 通道向客户端索取公钥列表和签名。
        // dartssh2 只在 `agentHandler != null` 时才发出 `auth-agent-req@openssh.com`
        // 通道请求，并用这个 handler 应答服务端的 identities / sign 请求。
        // `forwardAgent` 为 false 时保持 `agentHandler` 为空：dartssh2 就不会发出
        // 转发请求，服务端拒绝过的路径也不会再被走一遍。
        agentHandler: forwardAgent && agentForwarding && keys.isNotEmpty
            ? SSHKeyPairAgent(keys, comment: 'JuiceSSH')
            : null,
        ident: clientIdent,
        disableHostkeyVerification: disableHostKeyVerification,
        onVerifyHostKey: (type, fingerprintBytes) async {
          if (disableHostKeyVerification) return true;
          final fingerprint = utf8.decode(fingerprintBytes, allowMalformed: true);
          final known = await hostKeyStore.find(connection.address);
          if (known != null && known.fingerprint == fingerprint) {
            return true;
          }
          final challenge = HostKeyChallenge(
            hostname: connection.address,
            keyType: type,
            fingerprint: fingerprint,
            changed: known != null,
            previousFingerprint: known?.fingerprint,
          );
          final verdict = await onHostKey(challenge);
          if (verdict == HostKeyVerdict.rejected) return false;
          await hostKeyStore.remember(
            KnownHost(
              id: known?.id ?? 0,
              hostname: connection.address,
              key: '',
              type: type,
              fingerprint: fingerprint,
            ),
          );
          return true;
        },
        onPasswordRequest: () async {
          if (passwordUsed != null) {
            final value = passwordUsed;
            passwordUsed = null;
            return value;
          }
          // 已经在这个进程里输过密码 → 直接复用，不再弹窗（用户要求：
          // "下一次点'常用'快速连接不再要求输入密码，直接进终端"）。
          final cacheKey = '$username@${connection.address}';
          final cached = SshConnector._passwordCache[cacheKey];
          if (cached != null) return cached;
          final answer = await onPassword(
              '请输入 $username@${connection.address} 的密码', false);
          if (answer != null && answer.isNotEmpty) {
            SshConnector._passwordCache[cacheKey] = answer;
          }
          return answer;
        },
        onUserInfoRequest: (request) async {
          // 键盘交互式认证，原版用它支持两步验证（Google Authenticator 等）。
          // 提示语优先用服务端给的 instruction，为空时退回单条 prompt 文本，
          // 这样两步验证的提示能原样呈现。
          final answers = <String>[];
          for (final prompt in request.prompts) {
            final label = request.instruction.trim().isNotEmpty &&
                    request.prompts.length == 1
                ? request.instruction
                : prompt.promptText;
            final answer = await onPassword(label, prompt.echo);
            if (answer == null) return null;
            answers.add(answer);
          }
          return answers;
        },
      );

      onProgress?.call('正在进行主机密钥交换');
      await client.authenticated.timeout(timeout);

      onProgress?.call('正在打开终端');
      final session = await client.shell(
        pty: SSHPtyConfig(
          type: terminalType,
          width: columns,
          height: rows,
        ),
      );

      if (agentForwarding) {
        // 真正的转发由上面构造 `SSHClient` 时的 `agentHandler` 安装：
        // dartssh2 会发出 `auth-agent-req@openssh.com`，并在服务端打开
        // `auth-agent@openssh.com` 通道时代入 handler 应答。
        onProgress?.call('已请求 SSH Agent 转发');
      }

      return JuiceSshSession._(
        client,
        session,
        useUtf8 ? const Utf8Encoder() : const Latin1Encoder(),
      );
    }

    // 没有任何身份时，直接用密码认证（原版会弹出密码框）。
    if (ordered.isEmpty) {
      try {
        return await attempt(usernameOverride: null);
      } catch (error) {
        throw SshFailure.from(error, connection);
      }
    }

    for (final identity in ordered) {
      try {
        if (identity.hasPrivateKey) {
          final pairs = SSHKeyPair.fromPem(
            identity.privateKey!,
            (identity.privateKeyPassword ?? '').isEmpty
                ? null
                : identity.privateKeyPassword,
          );
          try {
            return await attempt(
              keys: pairs,
              usernameOverride: identity.username,
            );
          } catch (error) {
            // 只针对"服务端拒绝 agent 转发"这一种情况降级重试，其它错误原样抛给外层，
            // 交给 `_isAuthFailure` / `SshFailure` 的既有分类逻辑处理。
            final text = '$error'.toLowerCase();
            if (error is! SSHChannelRequestError ||
                !text.contains('agent') ||
                !text.contains('forward')) {
              rethrow;
            }
            onProgress?.call('服务端拒绝了 SSH Agent 转发，改为不转发重试');
            return await attempt(
              keys: pairs,
              usernameOverride: identity.username,
              forwardAgent: false,
            );
          }
        }
        return await attempt(
          password: identity.password,
          usernameOverride: identity.username,
        );
      } catch (error) {
        if (_isAuthFailure(error)) {
          lastError = error;
          onProgress?.call('身份「${identity.nickname}」认证被拒绝，尝试下一个');
          continue;
        }
        throw SshFailure.from(error, connection);
      }
    }

    // 所有身份都失败：给最后一次机会，现场询问密码。
    // 这也对应原版在密钥认证失败后回退到密码提示的行为。
    try {
      return await attempt();
    } catch (error) {
      throw SshFailure.from(lastError ?? error, connection);
    }
  }
}

/// 面向界面的连接失败信息。
///
/// 原版在 DEX 里有几条固定文案：`Got an unseen host key for `、
/// `Got a host key change for `、`Failed saving host key`，
/// 以及中文的「主机密钥已被拒绝」。这里把底层异常归类到它们。
class SshFailure implements Exception {
  const SshFailure(this.kind, this.message, {this.cause});

  final SshFailureKind kind;
  final String message;
  final Object? cause;

  factory SshFailure.from(Object error, Connection connection) {
    // dartssh2 在 onVerifyHostKey 返回 false 时抛 SSHHostkeyError，
    // 对应原版的中文文案「主机密钥已被拒绝」。
    if (error is SSHHostkeyError || error is HostKeyRejected) {
      return SshFailure(
        SshFailureKind.hostKeyRejected,
        '主机密钥已被拒绝',
        cause: error,
      );
    }
    if (error is SSHAuthFailError || error is SSHAuthAbortError) {
      return SshFailure(
        SshFailureKind.authentication,
        '认证失败：无法使用提供的身份登录 ${connection.address}',
        cause: error,
      );
    }
    if (error is TimeoutException) {
      return SshFailure(
        SshFailureKind.timeout,
        '连接超时：${connection.address}:${connection.port}',
        cause: error,
      );
    }
    return SshFailure(
      SshFailureKind.network,
      '无法连接到 ${connection.address}:${connection.port}（$error）',
      cause: error,
    );
  }

  @override
  String toString() => message;
}

enum SshFailureKind { hostKeyRejected, authentication, timeout, network }

/// 会话已关闭时执行操作。
class SshDisconnected implements Exception {
  const SshDisconnected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 主机密钥被拒绝。
class HostKeyRejected implements Exception {
  const HostKeyRejected(this.hostname);

  final String hostname;

  @override
  String toString() => '主机密钥已被拒绝：$hostname';
}
