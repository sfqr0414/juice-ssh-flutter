# JuiceSSH Flutter 复刻

## 项目简介

本项目是 Android 应用 **JuiceSSH 3.2.2**（原包名 `com.sonelli.juicessh`）的**像素级 1:1 Flutter 复刻**，目标是**逐屏与原版对照**：把原版 APK 反编译产物当作唯一事实来源，而不是照截图重画。

- **权威数据来源**：反编译的 `reference/JuiceSSH.apk`（`smali`/`dex`、`res/` 资源、`res/raw/ormlite_config.txt`）+ 真机与模拟器上的实测像素。原版 APK **不进 git**（`.gitignore` 里忽略 `/reference/`，涉版权），需要复核结论时请自备该 APK 放到 `reference/`。
- **对照方式**：`versionName 3.2.2` / `versionCode 200` / `minSdk 26` / `targetSdk 29` 与原版逐项一致，但 `applicationId` 有意保持不同，使原版与复刻能装在**同一台设备**上并排比对。
- **当前状态**：六大核心功能（连接管理、终端仿真、身份与密钥、端口转发、代码片段、设置/主题）均已有设备侧证据；`flutter analyze` 无问题、`flutter test` 22/22 通过（出处：`docs/WHEEL-FORWARDING-VERIFICATION.md` 第 7 节）；`dist/release/` 有 4 个发布签名包 + `dist/debug/` 1 个调试包。
- **明确不做**：账号体系、云同步、Pro 内购、插件、EC2 导入等需要服务端或授权体系的能力（出处：`docs/IMPLEMENTATION-NOTES.md` 第 3.1 节）。

### 当前状态一览

| 项目 | 状态 | 出处 |
|---|---|---|
| 应用版本 | `3.2.2+200`（versionName / versionCode 与原版一致） | `pubspec.yaml`、`android/app/build.gradle.kts` |
| SDK 约束 | Dart `^3.13.5`；`minSdk 26` / `targetSdk 29` | `pubspec.yaml`、`android/app/build.gradle.kts` |
| 静态分析 / 单元测试 | `flutter analyze` 无问题；`flutter test` 22/22 通过 | `docs/WHEEL-FORWARDING-VERIFICATION.md` 第 7 节 |
| 端到端验证载体 | `integration_test/` 4 个用例（用例名已核，覆盖面未逐个通读）；另有宿主探针测试 | `integration_test/`、`test/ssh_connect_probe_test.dart` |
| 交付物 | `dist/release/` 4 个发布签名 ABI 包 + `dist/debug/` 1 个调试包 | `dist/` |
| 实现笔记 | 346+ 轮，逐轮记录假设、证伪、像素对照与撤回 | `docs/IMPLEMENTATION-NOTES.md` |

> 阅读提示：`docs/IMPLEMENTATION-NOTES.md` 里有大量**自我更正**（若干轮结论被后续轮次作废）。引用其结论时请以**编号更大**的轮次为准。

## 项目组织架构

### 分层关系

```
screens/（各屏 UI）
  └─ 读写 settings_controller.dart（设置）+ i18n.dart / app_resources.dart（文案与资源表）
terminal/（终端层）
  ├─ terminal_page.dart（界面）→ terminal_session.dart（会话状态机）
  └─ session_host.dart（进程级会话宿主，路由 pop 后会话继续跑）
ssh/（SSH 层）
  ├─ ssh_service.dart（连接、主机密钥、身份轮询认证）
  └─ port_forward_service.dart（-L/-R/-D 运行时）
data/（数据层）
  └─ juice_database.dart（sqflite）→ models.dart（与原版 ORMLite 实体对应的模型）
```

依赖方向单向向下：UI 屏不直接碰 `dartssh2`，`ssh/` 不碰 UI；`main.dart` 负责开库、载入设置/资源/文案后再交给 `app/app.dart` 的根 widget。

### 目录与关键文件

