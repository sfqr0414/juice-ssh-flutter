"""端口转发验证用的目标 TCP 服务。

收到什么就在前面加 `ECHO:` 原样回去，并把内容打进日志 —— 这样设备侧
`nc` 的输出和服务端日志能同时证明"字节真的穿过了转发通道"。

    python tools/_echo_target.py [端口]        # 默认 9999，只监听 127.0.0.1
"""

from __future__ import annotations

import socket
import sys
import threading


def _serve(conn: socket.socket, addr) -> None:
    print('目标服务：%s:%d 接入' % (addr[0], addr[1]), flush=True)
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            print('目标服务收到 %d 字节: %r' % (len(data), data[:120]), flush=True)
            conn.sendall(b'ECHO:' + data)
    except Exception as exc:  # noqa: BLE001
        print('目标服务异常: %r' % (exc,), flush=True)
    finally:
        try:
            conn.close()
        except OSError:
            pass
        print('目标服务：连接结束', flush=True)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9999
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', port))
    listener.listen(8)
    print('目标服务监听 127.0.0.1:%d' % port, flush=True)
    while True:
        conn, addr = listener.accept()
        threading.Thread(target=_serve, args=(conn, addr), daemon=True).start()


if __name__ == '__main__':
    main()
