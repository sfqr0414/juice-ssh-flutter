import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_resources.dart';
import 'app/i18n.dart';
import 'app/settings_controller.dart';
import 'data/juice_database.dart';

/// 应用入口。
///
/// 启动顺序对应原版的初始化链：
/// 1. 打开 SQLite 数据库 —— 原版由 `ApplicationClass` 建库，
///    这里保持相同的表名与列名，便于直接读原版的 `juicessh.db`；
/// 2. 载入 `config` 表里的全部设置项（原版每个设置项都直接读这张表）；
/// 3. 载入打包进来的资源数组（对应 `res/values/arrays.xml`）；
/// 4. 载入文案（对应 `res/values/strings.xml` 与 `values-zh`）；
/// 5. 启动界面。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动耗时埋点（`adb logcat -s flutter` 可见）。这四步都在 runApp 之前，
  // 首帧必须等它们全部完成，所以要能分别量出来才知道该压哪一步。
  final stopwatch = Stopwatch()..start();

  final database = await JuiceDatabase.open();
  final databaseMs = stopwatch.elapsedMilliseconds;

  // 三者互不依赖（只有设置需要数据库），并发加载：总耗时取决于最慢的一项，
  // 而不是三者之和。此前是串行 await，白等了两个资源解析的时间。
  final loaded = await Future.wait<Object>([
    SettingsController.load(database),
    AppResources.load(),
    JuiceStrings.load(WidgetsBinding.instance.platformDispatcher.locale),
  ]);
  final restMs = stopwatch.elapsedMilliseconds - databaseMs;
  debugPrint(
    'JuiceSSH 启动耗时: 开库 ${databaseMs}ms + 资源/设置/文案 ${restMs}ms '
    '= ${stopwatch.elapsedMilliseconds}ms',
  );

  runApp(
    JuiceApp(
      database: database,
      settings: loaded[0] as SettingsController,
      resources: loaded[1] as AppResources,
      strings: loaded[2] as JuiceStrings,
    ),
  );
}