| 路径 | 职责 | 关键类 / 文件 |
|---|---|---|
| `lib/main.dart` | 应用入口，首帧不等初始化 | `JuiceBootstrap` |
| `lib/app/` | 主题、调色板、国际化、打包资源表、设置控制器、应用锁 | `JuicePalette`(`lib/app/juice_colors.dart`)、`JuiceTheme`(`lib/app/juice_theme.dart`)、`JuiceStrings`(`lib/app/i18n.dart`)、`AppResources`(`lib/app/app_resources.dart`)、`SettingsController`(`lib/app/settings_controller.dart`)、`JuiceApp`(`lib/app/app.dart`) |
| `lib/screens/` | 全部页面 | `MainScreen`(`lib/screens/main_screen.dart`)、`AddressBookScreen`(`lib/screens/address_book_screen.dart`)、`SettingsScreen`、`PinLockScreen`、各编辑器页 |
| `lib/terminal/` | 终端仿真与会话 | `TerminalSessionController`(`lib/terminal/terminal_session.dart`)、`TerminalPage`(`lib/terminal/terminal_page.dart`)、`SessionHost`(`lib/terminal/session_host.dart`)、`EscapeCharacters`/`KeyTag`(`lib/terminal/escape_characters.dart`)、`JuiceTerminalThemes`(`lib/terminal/terminal_themes.dart`) |
| `lib/ssh/` | SSH 连接、主机密钥、端口转发、密码库、通知 | `SshConnector`/`JuiceSshSession`(`lib/ssh/ssh_service.dart`)、`PortForwardService`、`PasswordVault` |
| `lib/data/` | 模型与持久化 | `Connection`/`Identity`/`PortForward` 等(`lib/data/models.dart`)、`JuiceDatabase`(`lib/data/juice_database.dart`)、`lib/data/generated/terminal_palettes.g.dart`（逆向生成的 9×260 色值，由 `tools/extract_from_apk.py` 产出） |
| `lib/widgets/` | 共享控件 | `JuiceAlertDialog`/`JuiceListDialog`/`JuiceDialogColors`(`lib/widgets/juice_alert_dialog.dart`)、`JuiceFormSectionHeader`/`JuiceFormRow`(`lib/widgets/juice_form.dart`)、`JuicePagerTabStrip`(`lib/widgets/pager_tab_strip.dart`)、`PagerList`/`JuiceListItem`(`lib/widgets/pager_list.dart`)、`JuicePopupItem`(`lib/widgets/juice_popup_menu.dart`) |
| `android/` | 原生壳：MethodChannel 桥、通知、状态栏、音量键 | `android/app/src/main/kotlin/com/juicessh/juice_ssh_flutter/MainActivity.kt`、`android/app/build.gradle.kts`、`android/app/src/main/AndroidManifest.xml` |
| `assets/` | 打包资源 | `assets/i18n/strings_en.json`（1062 条）/`strings_zh.json`、`assets/data/{arrays,colors,dimens,terminal_themes,apk_manifest}.json`、`assets/fonts/`（8 套 Nerd Font + FontAwesome + Roboto 静态字重） |
| `test/` | 单元/组件测试（钉住逆向常量与渲染规格） | `test/terminal_data_test.dart`、`test/terminal_surface_test.dart`、`test/terminal_theme_test.dart`、`test/juice_alert_dialog_test.dart`、`test/ssh_connect_probe_test.dart` |
| `integration_test/` | 应用进程内驱动 UI 的端到端载体 | `app_smoke_test.dart`、`screens_sweep_test.dart`、`port_forward_test.dart`、`scroll_regression_test.dart` |
| `tools/` | 反编译抽取与比对脚本、测试夹具 | `extract_from_apk.py`、`compare_dumps.py`、`_text_bands.py`、`_sample_colors.py`、`check_schema.py`、`check_i18n_keys.py`、`_sshd.py`、`_sshd_asyncssh.py` |
| `docs/` | 规格与逐轮实现笔记 | `docs/IMPLEMENTATION-NOTES.md`（346+ 轮）、`docs/ui-spec.md`、`docs/terminal-behaviour-spec.md`、`docs/original-schema.sql`、`docs/WHEEL-FORWARDING-VERIFICATION.md` |
| `dist/` | 已产出的安装包（**被 `.gitignore` 忽略，不进 git**，由本地构建或 CI 生成） | `dist/release/`（arm64-v8a / armeabi-v7a / x86_64 / 通用）、`dist/debug/` |
| `reference/` | 原版 APK（**被 `.gitignore` 忽略，不进 git**，需自备） | `reference/JuiceSSH.apk` |

### 页面与原生桥对照

| 复刻文件 | 对应原版界面 / 说明 |
|---|---|
| `lib/screens/main_screen.dart` | `MainActivity`（LAUNCHER）卡片式首页，布局取自 `res/layout/card_list.xml` |
| `lib/screens/address_book_screen.dart` | `AddressBookActivity`：`ViewPager` + `PagerTabStrip` 三标签（Connections / Identities / Port Forwards） |
| `lib/screens/connections_screen.dart`、`connection_editor_screen.dart` | 连接列表与连接编辑器；长按行弹上下文菜单 |
| `lib/screens/identities_screen.dart`、`identity_editor_screen.dart` | 身份列表与身份编辑器（口令 / 私钥 / PEM 展示） |
| `lib/screens/port_forwards_screen.dart`、`port_forward_editor_screen.dart` | 端口转发列表（带行内启停开关）与转发编辑器 |
| `lib/screens/snippets_screen.dart`、`groups_screen.dart` | 代码片段管理；分组管理页是复刻新增（原版没有，用长按进入） |
| `lib/screens/known_hosts_screen.dart` | 已知主机查看页，复刻新增（原版只有"全部清空"），同样用长按进入 |
| `lib/screens/settings_screen.dart`、`pin_lock_screen.dart` | 设置页（约 20 行）与应用锁 |
| `lib/terminal/terminal_page.dart` | `TerminalEmulatorActivity`：黄色 ActionBar + 终端主体 + 70dp 额外键行 + 长按上下文菜单 + 返回键 `background_session` 三选提示 |

