"""给复刻做端到端验证用的最小 SSH 服务端。

模拟器里的应用连 `10.0.2.2:2222`（用户/口令都是 `juice`）即可。
登录后先吐一段**固定**的 ANSI 样本（颜色、粗体、下划线、反显、256 色、
光标移动、清屏），再进入一个回显循环 —— 内容固定，原版与复刻截同一屏
就能逐像素比对终端渲染。

    python tools/_sshd.py [端口]

只依赖 paramiko，不要在应用构建里用到它。

第 16 轮起加上认证/开 shell/收数据的日志：判断"客户端到底有没有真的建立会话"，
服务端这一侧必须留痕，否则截图无法区分"没连上"和"连上了但没渲染"。
"""

from __future__ import annotations

import pathlib
import socket
import sys
import threading
import time

import paramiko

USER = 'juice'
PASSWORD = 'juice'

# 一段固定的 ANSI 样本：每种属性各占一行，方便逐行量。
BANNER = (
    '\x1b[2J\x1b[H'
    '\x1b[1;37mJUICE TERMINAL SAMPLE\x1b[0m\r\n'
    '\x1b[31mred\x1b[0m \x1b[32mgreen\x1b[0m \x1b[33myellow\x1b[0m '
    '\x1b[34mblue\x1b[0m \x1b[35mmagenta\x1b[0m \x1b[36mcyan\x1b[0m\r\n'
    '\x1b[1mbold\x1b[0m \x1b[4munderline\x1b[0m \x1b[7minverse\x1b[0m '
    '\x1b[3mitalic\x1b[0m\r\n'
    '\x1b[38;5;196m256:196\x1b[0m \x1b[38;5;46m256:46\x1b[0m '
    '\x1b[38;5;21m256:21\x1b[0m \x1b[48;5;240m bg240 \x1b[0m\r\n'
    'ASCII !"#$%&\'()*+,-./0123456789:;<=>?@\r\n'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\r\n'
    '\x1b[33mjuice@sample\x1b[0m:\x1b[36m~\x1b[0m$ '
    # 末尾这个 BEL 用来验证 `terminal:bell_mode = 2`（show_notification）：
    # 客户端解析到 \a 就该发一条"Terminal Bell"通知。
    '\a'
)

# 第 348 轮：给"普通模式下能否滑屏滚动"的回归验证加 `--many-lines`。
# 没有历史时 `maxScrollExtent` 是 0，拖动什么都测不出来，所以让服务端在样本后面
# 直接多吐 60 行，制造确定的可滚历史。
if '--many-lines' in sys.argv:
    BANNER += ''.join('scroll line %02d\r\n' % i for i in range(1, 61))


# 宿主密钥**固定**下来。早期这里是 `paramiko.RSAKey.generate(2048)`，每次重启
# 服务端指纹都变，客户端于是每次都弹「Host Verification」（Public key has
# changed），端到端验证每次都要多点一次、还会掩盖真正的主机密钥相关回归。
# 现在落盘到 `.research/_host_rsa`（该目录已 gitignore，不入库）。
_HOST_KEY_PATH = (
    pathlib.Path(__file__).resolve().parent.parent / '.research' / '_host_rsa'
)


def _load_host_key() -> paramiko.RSAKey:
    if _HOST_KEY_PATH.exists():
        try:
            return paramiko.RSAKey.from_private_key_file(str(_HOST_KEY_PATH))
        except Exception as exc:  # noqa: BLE001
            print('!! 宿主密钥载入失败，改为重新生成: %r' % (exc,), flush=True)
    key = paramiko.RSAKey.generate(2048)
    _HOST_KEY_PATH.parent.mkdir(parents=True, exist_ok=True)
    key.write_private_key_file(str(_HOST_KEY_PATH))
    print('已生成并固定宿主密钥: %s' % _HOST_KEY_PATH.name, flush=True)
    return key


HOST_KEY = _load_host_key()

# 验证公钥认证用的门钥：`.research/_id_rsa` 里那把私钥对应的公钥。
# 只有这一把被接受，这样服务端日志能证明客户端用的确实是它。
AUTHORIZED_KEY = None
_key_path = pathlib.Path(__file__).resolve().parent.parent / '.research' / '_id_rsa'
if _key_path.exists():
    try:
        AUTHORIZED_KEY = paramiko.RSAKey.from_private_key_file(str(_key_path))
    except Exception as exc:  # noqa: BLE001
        print('!! 门钥载入失败: %r' % (exc,), flush=True)

