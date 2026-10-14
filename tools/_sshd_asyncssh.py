"""高保真 SSH 夹具服务端（取代手写的 `_sshd.py`）。

为什么换：`_sshd.py` 是直接拿 paramiko 手搓的，保真度不够 —— 它能完成认证，却
**不回应 `exec` 请求**（客户端 `session.execute('echo hello')` 永久挂住），而且在模拟器
场景下出现过"服务端认证成功、客户端 `authenticated` 却不完成"的怪状，把排查引向
网络与 dartssh2。改用 `asyncssh`（纯 Python、成熟实现）后，密钥交换 / 认证 /
通道请求 / pty / window-change / exec 的退出状态全部由库负责，夹具不再是变量。

CLI 与 `_sshd.py` 保持一致，测试脚本可以互换：

    python tools/_sshd_asyncssh.py 2222 --many-lines [--alt-screen] [--mouse-tracking]

* `--many-lines`：横幅后追加 60 行，保证主屏有回滚余量（滚动类断言因此不空洞）；
* `--alt-screen`：横幅之后再进备用屏（`ESC [ ?1049h`），模拟 htop/vim；
* `--mouse-tracking`：发 `ESC [ ?1002h`，模拟开了鼠标上报的交互程序。

收到的每个输入数据块都会以 `收到 N 字节: repr hex=...` 打到 stdout —— 用来核验
"鼠标上报模式下滑动是否真的转成了 `ESC [ M <code+32> <col+32> <row+32>`"。
"""

import asyncio
import sys

import asyncssh

ARGS = sys.argv[1:]
PORT = int(ARGS[0]) if ARGS and ARGS[0].isdigit() else 2222
MANY_LINES = '--many-lines' in ARGS
ALT_SCREEN = '--alt-screen' in ARGS
MOUSE_TRACKING = '--mouse-tracking' in ARGS

# 固定 ANSI 样本：与 `_sshd.py` 里那份等价，保证既有断言（颜色、备用屏）继续成立。
BANNER = (
    '\x1b[0m\x1b[1;32mjuice@fixture\x1b[0m:\x1b[1;34m~\x1b[0m$ '
    'echo hello\r\n'
    'hello\r\n'
    '\x1b[31mRED\x1b[0m \x1b[32mGREEN\x1b[0m \x1b[33mYELLOW\x1b[0m '
    '\x1b[34mBLUE\x1b[0m \x1b[35mMAGENTA\x1b[0m \x1b[36mCYAN\x1b[0m\r\n'
)
if MANY_LINES:
    BANNER += ''.join(
        'line %03d: the quick brown fox jumps over the lazy dog\r\n' % i
        for i in range(1, 61)
    )

HOST_KEY_PATH = None


class FixtureServer(asyncssh.SSHServer):
    """口令认证 `juice` / `juice`，与 `_sshd.py` 相同。"""

    def begin_auth(self, username: str) -> bool:
        return True

    def password_auth_supported(self) -> bool:
        return True

    def validate_password(self, username: str, password: str) -> bool:
        ok = username == 'juice' and password == 'juice'
        print("认证 user=%r pass=%r -> %s" % (username, password, '成功' if ok else '失败'),
              flush=True)
        return ok


async def handle_client(process: asyncssh.SSHServerProcess) -> None:
    """shell 与 exec 共用入口。"""
    if process.command:
        # exec 请求：必须给出输出与退出状态，否则客户端 `execute()` 会永久等待
        # （这正是旧夹具的坑）。
        print('>>> exec: %r' % process.command, flush=True)
        process.stdout.write('hello\n')
        process.exit(0)
        return

    print('>>> 客户端请求 shell，会话已建立', flush=True)
    process.stdout.write(BANNER)
    if MOUSE_TRACKING:
        process.stdout.write('\x1b[?1002h')
        print('已开鼠标上报 ?1002h', flush=True)
    if ALT_SCREEN:
        process.stdout.write(
            '\x1b[?1049h\x1b[2J\x1b[H'
            'ALT-SCREEN MODE (simulates vi)\r\n'
            'line2: red green yellow blue\r\n'
            '\x1b[31mZZREDZZ\x1b[0m  \x1b[32mZZGREENZZ\x1b[0m\r\n'
        )
        print('已进备用屏 1049h', flush=True)

    while True:
        data = await process.stdin.read(4096)
        if not data:
            break
        raw = data.encode('utf-8', 'surrogateescape') if isinstance(data, str) else data
        print('收到 %d 字节: %r hex=%s' % (len(raw), raw[:120], raw[:32].hex()), flush=True)
        # 回显，模拟终端行为（`\r` 换成 CRLF）。
        process.stdout.write(data.replace('\r', '\r\n'))
    print('客户端关闭通道', flush=True)
    process.exit(0)


async def main() -> None:
    key = asyncssh.generate_private_key('ssh-rsa')
    await asyncssh.create_server(
        FixtureServer,
        '0.0.0.0',
        PORT,
        server_host_keys=[key],
        process_factory=handle_client,
    )
    print('asyncssh 夹具已监听 0.0.0.0:%d（juice/juice）'
          ' many=%s alt=%s mouse=%s' % (PORT, MANY_LINES, ALT_SCREEN, MOUSE_TRACKING),
          flush=True)
    await asyncio.Event().wait()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