原生侧只有一处 Activity（`MainActivity.kt`），通过三条 MethodChannel 与 Dart 通信：

| 通道 | 用途 |
|---|---|
| `com.juicessh.juice_ssh_flutter/port_forwards` | 端口转发常驻通知（`show` / `cancel` / `bell` / `requestPermission`），通知上的停止动作经 `BroadcastReceiver` 回传 Dart |
| `com.juicessh.juice_ssh_flutter/hardware_keys` | 终端页激活期间拦截音量键（keycode 24/25）改字号 |
| `juicessh/system_ui` | `setStatusBar`（颜色 + 浅色图标）与 `imeVisible`（输入法真实可见性） |

## 构建与运行

工具链按 `docs/IMPLEMENTATION-NOTES.md` 第 5 节的记录安装在 `D:\dev`（JDK 17 / Android SDK / Flutter 3.47.7 stable）；对比设备是 AVD `juice_pixel`（Pixel 6、Android 16、1080×2400 @420dpi）。

| 操作 | 命令（出处：第 5 节） |
|---|---|
| 静态分析 | `flutter analyze` |
| 单元测试 | `flutter test` |
| 端到端 | `flutter test integration_test/<用例>.dart -d emulator-5554` |
| 装到模拟器 | `flutter build apk --debug` 后 `adb install -r build\app\outputs\flutter-apk\app-debug.apk` |
| 对照原版 | `adb shell uiautomator dump` + `adb shell screencap -p /sdcard/x.png` + `adb pull` |

已记录的坑（第 5 节）：PowerShell 里 `adb exec-out screencap -p > x.png` 会写出坏 PNG（CRLF 转换），必须先写设备文件再 `adb pull`；`adb shell input text` **无法**输入进 Flutter 文本框（走 `InputConnection`），造数据要直接改写应用私有数据库；`android/gradle.properties` 里的 `kotlin.incremental=false` 必须保留（pub 缓存在 C:、工程在 D:，跨盘符会让 Kotlin 增量编译直接失败）。


### 本机工具链

| 组件 | 路径 / 版本 |
|---|---|
| Flutter | `D:\dev\flutter`（3.47.7 stable / Dart 3.13.5） |
| JDK | `D:\dev\jdk17`（Temurin 17） |
| Android SDK | `D:\dev\android-sdk`（platform 36 / build-tools 36） |
| 模拟器 | AVD `juice_pixel`：Pixel 6，Android 16（SDK 36），1080×2400 @ 420dpi |

安装时先设环境变量（每次新开终端都要）：

```powershell
$env:JAVA_HOME='D:\dev\jdk17'
$env:ANDROID_HOME='D:\dev\android-sdk'
$env:ANDROID_SDK_ROOT='D:\dev\android-sdk'
$env:Path = 'D:\dev\jdk17\bin;D:\dev\flutter\bin;D:\dev\android-sdk\platform-tools;D:\dev\android-sdk\emulator;' + $env:Path

# 启动模拟器（必须分离进程，否则 adb 会跟着被杀）
Start-Process 'D:\dev\android-sdk\emulator\emulator.exe' `
  -ArgumentList '-avd','juice_pixel','-no-boot-anim','-netdelay','none','-netspeed','full' `
  -PassThru -WindowStyle Minimized

flutter run                       # 或
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -n com.juicessh.juice_ssh_flutter/.MainActivity
```

### 与原版并排比对用的脚本

| 脚本 | 用途 |
|---|---|
| `tools/compare_dumps.py` | 两份 uiautomator 层级做标签序列 LCS 对齐后并排对照，带位置差；`--ids` 连容器一起列 |
| `tools/_read_ui_dump.py` | 单份层级，带 px→dp 换算 |
| `tools/_text_bands.py` | 截图里文字带所在的像素区间；`--axis cols` 量 x 坐标 |
| `tools/_sample_colors.py` | 采样指定矩形的颜色 |
| `tools/extract_from_apk.py` | 从 APK 抽字符串 / 尺寸 / 颜色 / 终端配色 / 字体 |
| `tools/check_schema.py` | 用 Python sqlite3 跑一遍 Dart 里的建表 SQL |
| `tools/check_i18n_keys.py` | 校验 Dart 里引用的文案键都存在 |
| `tools/_sshd.py` | 集成测试用 SSH 夹具：原样打印收到的每个字节（验"客户端到底发了什么"） |
| `tools/_sshd_asyncssh.py` | 集成测试用 SSH 夹具：protocol 保真（验 exec / pty / 退出码） |