# 每来一个连接分配一个短号，日志里能对上。
_counter = [0]
_lock = threading.Lock()


def _next_tag() -> str:
    with _lock:
        _counter[0] += 1
        return '#%d' % _counter[0]


class _Server(paramiko.ServerInterface):
    def __init__(self, tag: str, transport) -> None:
        self.tag = tag
        self.transport = transport
        # chanid -> (host, port)，供 accept() 之后取出来做桥接。
        self.direct_targets = {}
        # chanid -> 通道类型。paramiko 的 Channel 没有 get_kind()，
        # 只能在 check_channel_* 回调里自己记下来。
        self.kinds = {}

    def check_channel_direct_tcpip_request(self, chanid, origin, destination):
        # 客户端要经我们连到 destination（本地转发 `-L` 的每一跳）。
        self.direct_targets[chanid] = destination
        self.kinds[chanid] = 'direct-tcpip'
        print('%s >>> 直连转发请求 chanid=%s %s:%s（源自 %s:%s）'
              % (self.tag, chanid, destination[0], destination[1],
                 origin[0], origin[1]), flush=True)
        return paramiko.OPEN_SUCCEEDED

    def check_port_forward_request(self, address, port):
        """客户端要求 `-R`：由**服务器侧**监听 address:port。"""
        print('%s >>> 远端转发请求 %s:%s（将在服务器侧监听）'
              % (self.tag, address, port), flush=True)
        threading.Thread(
            target=self._listen_remote,
            args=(address, port),
            daemon=True,
        ).start()
        return True

    def _listen_remote(self, address, port) -> None:
        try:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(('127.0.0.1', port))
            listener.listen(4)
        except OSError as exc:
            print('!! %s 远端监听 %d 失败: %r' % (self.tag, port, exc), flush=True)
            return
        print('%s 已在服务器侧监听 127.0.0.1:%d' % (self.tag, port), flush=True)
        while True:
            try:
                conn, addr = listener.accept()
            except OSError:
                return
            print('%s 宿主接入 %s:%d -> 打开 forwarded-tcpip 通道'
                  % (self.tag, addr[0], addr[1]), flush=True)
            try:
                channel = self.transport.open_forwarded_tcpip_channel(
                    addr, (address, port))
            except Exception as exc:  # noqa: BLE001
                print('!! %s 打开 forwarded-tcpip 失败: %r' % (self.tag, exc), flush=True)
                conn.close()
                continue
            threading.Thread(
                target=_pump_socket_channel,
                args=(conn, channel, self.tag),
                daemon=True,
            ).start()

    def check_auth_password(self, username: str, password: str) -> int:
        ok = username == USER and password == PASSWORD
        print('%s 口令认证 user=%r pass=%r -> %s'
              % (self.tag, username, password, '成功' if ok else '失败'), flush=True)
        return paramiko.AUTH_SUCCESSFUL if ok else paramiko.AUTH_FAILED

    def check_auth_publickey(self, username: str, key) -> int:
        ok = (
            AUTHORIZED_KEY is not None
            and username == USER
            and key.get_base64() == AUTHORIZED_KEY.get_base64()
        )
        print('%s 公钥认证 user=%r type=%s -> %s'
              % (self.tag, username, key.get_name(), '成功' if ok else '失败'),
              flush=True)
        return paramiko.AUTH_SUCCESSFUL if ok else paramiko.AUTH_FAILED

    def get_allowed_auths(self, username: str) -> str:
        return 'password,publickey'

    def check_channel_request(self, kind: str, chanid: int) -> int:
        print('%s 通道请求 kind=%s' % (self.tag, kind), flush=True)
        self.kinds[chanid] = kind
        return paramiko.OPEN_SUCCEEDED

    def check_channel_pty_request(self, *args, **kwargs) -> bool:
        print('%s pty 请求 %r' % (self.tag, args[:2]), flush=True)
        return True

    def check_channel_forward_agent_request(self, channel) -> bool:
        # 真实 OpenSSH 默认 `AllowAgentForwarding yes`，会接受 `auth-agent-req@openssh.com`。
        # paramiko 的默认实现返回 False，而 dartssh2 遇到拒绝会抛 SSHChannelRequestError
        # 直接中止整次连接 —— 测试服务端必须显式接受，否则开着 `ssh:agent` 的连接全都连不上。
        # 加 `--refuse-agent-forward` 可复现"服务端拒绝"这条路径。
        refuse = '--refuse-agent-forward' in sys.argv
        print('%s >>> auth-agent-req 转发请求 -> %s'
              % (self.tag, '拒绝' if refuse else '接受'), flush=True)
        return not refuse

    def check_channel_shell_request(self, channel) -> bool:
        print('%s >>> 客户端请求 shell（会话已建立）' % self.tag, flush=True)
        return True

    def check_channel_exec_request(self, channel, command) -> bool:
        print('%s >>> 客户端请求 exec: %r' % (self.tag, command), flush=True)
        return True


