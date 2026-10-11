"""通过 Dart VM service 抓取 Flutter 的组件树。

用途：模拟器上有些屏幕只能量像素（自绘/canvas），uiautomator 看不到节点。
这时用 logcat 里那行 `The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN=/`
拿到地址，adb forward 过来，用 JSON-RPC 调 `ext.flutter.debugDumpApp`，
就能直接看到当前到底在渲染哪些 Widget。

用法：
    python tools/_vm_dump.py <port> <token> [要从顶部打印多少行]
"""

import asyncio
import json
import sys


async def dump(port: str, token: str, lines: int) -> int:
    try:
        import websockets
    except ImportError:  # pragma: no cover - 首次运行会装
        print('缺少 websockets，请先 pip install websockets')
        return 2

    url = f'ws://127.0.0.1:{port}/{token}/ws'
    async with websockets.connect(url, max_size=None) as ws:
        await ws.send(json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'getVM'}))
        vm = json.loads(await ws.recv())
        isolates = vm.get('result', {}).get('isolates', [])
        if not isolates:
            print('没有 isolate:', vm)
            return 3
        isolate_id = isolates[0]['id']
        print('# isolate', isolate_id, isolates[0].get('name'))

        await ws.send(json.dumps({
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'ext.flutter.debugDumpApp',
            'params': {'isolateId': isolate_id},
        }))
        reply = json.loads(await ws.recv())
        text = reply.get('result', {}).get('data') or json.dumps(reply)
        for line in text.splitlines()[:lines]:
            print(line)
    return 0


if __name__ == '__main__':
    port = sys.argv[1] if len(sys.argv) > 1 else '41819'
    token = sys.argv[2] if len(sys.argv) > 2 else ''
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 70
    raise SystemExit(asyncio.run(dump(port, token, count)))