## 发布与持续集成

`.github/workflows/release.yml` 负责构建并发布**所有目标平台**的 release APK：

- **触发**：手动 `workflow_dispatch`（可选填 `version` 覆盖版本号），或推送形如 `v1.0.0` 的 tag（版本号取 tag 名去掉 `v`）。
- **环境**：`ubuntu-24.04` + Temurin JDK 17 + Flutter（`channel: stable`，版本固定为与本仓库开发环境一致的 3.47.7）+ 映像自带的 Android SDK（接受许可后，缺的组件交给 AGP 自行下载）。
- **产物**：`arm64-v8a` / `armeabi-v7a` / `x86_64` 三个 ABI 包 + 一个通用（fat）包 + `SHA256SUMS.txt`，命名与本地 `dist/release/` 一致。任何触发方式都会上传为 Actions artifact；tag 触发时额外创建 GitHub Release 并附上这些文件。
- **签名**：`android/app/build.gradle.kts` 在缺少 `android/key.properties` 时自动回退 debug 签名，因此**不配任何 Secret 也能出包**。要出正式签名包，在仓库 Secrets 里配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`，流水线会自动写出 `key.properties` 与 `.jks`。
- **质量门**：出包前先跑 `flutter analyze`（只作提示，不同 Flutter 小版本的新 lint 不拦出包）与 `flutter test`（**硬门**；依赖外部 SSH 夹具的用例在没有夹具时会自动跳过）。

本地等价的出包命令：

```powershell
flutter build apk --release --split-per-abi   # arm64-v8a / armeabi-v7a / x86_64
flutter build apk --release                   # 通用包
flutter build apk --debug
```

## 实现内容

### 终端仿真

- **引擎**：`xterm ^4.0.0`（`pubspec.yaml`），会话控制器 `TerminalSessionController` 负责状态机（连接中/已连接/已断开/失败）、字节泵与 Ctrl/Alt 修饰键语义（`lib/terminal/terminal_session.dart`）。
- **配色**：9 套配色 × 260 个 ARGB 值（256 色 + 前景 + 背景），由 `tools/extract_from_apk.py` 从原版 `com/sonelli/ni0.smali` 的数组逆向生成到 `lib/data/generated/terminal_palettes.g.dart`；默认 `terminal:theme = 2`（Solarized Dark），依据是 `TerminalEmulatorActivity` 对缺失值取 `"2"`（`lib/app/settings_controller.dart`）。
- **字体**：与原版内置的 8 套 Nerd Font 同名同源（`pubspec.yaml` 的 `fonts:`），并额外实例化 Roboto 的 w400/w700 静态字重，避免 Flutter 合成粗体（第 64 轮）。
- **回滚缓冲**：10000 行，取自原版 `TermSession.TRANSCRIPT_ROWS = 0x2710`（`lib/terminal/terminal_session.dart`）；初始 80×25（原版 `initializeEmulator(80, 25)`）。
- **扩展键行**：`lib/terminal/hacker_keyboard.dart` + `lib/terminal/escape_characters.dart`（F1–F12 与 `KeyTag` 复用原版 packed-switch 的负值编码），位置由 `terminal:keyboard_position` 决定。
- **滑动与滚轮**：交互态判定与滚轮转发照抄原版 `jackpal.androidterm.emulatorview.EmulatorView.onScroll`（`dexdump -d` 偏移 3fa788 / 3fa494），鼠标上报模式（DECSET 1000/1002/1003）或备用屏时把竖向位移按单元格高度累积成 X10 滚轮事件 `ESC [ M <code+32> <col+32> <row+32>`，且不回滚历史（`docs/WHEEL-FORWARDING-VERIFICATION.md` 第 2 节）。

### SSH 客户端与认证

- **库**：`dartssh2 ^4.1.0`（`pubspec.yaml`），封装在 `lib/ssh/ssh_service.dart`（`SshConnector` / `JuiceSshSession`）。
- **身份轮询**：一条连接可挂多个身份，先试带私钥的（公钥认证）再试带密码的，逐个尝试；因为 dartssh2 单连接只尝试一次密码认证，所以每个候选身份重新建连来复现原版语义（`lib/ssh/ssh_service.dart`）。
- **主机密钥**：首次见到弹确认框、指纹变更提示风险，判定结果分 `HostKeyVerdict.accepted/rejected`，记录进 `host` 表；已知主机的查询与写入都加 **3 秒超时**并降级为"未记录但继续连接"，避免本地库卡死把整个握手拖成"连接超时"（`lib/ssh/ssh_service.dart` + `docs/WHEEL-FORWARDING-VERIFICATION.md` 第 1 节）。
- **密码**：进程内缓存 → `PasswordVault`（`flutter_secure_storage`，跨重启记住）→ 弹窗询问；若同一次连接里服务端二次索要密码，视为存储的密码已失效并清除后重新询问（`lib/ssh/ssh_service.dart`）。
- **键盘交互式认证**：两因素认证的 prompt 原样透出（`onUserInfoRequest`）。
- **Agent 转发**：`ssh:agent` 打开时注入 `SSHKeyPairAgent`，由 dartssh2 发出 `auth-agent-req@openssh.com`；服务端拒绝时降级为"不转发重试"，不让整次连接失败（第 37–39、42 轮）。

### 端口转发与会话管理

- **三种模式**：`-L` 本地监听后逐连接拨通道、`-R` 远端监听、`-D` SOCKS5，实现在 `lib/ssh/port_forward_service.dart`；每条转发可单独启停，对应原版列表行的 `toggleIndicator`；转发挂在连接上，会话断开时统一回收。
- **常驻通知**：每条约活动转发一条通知（`setUsesChronometer(true)` + 停止动作，文案 `@string/disconnect`），点开的去向由 `PortForward.openInBrowser` 决定；原生化在 `android/app/src/main/kotlin/com/juicessh/juice_ssh_flutter/MainActivity.kt`。
- **会话宿主**：`lib/terminal/session_host.dart` 把会话持有权从页面 State 提到进程级单例，让"返回键 → 保持后台"成为真的（原版靠前台 Service）。

### 主题、国际化与数据持久化

- **主题**：`JuicePalette` 逐字段对应原版颜色资源，亮色取自 `res/values/colors.xml`、暗色取自 `res/values-night/colors.xml`（`lib/app/juice_colors.dart`）；`useMaterial3: false`，因为原版是 Material 2 / 旧式 ActionBar。
- **国际化**：`assets/i18n/strings_en.json`（1062 条）与 `strings_zh.json`（655 条）由 `tools/extract_from_apk.py` 从 `res/values/strings.xml` 与 `res/values-zh-rCN/strings.xml` 抽出，含 `%s`/`%d`/位置参数格式化；缺失键回退英文、再回退键名（`lib/app/i18n.dart`）。
- **设置**：键名与原版完全一致（`terminal:theme`、`pinlock:enabled`、`theme:dark` …），布尔值按原版落库为字符串 `true`/`false`（`lib/app/settings_controller.dart`）。
- **数据库**：sqflite，表名沿用原版 ORMLite 结构；配置层已迁到原版的 `configfield` + `configvalue` 两表（25 条键定义与默认值逐条抄自原版实测库），`schemaVersion = 2`（`lib/data/juice_database.dart`）。
- **应用锁**：`PinLockScreen` + `lib/app/app.dart` 的生命周期监听，按 `pinlock:timeout` 判定后台停留是否超过阈值才重新上锁。

### 与原版对齐的关键决定

| 决定 | 原因 / 出处 |
|---|---|
| `targetSdk = 29`（写死，不用 Flutter 默认 36） | 与包内 `apktool.yml` 的 `targetSdkVersion 29` 一致；targetSdk 决定大量运行时行为。代价是 release 构建需 `disable += "ExpiredTargetSdkVersion"`（`android/app/build.gradle.kts`，第 57 轮） |
| `minSdk = 26`、`versionName 3.2.2`、`versionCode 200` | 与原版清单四项逐项相同（第 57 轮） |
| `applicationId = com.juicessh.juice_ssh_flutter`（**有意**不同于原版 `com.sonelli.juicessh`） | 保持不同 package 与签名，才能与原版**同时装在同一台设备**上逐屏对照（`android/app/build.gradle.kts` 注释） |
| 颜色/尺寸取自原版资源而非目测 | `assets/data/colors.json`、`assets/data/dimens.json` 由 `tools/extract_from_apk.py` 从 `res/values/{colors,dimens}.xml` 抽出，运行时由 `AppResources` 解析 |
| `theme:dark` 的旧值 `-1` 映射为**深色** | 原版官方表只有 1/2/3，`-1` 属旧版遗留，原版对表外值回落深色。改正后底色/文字色/状态栏黄三项与原版逐像素一致（第 62 轮） |
| 列表项长按用底部 `showModalBottomSheet` 代替原版"在触点弹原生上下文菜单" | Flutter 无等价物（第 3.2 节） |
| 端口转发页对非 Pro 用户做成**可用功能**（原版是付费墙） | 本次范围先做核心版，不做授权体系；列表/空态/FAB 位置仍按 `port_forwards.xml` 对齐（第 3.2 节） |
| 未实现的功能点击后统一提示 `Not available in this build` | 该文案在原版字符串表里**不存在**，是复刻新增的有意显眼偏离，好过假装成功（第 3.1 节） |

## 复刻比对

### 方法

1. **反编译取权威值**：`reference/JuiceSSH.apk` 解出 `smali`/`dex`（用 `dexdump -d` 读具体偏移）、`res/values/{colors,dimens,arrays,strings}.xml`、`res/raw/ormlite_config.txt`，落成 `assets/data/*.json` 与 `lib/data/generated/*.dart`。
2. **静态布局对照**：把原版 layout XML 的每个 id、字号、内边距、外距与 Flutter 实现逐项核对（成本低、结论硬）。
3. **同机逐屏像素/坐标对照**：原版与复刻并排装在同一台模拟器（`juice_pixel`，Pixel 6 / Android 16 / 1080×2400 @420dpi），`adb shell uiautomator dump` 取语义树 + `screencap` 取像素，用 `tools/compare_dumps.py`（标签序列 LCS 对齐后带位置差）、`tools/_text_bands.py`（文字带像素区间）、`tools/_sample_colors.py`（矩形取色）量化。
4. **行为级取证**：用测试夹具 `tools/_sshd.py`（原样打印收到的每个字节）与 `tools/_sshd_asyncssh.py`（协议完整性）作地面真值，配合 `integration_test/` 在应用进程内驱动 UI。
5. **数值回归**：把逆向常量与渲染规格钉进单元测试（`test/terminal_data_test.dart`、`test/terminal_surface_test.dart`、`test/terminal_theme_test.dart`）。

### 已确认一致的例子

| 例子 | 数值 | 出处 |
|---|---|---|
| 首页卡片纵向位置 | Quick Connect `317px`（高 184）、Frequently Used `543px`、Help `1889px` 三张差 **0**；其余 ≤ 4px | `docs/IMPLEMENTATION-NOTES.md` 第 7 节「首页（`MainActivity`）—— 卡片位置」 |
| 管理连接页几何 | 内容区起点 `275px`、列表区起点 `359px`、FAB `(891,2148) 147×147`、窗口底边 `2337px` 全部差 **0** | 同上，「管理连接（`AddressBookActivity`）」 |
| 终端画布与快捷键栏底色 | Solarized Dark 画布 `#254E59`（背景 `#073642` 叠白 12%）、快捷键栏 `#1D4750`（叠前景 9.5%），均由原版实测像素反推 | `lib/terminal/terminal_themes.dart` + `test/terminal_surface_test.dart`（4 条断言） |
| 终端配色 | 9 套 × 260 项，Dark 前 16 个 ANSI 值逐项锁定（`0xFFCD0000`/`0xFF00CD00`/`0xFFCDCD00` …），后 240 项九套相同 | `lib/data/generated/terminal_palettes.g.dart` + `test/terminal_data_test.dart` |
| 配置层结构 | 与原版真实库逐行一致：`configfield` 两边都是 25 行，`defaultValue` **0 处不一致、无缺失键** | 第 56 轮（`docs/original-schema.sql` 为建表语句来源） |
| 暗色配色 | 状态栏带 `(213,186,49)`、正文空白 `(0,0,0)`、文字 `(190,190,190)` 三项与原版逐像素一致 | 第 62 轮 |
| 滚轮转发的字节 | 夹具收到 `hex=1b5b4d603938` 等 `ESC[M`+3 字符，断言 `ESC[M+65 条数=10 / +64 条数=13`，同时"离底距离 0.0 → 0.0"证明不回滚历史 | `docs/WHEEL-FORWARDING-VERIFICATION.md` 第 2 节 |
| 设置页行位置 | `Manage Snippets y=635`、`Amazon EC2 Link y=803` 与原版**逐像素相同** | 第 57 轮 |

## 功能清单

### 已实现

| 功能 | 依据 |
|---|---|
| SSH 会话（口令 / 公钥 / 键盘交互式认证） | `lib/ssh/ssh_service.dart`；口令与公钥两条路径各有设备侧证据（第 18、48 轮） |
| 多身份按序尝试认证 | `lib/ssh/ssh_service.dart`（重新建连循环）；第 45、52 轮 |
| Agent 转发（含被拒降级重试） | 第 37–39 轮验证成功、第 42 轮修复"被拒拖死整次连接" |
| 主机密钥确认 / 指纹变更告警 / 已知主机存储 | `lib/ssh/ssh_service.dart`、`lib/screens/known_hosts_screen.dart` |
| 终端仿真、Ctrl/Alt、F1–F12、扩展键行 | `lib/terminal/terminal_session.dart`、`lib/terminal/hacker_keyboard.dart`、`lib/terminal/escape_characters.dart` |
| 9 套配色 + 8 套 Nerd Font + 字号/边距 | `lib/data/generated/terminal_palettes.g.dart`、`pubspec.yaml`、第 40 轮 |
| 交互式程序禁滑 + 滚轮转发 | 第 346–349 轮（`lib/terminal/terminal_session.dart` + `lib/terminal/terminal_page.dart`）；真机确认 + 夹具字节级确认 |
| 水平滑动模式（Irssi/WeeChat/tmux/screen/Disabled） | 第 33 轮实现并验证；`lib/terminal/terminal_page.dart` |
| 音量键改字号 | `android/app/src/main/kotlin/com/juicessh/juice_ssh_flutter/MainActivity.kt` 的 keycode 24/25 拦截；第 34–35 轮 |
| 响铃三模式（关 / 震动 / 通知） | `lib/terminal/terminal_session.dart` + `android/app/src/main/kotlin/com/juicessh/juice_ssh_flutter/MainActivity.kt` 的 `bell` 通道；第 36 轮（模式 1 正向证据）、第 27 轮（模式 2 通知） |
| 连接管理：增删改、复制、分组、使用次数 | `lib/screens/connections_screen.dart`、`lib/screens/groups_screen.dart`；第 53 轮修"使用次数从未写入" |
| 身份与密钥（粘贴 PEM 私钥、口令、PEM 展示对话框） | `lib/screens/identity_editor_screen.dart`；第 50–52 轮 |
| 端口转发 `-L` / `-R` / `-D` + 单条启停 + 常驻通知 + 通知上断开 | `lib/ssh/port_forward_service.dart`；第 19–25、46–47 轮 |
| 代码片段（含连上后自动执行） | `lib/screens/snippets_screen.dart`；第 18 轮 |
| 设置页 20 行 × 与代码对齐 + 逐行取值 | `lib/screens/settings_screen.dart`；第 40、57、58 轮 |
| 应用锁（PIN）+ 按 `pinlock:timeout` 超时重新上锁 | `lib/screens/pin_lock_screen.dart`、`lib/app/app.dart` |
| 密码加密持久化（跨重启记住，失效自动清除） | `lib/ssh/password_vault.dart` + `lib/ssh/ssh_service.dart`；第 273 轮 |
| 状态栏与终端同色（沉浸）、状态栏与 ActionBar 同色 | `android/app/src/main/kotlin/com/juicessh/juice_ssh_flutter/MainActivity.kt` 的 `juicessh/system_ui` 通道；第 245–248、262 轮 |
| 会话后台保活（`SessionHost`） | `lib/terminal/session_host.dart`；第 22 轮 |
| 4 个发布签名 ABI 包 + 1 个 debug 包 | `dist/release/`、`dist/debug/`；第 322–327、345+ 轮 |
| 交付物与源码一致性、性能基线 | 第 266、315–316 轮 |

### 未实现 / 部分实现 / 已知差异

| 项 | 状态 | 依据 |
|---|---|---|
| telnet / mosh / 本地设备连接类型 | 编辑器的四项都在，但底层只有 `dartssh2` 一条通道，选非 SSH 会走 SSH 并失败 | 第 3.1 节 |
| Pro 内购、插件、Tech Library、CloudSync / TeamShare | 未实现，只给 `Not available in this build`；云同步卡片干脆不出现 | 第 3.1 节 |
| `Amazon EC2 Link`、`Components & Licenses` | 未实现（无对应页面） | 第 3.1 节 |
| 主屏快捷方式 | 未实现，点击给出"不支持"提示 | `lib/screens/connections_screen.dart`、`lib/screens/port_forwards_screen.dart` |
| 身份私钥的三步录入 | 只实现"粘贴 PEM"；**生成密钥**与**从文件导入**未实现 | `lib/screens/identity_editor_screen.dart` 注释、第 50 轮 |
| 密钥的文件导出 | 未实现，改为弹窗展示 PEM | 第 3.1 节 |
| "生成公钥代码片段"按钮 | 未实现密钥推导，只给提示、不写库 | `lib/screens/identity_editor_screen.dart` |
| `use_as_proxy` 行为 | 只存库、运行时无消费者 —— 原版亦然，**不算差异** | 第 26 轮 |
| 业务表列名与主键 | 仍是 `fieldName` 形态 + 自增整数主键，**尚未**对齐原版的 `_id` 后缀 + UUID 字符串；复刻还多出自造的 `connectionidentity.position` | `lib/data/juice_database.dart` 类注释、第 55–56 轮 |
| 长按列表项的菜单形态 | Flutter 用底部弹出替代"在触点弹原生上下文菜单" | 第 3.2 节 |
| 终端页溢出按钮 | 原版终端页只有长按菜单、无溢出菜单，复刻多一个按钮（已实测确认为真实差异） | `lib/terminal/terminal_page.dart` 类注释 |
| ActionBar 返回按钮语义 | 原版是 `Navigate up`，复刻是 Flutter 默认 `Back`（仅语义树/读屏可见），**记入待办未改** | 第 57 轮、第 59 轮 |
| 终端粗体 | 已定位"墨迹偏多"的原因并落地改动，但**尚未生效**（如实记录） | 第 64 轮 |
| 状态栏 / ActionBar 之外的区域配色 | 部分页面（如身份页）的颜色维度**尚未**真正比对过 | 第 62、64 轮 |
| 滚轮转发的**方向与字节** | 夹具已确认（见上文比对表）；但设备侧自验（`printf '\033[?1002h'; cat -v` 后滑动）**尚未执行** | 第 346+ 轮末尾「未验证」、`docs/WHEEL-FORWARDING-VERIFICATION.md` 第 2 节 |
| 响铃模式 1（震动） | 只有间接正向证据，未独立复核 | 第 36 轮 |
| 通知授权时机 | 授权框原本在**冷启动**时弹（`targetSdk 29` + 启动即建通知渠道）；已改为按需创建渠道、同刻请求授权，并有"启动后无渠道 / 测试期间无授权框"的对照采样 | `docs/WHEEL-FORWARDING-VERIFICATION.md` 第 6 节 |
| 密码"重启也记住" | 实现路径在代码里，但**未验证**跨重启场景 | `lib/ssh/ssh_service.dart` 注释、第 273 轮 |
| 终端字号换算系数 1.75 | 是**标定值**而非原版依据，待真机截图比对后再微调 | `lib/terminal/terminal_session.dart` 注释 |
| 字体导入 / 终端 `screen`·`ansi` 类型 | 原版包内 `terminfo.zip` 有，但设置页只列 5 项，复刻与设置页一致 | `lib/app/settings_controller.dart` 注释 |
| DA（设备属性）应答 | 复刻**整条丢弃**以断掉 ping-pong，原版老终端也不做应答 | `lib/terminal/terminal_session.dart` |

## 资料出处

本文每条结论的出处（相对路径）；"第 N 轮"指 `docs/IMPLEMENTATION-NOTES.md` 的编号轮次。

- `pubspec.yaml`
- `lib/main.dart`、`lib/app/app.dart`、`lib/app/app_resources.dart`、`lib/app/i18n.dart`、`lib/app/juice_colors.dart`、`lib/app/juice_theme.dart`、`lib/app/settings_controller.dart`
- `lib/ssh/ssh_service.dart`、`lib/ssh/port_forward_service.dart`
- `lib/terminal/session_host.dart`、`lib/terminal/terminal_session.dart`、`lib/terminal/terminal_page.dart`
- `lib/data/juice_database.dart`、`lib/data/models.dart`、`lib/data/generated/terminal_palettes.g.dart`
- `lib/screens/main_screen.dart`（含注释）、`lib/screens/identity_editor_screen.dart`（含注释）、`lib/screens/connections_screen.dart`、`lib/screens/port_forwards_screen.dart`（经 grep 命中行）
- `android/app/build.gradle.kts`、`android/app/src/main/AndroidManifest.xml`、`android/gradle.properties`、`android/app/src/main/kotlin/com/juicessh/juice_ssh_flutter/MainActivity.kt`
- `test/terminal_data_test.dart`（第 20–93 行逐行读过，其余部分只读到用例名与断言行）、`test/terminal_surface_test.dart`（全文）、`test/terminal_theme_test.dart`、`test/juice_alert_dialog_test.dart`、`test/ssh_connect_probe_test.dart`（后三者仅读到用例名）
- `integration_test/app_smoke_test.dart`、`integration_test/screens_sweep_test.dart`、`integration_test/port_forward_test.dart`、`integration_test/scroll_regression_test.dart`（仅测试用例名与文件清单）
- `docs/IMPLEMENTATION-NOTES.md`（标题骨架 + 第 3、4、6、7 节 + 第 32、50、56、57、62、106–107、345+、346+ 轮）
- `docs/WHEEL-FORWARDING-VERIFICATION.md`（全文）
- `docs/original-schema.sql`（`CREATE TABLE` 清单）
- `tools/`、`dist/`、`assets/`、`.research/`（仅目录与文件清单）
- `.research/JUICESH_INVENTORY.md`（前 60 行）