def _pump_direct(channel, tag: str, destination) -> None:
    """把一条 direct-tcpip 通道与真实目标之间双向对拷。"""
    host, port = destination
    try:
        target = socket.create_connection((host, port), timeout=10)
    except OSError as exc:
        print('%s 目标 %s:%s 连不上: %r' % (tag, host, port, exc), flush=True)
        channel.close()
        return

    print('%s 转发通道已接通 %s:%s' % (tag, host, port), flush=True)

    import threading as _threading

    def copy(src, dst, closer):
        try:
            while True:
                data = src.recv(4096)
                if not data:
                    break
                print('%s 转发 %d 字节: %r' % (tag, len(data), data[:80]), flush=True)
                dst.sendall(data)
        except Exception:  # noqa: BLE001
            pass
        finally:
            try:
                closer()
            except Exception:  # noqa: BLE001
                pass

    t1 = _threading.Thread(target=copy, args=(channel, target, channel.close), daemon=True)
    t2 = _threading.Thread(target=copy, args=(target, channel, target.close), daemon=True)
    t1.start()
    t2.start()
    t1.join(60)
    t2.join(60)
    print('%s 转发通道结束' % tag, flush=True)


def _pump_socket_channel(sock: socket.socket, channel, tag: str) -> None:
    """把服务器侧接入的 socket 与一条 SSH 通道双向对拷（`-R` 用）。"""
    print('%s 远端转发通道已接通' % tag, flush=True)

    def copy(src, dst, closer):
        try:
            while True:
                data = src.recv(4096)
                if not data:
                    break
                print('%s 远端转发 %d 字节: %r' % (tag, len(data), data[:80]), flush=True)
                dst.sendall(data)
        except Exception:  # noqa: BLE001
            pass
        finally:
            try:
                closer()
            except Exception:  # noqa: BLE001
                pass

    t1 = threading.Thread(target=copy, args=(sock, channel, channel.close), daemon=True)
    t2 = threading.Thread(target=copy, args=(channel, sock, sock.close), daemon=True)
    t1.start()
    t2.start()
    t1.join(60)
    t2.join(60)
    print('%s 远端转发通道结束' % tag, flush=True)


def _probe_agent(session_channel, tag: str) -> None:
    """探测 agent 转发：客户端只有装了 agentHandler 才会接受这条通道。

    真实 sshd 正是用 `auth-agent@openssh.com` 通道回头找客户端要签名。
    这里只发 `SSH2_AGENTC_REQUEST_IDENTITIES`(11)，看有没有
    `SSH2_AGENTC_IDENTITIES_ANSWER`(12) 与公钥列表回来。
    """

    def run() -> None:
        # 等客户端把 `auth-agent-req@openssh.com` 请求发出来再开门。
        time.sleep(1.5)
        try:
            chan = session_channel.transport.open_channel(
                'auth-agent@openssh.com',
                window_size=64 * 1024,
                max_packet_size=32 * 1024,
            )
        except Exception as exc:  # noqa: BLE001
            print('%s >>> agent 通道打不开（客户端未安装转发）: %r' % (tag, exc),
                  flush=True)
            return
        chan.send(b'\x00\x00\x00\x01\x0b')  # length=1, REQUEST_IDENTITIES
        try:
            data = chan.recv(4096)
        except Exception as exc:  # noqa: BLE001
            print('%s >>> agent 通道读取失败: %r' % (tag, exc), flush=True)
            chan.close()
            return
        print('%s <<< agent 应答 %d 字节: %r' % (tag, len(data), data[:160]),
              flush=True)
        if data[:5] == b'\x00\x00\x00\x01\x0c':
            print('%s <<< 收到 IDENTITIES_ANSWER(12)，公钥数量=%d' % (tag, data[5]),
                  flush=True)
        chan.close()

    threading.Thread(target=run, daemon=True).start()


