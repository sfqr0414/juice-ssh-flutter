# 滚轮转发与夹具验证记录（第 348–349 轮）

本文记录三件事：**集成夹具为什么会"认证成功却报连接超时"**、**滚轮转发如何拿到端到端硬证据**、
以及**两种夹具服务端的取舍**。所有结论都附命令与原始输出，可复现。

## 1. 连接抖动的根因：测试时序，不是网络也不是 dartssh2

之前的现象很容易把人引向网络层：

```
服务端日志：  #1 口令认证 user='juice' pass='juice' -> 成功
App 界面日志：主机密钥裁决=HostKeyVerdict.accepted
              → 随后 "Connection Failed / 连接超时：10.0.2.2:2222"
```

加时间戳后在夹具里跑一次就看清了顺序：

```
JuiceSsh时间线: 等 authenticated 开始 (t=0ms)
JuiceSsh时间线: onVerifyHostKey 进入 type=rsa-sha2-512
SCROLL 注入窗口开始（30 秒）          ← 测试开始注入滑动，全程不碰弹窗
SCROLL 注入窗口结束
JuiceSsh时间线: 主机密钥裁决=accepted  ← 30 秒后才有人点"接受"
```

`integration_test/scroll_regression_test.dart` 原本**先开 30 秒注入窗口、窗口结束后才轮询点弹窗**，
而 `SshConnector.connect` 的 `client.authenticated.timeout(30s)` 早已到期 —— 于是必然超时，
且"弹窗与超时谁先到"决定了每次是否偶发。真机上用户手点弹窗很快，所以只在夹具里发作。

**修复**（两层，都在代码里）：

1. `integration_test/scroll_regression_test.dart`：把"处理连接期弹窗"提到注入窗口**之前**，
   并等到终端真的拿到历史（`terminalScrollable != null`）再开始注入；
2. `lib/ssh/ssh_service.dart`：已知主机查询与写入都加 **3 秒超时**并把失败降级为
   "未记录，但连接继续"（错误路径打日志，标了 `// ignore: avoid_print`）。
   本地持久化不该让整个握手卡死 —— 一旦卡死，界面只会说"连接超时"，把排查引向错误方向。

修复后稳定表现：

```
JuiceSsh时间线: authenticated 完成 (+2321ms)
JuiceSsh时间线: shell 打开完成 (+131ms)
```

## 2. 滚轮转发的端到端硬证据

实现照搬原版 `jackpal.androidterm.emulatorview.EmulatorView.onScroll`（反汇编 @3fa788）：
鼠标上报模式开着时，竖向位移按单元格高度累积成整数行数，再发 X10 编码的滚轮事件
`ESC [ M <code+32> <col+32> <row+32>`（手指上移 → 65，下移 → 64），并且**不回滚历史**。

夹具是 `tools/_sshd.py`（原样读字节、把每个输入块打成 `收到 N 字节 … hex=…`）：

```
#1 收到 6 字节: b'\x1b[M`98' hex=1b5b4d603938
#1 收到 6 字节: b'\x1b[Ma9)' hex=1b5b4d613929
#1 收到 12 字节: b'\x1b[Ma9)\x1b[Ma9)' hex=1b5b4d6139291b5b4d613929
ESC[M+65 条数=10   ESC[M+64 条数=13
```

同一轮里断言：`SCROLL 离底距离(备用屏): 0.0 → 0.0 (max=384.5)` —— 屏幕上有 384.5 像素的
回滚余量，却一像素都没动，**"交互命令模式不回滚历史、但滑动仍然有反应"两头都成立**。

`col`/`row` 也随手指位置单调变化（上划时 `row` 24→9 递减、下划递增），说明坐标换算正确。

## 3. 两种夹具服务端：别用 asyncssh 验 pty 输入

`tools/_sshd_asyncssh.py`（第 348 轮为提升保真度引入，`pip install asyncssh`）解决了旧夹具
**不回应 `exec` 请求**的问题 —— 宿主机探针 `test/ssh_connect_probe_test.dart` 用它首次全绿：

```
PROBE 连接成功 / PROBE 执行结果=hello / All tests passed!
```

但它**不能**用来验"客户端往 pty 里写了什么"：asyncssh 的 pty 会话带行缓冲（canonical），
不含换行的输入（滚轮事件正是 `ESC[M`+3 字符）会被它自己吞掉并回显，`process.stdin.read()`
永远不返回 —— 表现为"夹具一个字节没收到"，极易误判成 App 没发。实测同样一批 `ESC[M`
字节，`_sshd.py` 全都打了出来，asyncssh 一行都没有。

结论：**验 pty 原始输入用 `tools/_sshd.py`；验 exec/pty/退出码等协议完整性用
`tools/_sshd_asyncssh.py`。**

## 4. 断言修正：普通模式要用"过程峰值"

普通模式用例如实反映了拖动过程：

```
SCROLL 上滑: 384.476 → 拖动结束=164.476 → +1s=164.476 (max=384.476) 有变化=true
SCROLL 下滑: 164.476 → 384.476
```

但旧判据读的是**终值**（先上划看历史、再下划回底部 → 终值必然贴底），于是"普通模式应滚动"
这条断言自我抵消、永远为红 —— 与第 46/47 轮"读终值造成假阳性"是同一枚硬币的两面。
现改为比较**离底距离的峰值**，普通模式与备用屏两种判据共用这一份代码。

## 5. 复现命令

```powershell
# 终端 A：夹具（普通模式）
python tools/_sshd.py 2222 --many-lines

# 终端 B：跑测试，然后在它打印"注入窗口开始（30 秒）"后注入真实触摸
flutter test integration_test/scroll_regression_test.dart -d emulator-5554
adb shell input swipe 540 1700 540 700 250   # 手指上移 → 看历史 / 发滚轮 65
adb shell input swipe 540 700 540 1700 250   # 手指下移 → 回底部 / 发滚轮 64

# 交互模式（鼠标上报）把夹具换成：
python tools/_sshd.py 2222 --many-lines --mouse-tracking
flutter test integration_test/scroll_regression_test.dart -d emulator-5554 --dart-define=ALT_SCREEN=true
# 期望：夹具日志出现 hex=1b5b4d6…，且测试断言"不滚动"通过
```
