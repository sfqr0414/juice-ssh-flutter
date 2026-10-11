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

  final database = await JuiceDatabase.open();
  final settings = await SettingsController.load(database);
  final resources = await AppResources.load();
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final strings = await JuiceStrings.load(locale);

  runApp(
    JuiceApp(
      database: database,
      settings: settings,
      resources: resources,
      strings: strings,
    ),
  );
}
