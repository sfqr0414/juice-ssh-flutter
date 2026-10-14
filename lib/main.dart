import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_resources.dart';
import 'app/i18n.dart';
import 'app/settings_controller.dart';
import 'data/juice_database.dart';

/// 应用入口。
///
/// **首帧不等初始化**。初始化里有一笔固定开销：首次异步平台调用
/// （`getDatabasesPath()` 或紧随其后的第一个文件系统调用）实测占 500~800ms，
/// 而 `openDatabase` 本身只要 11~34ms —— 见 `JuiceDatabase.open` 里的埋点。
/// 以前这些步骤全部串行等在 `runApp` 之前，用户就要对着启动图多等这一整段。
/// 现在立刻出首帧（纯白，与原生 `launch_background` 同色，切换看不出跳变），
/// 初始化完成后再切到真正的应用。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JuiceBootstrap());
}

/// 初始化期间显示的引导壳：加载完成前是纯色屏，完成后是 `JuiceApp`。
class JuiceBootstrap extends StatefulWidget {
  const JuiceBootstrap({super.key});

  @override
  State<JuiceBootstrap> createState() => _JuiceBootstrapState();
}

class _JuiceBootstrapState extends State<JuiceBootstrap> {

  JuiceDatabase? _database;
  SettingsController? _settings;
  AppResources? _resources;
  JuiceStrings? _strings;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  /// 与原版的初始化链一致（原版由 `ApplicationClass` 建库）：
  /// 开库 → 载入 `config` 设置 → 载入打包资源（对应 `res/values/arrays.xml`）
  /// → 载入文案（对应 `strings.xml` 与 `values-zh`）。
  Future<void> _initialize() async {
    final database = await JuiceDatabase.open();

    // 三者互不依赖（只有设置需要数据库），并发加载：总耗时取最慢的一项，
    // 而不是三者之和。
    final loaded = await Future.wait<Object>([
      SettingsController.load(database),
      AppResources.load(),
      JuiceStrings.load(WidgetsBinding.instance.platformDispatcher.locale),
    ]);


    if (!mounted) return;
    setState(() {
      _database = database;
      _settings = loaded[0] as SettingsController;
      _resources = loaded[1] as AppResources;
      _strings = loaded[2] as JuiceStrings;
    });
  }

  @override
  Widget build(BuildContext context) {
    final database = _database;
    final settings = _settings;
    final resources = _resources;
    final strings = _strings;
    if (database == null ||
        settings == null ||
        resources == null ||
        strings == null) {
      // 与 `launch_background.xml` 的 `@android:color/white` 同色。
      return const ColoredBox(color: Color(0xFFFFFFFF));
    }
    return JuiceApp(
      database: database,
      settings: settings,
      resources: resources,
      strings: strings,
    );
  }
}