def _session_loop(channel, tag: str) -> None:
    """会话通道：先吐固定的 ANSI 样本，再回显。"""
    print('%s 已发样本横幅（%d 字节）' % (tag, len(BANNER)), flush=True)
    channel.sendall(BANNER)
    # agent 探测默认关闭：第 38 轮打开它之后，所有连接都在 banner 阶段被客户端重置。
    # 先关掉做证伪，确认症状是否随它出现（加 `--agent-probe` 才启用）。
    if '--agent-probe' in sys.argv:
        _probe_agent(channel, tag)
    if '--alt-screen' in sys.argv:
        # 备用屏 + DA1（主设备属性）查询，用来判定三件事：
        #   1. 客户端是否**只在被查询后**才回 DA 应答（不该主动发），
        #   2. 回的到底是 `ESC[?1;2c` 还是别的序列，
        #   3. 备用屏里键入的字节原样是什么（vi 就是这种模式）。
        channel.sendall(
            b'\x1b[?1049h\x1b[2J\x1b[H'
            b'ALT-SCREEN MODE (simulates vi)\r\n'
            b'line2: red green yellow blue\r\n'
            # 判别实验（第 268 轮）：备用屏里再写一段**带 SGR 彩色**的文字。
            # 彩色能显示 ⇒ 问题在"默认前景色"（默认色单元格与画布同色）；
            # 彩色也不显示 ⇒ 问题在备用屏绘制本身。
            b'\x1b[31mZZREDZZ\x1b[0m  \x1b[32mZZGREENZZ\x1b[0m\r\n'
        )
        channel.sendall(b'\x1b[24;1H-- ALT --')
        print('%s 已进备用屏(1049h)，接着发送 DA1 查询 ESC[c' % tag, flush=True)
        channel.sendall(b'\x1b[c')
        print('%s DA1 查询已发出，等客户端应答' % tag, flush=True)
    while True:
        data = channel.recv(4096)
        if not data:
            print('%s 客户端关闭通道' % tag, flush=True)
            break
        print('%s 收到 %d 字节: %r hex=%s'
              % (tag, len(data), data[:120], data[:32].hex()), flush=True)
        # 回显：把输入原样送回（`\r` 换成 CRLF，模拟终端行为）
        channel.sendall(data.replace(b'\r', b'\r\n'))


def _serve(conn: socket.socket, addr, tag: str) -> None:
    try:
        transport = paramiko.Transport(conn)
        transport.add_server_key(HOST_KEY)
        server = _Server(tag, transport)
        transport.start_server(server=server)

        # 会话通道和转发通道是**陆续**到来的：客户端打开 `-L` 转发时，
        # 会话通道仍然开着。所以这里必须持续 accept 并按类型分发，
        # 只 accept 一次会让转发通道永远排不上队。
        while transport.is_active():
            channel = transport.accept(1)
            if channel is None:
                continue
            kind = server.kinds.get(channel.get_id(), 'session')
            if kind == 'direct-tcpip':
                destination = server.direct_targets.get(
                    channel.get_id(), ('127.0.0.1', 0))
                threading.Thread(
                    target=_pump_direct,
                    args=(channel, tag, destination),
                    daemon=True,
                ).start()
                continue
            threading.Thread(
                target=_session_loop,
                args=(channel, tag),
                daemon=True,
            ).start()
    except Exception as exc:  # noqa: BLE001 - 验证脚本，出错直接打出来
        print('!! %s 连接异常: %r' % (tag, exc), flush=True)
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 2222
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('0.0.0.0', port))
    listener.listen(8)
    print('SSH 服务端已监听 0.0.0.0:%d（%s/%s）' % (port, USER, PASSWORD), flush=True)
    while True:
        try:
            conn, addr = listener.accept()
        except OSError:
            break
        tag = _next_tag()
        print('+ %s 来自 %s:%d' % (tag, addr[0], addr[1]), flush=True)
        threading.Thread(target=_serve, args=(conn, addr, tag), daemon=True).start()
        time.sleep(0.01)


if __name__ == '__main__':
    main()
