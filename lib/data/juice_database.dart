import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

/// @brief SQLite 存储层，表名与列名沿用原版 JuiceSSH 的 ORMLite 结构。
///
/// 表名与列名沿用原版 JuiceSSH 的 ORMLite 结构，但**不能**只照抄包内
/// `res/raw/ormlite_config.txt` 里的 `fieldName=`（那是 Java 字段名）：ORMLite
/// 运行时还会做两件 config 文件里看不到的事 —— 外键列加 `_id` 后缀
/// （`group` → `group_id`、`via` → `via_id`、`owner` → `owner_id` …）、
/// 主键用 UUID 字符串而非自增整数。此前正是照字段名建的库，所以与原版真实库
/// 对不上（第 55 轮把运行中的原版库拉下来核对时发现）。
///
/// 配置层本轮已改成与原版一致的两表结构：
///
/// * `configfield` —— 每个设置键的定义与**默认值**（25 条，逐条抄自原版实测库）；
/// * `configvalue` —— 只存被改过的键，未改过的键没有行，读取时回落到默认值。
///
/// 其余业务表（`connection` / `identity` / `snippet` …）的列名仍是 `fieldName`
/// 形态，尚未对齐，详见 `docs/IMPLEMENTATION-NOTES.md` 第 55/56 轮。
class JuiceDatabase {
  /// @brief 用已打开的 sqflite 数据库构造（外部请走 `open()`）。
  JuiceDatabase._(this._db);

  /// @brief 底层 sqflite 数据库句柄
  final Database _db;

  /// @brief 进程内单例，`open()` 成功后填入
  static JuiceDatabase? _instance;

  /// @brief 取已初始化的单例，未初始化时抛 StateError。
  static JuiceDatabase get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('数据库尚未初始化，请先 await JuiceDatabase.open()');
    }
    return value;
  }

  /// @brief 库结构版本号，见下方说明。
  ///
  /// v2：设置从自建的 `config` 表迁到原版的 `configfield` + `configvalue`。
  static const int schemaVersion = 2;

  /// @brief 数据库文件名，放在 `getDatabasesPath()` 目录下
  static const String fileName = 'juicessh.db';

  /// @brief 桌面平台需要先初始化 sqflite 的 FFI 后端。
  ///
  /// 移动端**保留**平台通道后端：本轮试过全平台改走 FFI（`databaseFactoryFfi`），
  /// 开库耗时实测没有变化（11~34ms vs 26~34ms，那 500ms 根本不在这段里），
  /// 却要动数据安全的关键路径，因此回退。
  static void initializeFfiIfNeeded() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// @brief 打开（必要时建库/建表）数据库并设为单例，返回该实例。
  static Future<JuiceDatabase> open({String? directory}) async {
    final t0 = DateTime.now();
    final baseDir = directory ?? await getDatabasesPath();
    final t1 = DateTime.now();
    initializeFfiIfNeeded();
    final path = p.join(baseDir, fileName);
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        // 外键约束与原版 ORMLite 的 foreign=true 对应
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in _schema) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
        // 原版首次启动会写入 `configfield` 的 25 条键定义与默认值，
        // 之后只有被改过的键才落到 `configvalue`。
        await _seedConfigFields(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 用一张自建的 `config` 表存设置；v2 起改成原版的两表结构，
          // 并把旧表里改过的值按 key 搬进 `configvalue`。默认值仍在
          // `configfield` 里，所以迁移后设置不会丢。
          for (final statement in _configSchema) {
            await db.execute(statement);
          }
          await _seedConfigFields(db);
          final fieldIds = <String, String>{
            for (final row
                in await db.query('configfield', columns: ['id', 'name']))
              row['name'] as String: row['id'] as String,
          };
          for (final row in await db.query('config')) {
            final fieldId = fieldIds[row['key'] as String];
            if (fieldId == null) continue;
            await db.insert('configvalue', {
              'field_id': fieldId,
              'value': row['value'],
              'id': _uuid(),
              'modified': _now(),
              'encrypted': null,
              'isEncrypted': row['isEncrypted'] ?? 0,
              'owner_id': null,
              'lastUpdatedBy_id': null,
            });
          }
          await db.execute('DROP TABLE IF EXISTS config');
        }
      },
    );
    // 开库耗时分解：定位那段开销具体花在哪一步（`adb logcat -s flutter` 可见）。
    // 实测结论：`getDatabasesPath()` 这个**首次异步平台调用**会占到 500~800ms，
    // 而 `openDatabase` 本身只要 11~34ms —— 所以慢的不是 SQLite。
    debugPrint(
      '开库分解: 取路径 ${t1.difference(t0).inMilliseconds}ms + '
      'openDatabase ${DateTime.now().difference(t1).inMilliseconds}ms',
    );
    final instance = JuiceDatabase._(db);
    _instance = instance;
    return instance;
  }

  /// @brief 关闭数据库并清空单例（测试与退出时用）。
  Future<void> close() async {
    await _db.close();
    _instance = null;
  }

  /// @brief 底层 sqflite 句柄，供少数需要直接发 SQL 的调用方使用。
  Database get raw => _db;

  /// @brief 全部建表与建索引语句。
  ///
  /// 列名与原版 ORMLite 的字段名一致；
  /// `group` / `key` 是 SQL 关键字，统一加双引号。
  static const List<String> _schema = <String>[
    '''
    CREATE TABLE connection (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nickname TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '',
      port INTEGER NOT NULL DEFAULT 22,
      type TEXT NOT NULL DEFAULT 'ssh',
      "group" INTEGER REFERENCES connectiongroup(id) ON DELETE SET NULL,
      via INTEGER REFERENCES connection(id) ON DELETE SET NULL,
      snippet INTEGER REFERENCES snippet(id) ON DELETE SET NULL,
      mosh_command TEXT,
      backspaceMode INTEGER NOT NULL DEFAULT 0,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    'CREATE INDEX connection_id_idx ON connection(id)',
    '''
    CREATE TABLE connectiongroup (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL DEFAULT '',
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    '''
    CREATE TABLE connectiongroupmembership (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      "group" INTEGER NOT NULL REFERENCES connectiongroup(id) ON DELETE CASCADE,
      connection INTEGER NOT NULL REFERENCES connection(id) ON DELETE CASCADE,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    'CREATE UNIQUE INDEX cgm_pair_idx ON connectiongroupmembership("group", connection)',
    '''
    CREATE TABLE connectionidentity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      connection INTEGER NOT NULL REFERENCES connection(id) ON DELETE CASCADE,
      identity INTEGER NOT NULL REFERENCES identity(id) ON DELETE CASCADE,
      position INTEGER NOT NULL DEFAULT 0,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    'CREATE UNIQUE INDEX ci_pair_idx ON connectionidentity(connection, identity)',
    '''
    CREATE TABLE identity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nickname TEXT NOT NULL DEFAULT '',
      username TEXT,
      password TEXT,
      privatekey TEXT,
      privatekeyPassword TEXT,
      passUpdated INTEGER,
      keyUpdated INTEGER,
      snippet INTEGER REFERENCES snippet(id) ON DELETE SET NULL,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    '''
    CREATE TABLE snippet (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      count INTEGER NOT NULL DEFAULT 0,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    '''
    CREATE TABLE portforward (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL DEFAULT '',
      mode INTEGER NOT NULL DEFAULT 0,
      connection INTEGER REFERENCES connection(id) ON DELETE CASCADE,
      host TEXT,
      localPort INTEGER,
      remotePort INTEGER,
      openInBrowser INTEGER NOT NULL DEFAULT 0,
      useAsProxy INTEGER NOT NULL DEFAULT 0,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    '''
    CREATE TABLE host (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL DEFAULT '',
      fingerprint TEXT,
      key TEXT NOT NULL DEFAULT '',
      type TEXT NOT NULL DEFAULT '',
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    'CREATE UNIQUE INDEX host_hostname_idx ON host(hostname)',
    '''
    CREATE TABLE connectioncounter (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      connection INTEGER NOT NULL REFERENCES connection(id) ON DELETE CASCADE,
      count INTEGER NOT NULL DEFAULT 0,
      modified INTEGER,
      encrypted TEXT,
      isEncrypted INTEGER NOT NULL DEFAULT 0,
      owner INTEGER,
      lastUpdatedBy INTEGER
    )
    ''',
    'CREATE UNIQUE INDEX counter_connection_idx ON connectioncounter(connection)',
    // 配置表与原版一致：`configfield`（键定义 + 默认值）+ `configvalue`
    // （只存改过的值）。单独成表是为了升级时能只跑这一段。
    ..._configSchema,
  ];

  /// @brief 原版 `configfield` 的 25 条「键 + 默认值」，逐条抄自运行中的原版库。
  ///
  /// 顺序即原版的写入顺序。原版把 `session:timeout`、`pinlock:enabled`
  /// 这类东西放在加密的 `session:cache` JSON 里，因此它们**不**在这份清单中。
  static const List<(String, String)> _configDefaults = [
    ('notifications:enabled', 'true'),
    ('terminal:font_size', '8'),
    ('terminal:type', 'linux'),
    ('terminal:utf8', 'true'),
    ('terminal:keyboard_position', '1'),
    ('terminal:theme', '2'),
    ('terminal:bell_mode', '0'),
    ('terminal:autocomplete', '0'),
    ('terminal:horizontal_swipe_mode', '0'),
    ('mosh:mosh-server', 'mosh-server new -s -l LANG=en_US.UTF-8'),
    ('tutorial:terminal', 'false'),
    ('last:cloudsync', '0'),
    ('last:teamshare', '0'),
    ('cloudsync:enabled', 'false'),
    ('cloudsync:identities', 'true'),
    ('session:cache', ''),
    ('pinlock:style', '2'),
    ('pinlock:pin', ''),
    ('changelog:seen_auth_migration_message', 'false'),
    ('version:code', '0'),
    // 参考机那份库这里是遗留值 `-1`（第 62 轮实测它在原版里落到 Dark）。但用户反馈
    // 实际使用的原版是**亮色**启动，且 `-1` 不在原版 `arrays.xml` 的取值表内
    // （3 = Automatic / 1 = Light / 2 = Dark），属旧版遗留。按开箱默认改成 Light。
    ('theme:dark', '1'),
    ('terminal:margin', '0'),
    ('terminal:margin_selection', '0'),
    ('ssh:agent', 'false'),
    ('terminal:font', ''),
  ];

  /// @brief 配置两表的建表语句，逐字取自原版真实库。
  static const List<String> _configSchema = [
    '''
    CREATE TABLE `configfield` (`defaultValue` VARCHAR , `name` VARCHAR , `encrypted` VARCHAR , `id` VARCHAR , `isEncrypted` SMALLINT , `lastUpdatedBy_id` VARCHAR , `modified` BIGINT , `owner_id` VARCHAR , PRIMARY KEY (`id`) )
    ''',
    '''
    CREATE TABLE `configvalue` (`field_id` VARCHAR , `value` VARCHAR , `id` VARCHAR , `modified` BIGINT , `encrypted` VARCHAR , `isEncrypted` SMALLINT , `owner_id` VARCHAR , `lastUpdatedBy_id` VARCHAR , PRIMARY KEY (`id`) )
    ''',
    'CREATE INDEX `configfield_id_idx` ON `configfield` ( `id` )',
    'CREATE INDEX `configfield_name_idx` ON `configfield` ( `name` )',
    'CREATE INDEX `configvalue_id_idx` ON `configvalue` ( `id` )',
  ];

  /// @brief 生成 UUID 用的随机源
  static final Random _random = Random();

  /// @brief 生成 UUID v4 字符串。
  ///
  /// 与原版 ORMLite 给 `@DatabaseField(id = true) String id`
  /// 生成的形态一致（原版库里的 `configfield.id` 就是这种串）。
  static String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// @brief 写入 `configfield` 的键定义与默认值。
  ///
  /// 按 `name` 去重，重复调用不会重复插入。
  static Future<void> _seedConfigFields(DatabaseExecutor db) async {
    final existing = <String>{
      for (final row in await db.query('configfield', columns: ['name']))
        row['name'] as String,
    };
    final batch = db.batch();
    var inserted = 0;
    for (final (name, value) in _configDefaults) {
      if (existing.contains(name)) continue;
      batch.insert('configfield', {
        'defaultValue': value,
        'name': name,
        'encrypted': null,
        'id': _uuid(),
        'isEncrypted': 0,
        'lastUpdatedBy_id': null,
        'modified': _now(),
        'owner_id': null,
      });
      inserted++;
    }
    if (inserted > 0) await batch.commit(noResult: true);
  }

  /// @brief 当前时间戳（毫秒），写入 `modified` 列用。
  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ------------------------------------------------------------------ 连接 --

  /// @brief 全部连接，按昵称不区分大小写升序。
  Future<List<Connection>> connections() async {
    final rows = await _db.query('connection', orderBy: 'nickname COLLATE NOCASE ASC');
    return rows.map(Connection.fromMap).toList();
  }

  /// @brief 按 id 取单条连接，不存在返回 null。
  Future<Connection?> connection(int id) async {
    final rows = await _db.query('connection', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Connection.fromMap(rows.first);
  }

  /// @brief 新增或更新一条连接，返回其 id（id 为 0 表示新增）。
  Future<int> saveConnection(Connection value) async {
    final map = value.toMap()..['modified'] = _now();
    if (value.id == 0) {
      final id = await _db.insert('connection', map);
      return id;
    }
    await _db.update('connection', map, where: 'id = ?', whereArgs: [value.id]);
    return value.id;
  }

  /// @brief 按 id 删除连接（级联清掉其身份/分组关联与计数器）。
  Future<void> deleteConnection(int id) async {
    await _db.delete('connection', where: 'id = ?', whereArgs: [id]);
  }

  /// @brief 连接名 -> 该连接配置的身份，按尝试顺序。
  Future<List<int>> connectionIdentityIds(int connectionId) async {
    final rows = await _db.query(
      'connectionidentity',
      columns: ['identity'],
      where: 'connection = ?',
      whereArgs: [connectionId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map((row) => (row['identity'] as num).toInt()).toList();
  }

  /// @brief 整体替换某条连接的身份列表，`position` 按列表下标写入。
  Future<void> setConnectionIdentities(int connectionId, List<int> identityIds) async {
    await _db.transaction((txn) async {
      await txn.delete('connectionidentity', where: 'connection = ?', whereArgs: [connectionId]);
      for (var i = 0; i < identityIds.length; i++) {
        await txn.insert('connectionidentity', {
          'connection': connectionId,
          'identity': identityIds[i],
          'position': i,
          'modified': _now(),
        });
      }
    });
  }

  /// @brief 连接 -> 所属分组 id 集合。
  Future<List<int>> groupIdsForConnection(int connectionId) async {
    final rows = await _db.query(
      'connectiongroupmembership',
      columns: ['"group"'],
      where: 'connection = ?',
      whereArgs: [connectionId],
    );
    return rows.map((row) => (row['group'] as num).toInt()).toList();
  }

  /// @brief 整体替换某条连接的分组列表（先清空再按列表写入）。
  Future<void> setConnectionGroups(int connectionId, List<int> groupIds) async {
    await _db.transaction((txn) async {
      await txn.delete('connectiongroupmembership',
          where: 'connection = ?', whereArgs: [connectionId]);
      for (final groupId in groupIds) {
        await txn.insert('connectiongroupmembership', {
          'group': groupId,
          'connection': connectionId,
          'modified': _now(),
        });
      }
    });
  }

  /// @brief 使用次数 +1（无行则插入 1），用于"常用连接"与按使用频率排序。
  Future<void> incrementConnectionCounter(int connectionId) async {
    await _db.rawInsert(
      'INSERT INTO connectioncounter (connection, count, modified) VALUES (?, 1, ?) '
      'ON CONFLICT(connection) DO UPDATE SET count = count + 1, modified = ?',
      [connectionId, _now(), _now()],
    );
  }

  /// @brief 全部连接的 id -> 使用次数映射。
  Future<Map<int, int>> connectionCounters() async {
    final rows = await _db.query('connectioncounter', columns: ['connection', 'count']);
    return {
      for (final row in rows)
        (row['connection'] as num).toInt(): (row['count'] as num).toInt(),
    };
  }

  /// @brief 清空某条连接的连接历史（长按菜单的 "Clear history"）。
  ///
  /// 对应连接长按菜单里的 "Clear history"：把 `connectioncounter` 里
  /// 该连接那一行删掉，使用次数即回到「从未连接」。
  Future<void> clearConnectionCounter(int connectionId) async {
    await _db.delete(
      'connectioncounter',
      where: 'connection = ?',
      whereArgs: [connectionId],
    );
  }

  // ------------------------------------------------------------------ 分组 --

  /// @brief 全部分组，按名称不区分大小写升序。
  Future<List<ConnectionGroup>> groups() async {
    final rows = await _db.query('connectiongroup', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(ConnectionGroup.fromMap).toList();
  }

  /// @brief 新增或更新一个分组，返回其 id。
  Future<int> saveGroup(ConnectionGroup value) async {
    final map = value.toMap()..['modified'] = _now();
    if (value.id == 0) return _db.insert('connectiongroup', map);
    await _db.update('connectiongroup', map, where: 'id = ?', whereArgs: [value.id]);
    return value.id;
  }

  /// @brief 按 id 删除分组（成员关系级联删除，连接本身保留）。
  Future<void> deleteGroup(int id) async {
    await _db.delete('connectiongroup', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------ 身份 --

  /// @brief 全部身份，按昵称不区分大小写升序。
  Future<List<Identity>> identities() async {
    final rows = await _db.query('identity', orderBy: 'nickname COLLATE NOCASE ASC');
    return rows.map(Identity.fromMap).toList();
  }

  /// @brief 按 id 取单个身份，不存在返回 null。
  Future<Identity?> identity(int id) async {
    final rows = await _db.query('identity', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Identity.fromMap(rows.first);
  }

  /// @brief 新增或更新一个身份，返回其 id。
  Future<int> saveIdentity(Identity value) async {
    final map = value.toMap()..['modified'] = _now();
    if (value.id == 0) return _db.insert('identity', map);
    await _db.update('identity', map, where: 'id = ?', whereArgs: [value.id]);
    return value.id;
  }

  /// @brief 按 id 删除身份（连接与它的关联级联删除）。
  Future<void> deleteIdentity(int id) async {
    await _db.delete('identity', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------ 片段 --

  /// @brief 全部片段，按名称不区分大小写升序。
  Future<List<Snippet>> snippets() async {
    final rows = await _db.query('snippet', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Snippet.fromMap).toList();
  }

  /// @brief 新增或更新一个片段，返回其 id。
  Future<int> saveSnippet(Snippet value) async {
    final map = value.toMap()..['modified'] = _now();
    if (value.id == 0) return _db.insert('snippet', map);
    await _db.update('snippet', map, where: 'id = ?', whereArgs: [value.id]);
    return value.id;
  }

  /// @brief 按 id 删除片段。
  Future<void> deleteSnippet(int id) async {
    await _db.delete('snippet', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------- 端口转发 --

  /// @brief 全部端口转发规则，按名称不区分大小写升序。
  Future<List<PortForward>> portForwards() async {
    final rows = await _db.query('portforward', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(PortForward.fromMap).toList();
  }

  /// @brief 新增或更新一条端口转发规则，返回其 id。
  Future<int> savePortForward(PortForward value) async {
    final map = value.toMap()..['modified'] = _now();
    if (value.id == 0) return _db.insert('portforward', map);
    await _db.update('portforward', map, where: 'id = ?', whereArgs: [value.id]);
    return value.id;
  }

  /// @brief 按 id 删除一条端口转发规则。
  Future<void> deletePortForward(int id) async {
    await _db.delete('portforward', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------- 已知主机 --

  /// @brief 全部已知主机，按主机名不区分大小写升序。
  Future<List<KnownHost>> knownHosts() async {
    final rows = await _db.query('host', orderBy: 'hostname COLLATE NOCASE ASC');
    return rows.map(KnownHost.fromMap).toList();
  }

  /// @brief 按主机名取已知主机，没有记录返回 null。
  Future<KnownHost?> knownHost(String hostname) async {
    final rows = await _db.query('host', where: 'hostname = ?', whereArgs: [hostname], limit: 1);
    return rows.isEmpty ? null : KnownHost.fromMap(rows.first);
  }

  /// @brief 新增或更新一条已知主机，返回其 id。
  ///
  /// 主机名有唯一索引，所以 id 为 0 但同名记录已存在时改为更新那一行。
  Future<int> saveKnownHost(KnownHost value) async {
    final map = value.toMap()..['modified'] = _now();
    if (value.id == 0) {
      final existing = await knownHost(value.hostname);
      if (existing != null) {
        map['id'] = existing.id;
        await _db.update('host', map, where: 'id = ?', whereArgs: [existing.id]);
        return existing.id;
      }
      return _db.insert('host', map);
    }
    await _db.update('host', map, where: 'id = ?', whereArgs: [value.id]);
    return value.id;
  }

  /// @brief 按 id 删除一条已知主机。
  Future<void> deleteKnownHost(int id) async {
    await _db.delete('host', where: 'id = ?', whereArgs: [id]);
  }

  /// @brief 清空全部已知主机（设置页的 "Clear known hosts"）。
  Future<void> clearKnownHosts() async {
    await _db.delete('host');
  }

  // ------------------------------------------------------------------ 设置 --

  /// @brief 读全部设置，键名 → 生效值。
  ///
  /// 有 `configvalue` 行就用它，否则用 `configfield.defaultValue`。
  ///
  /// 原版对 `terminal:font`、`pinlock:pin`、`session:cache` 这类字符串键用空串
  /// 表示"未设置"，这里读出来统一折成 null，交给各自的默认逻辑处理。
  Future<Map<String, String?>> allConfig() async {
    final rows = await _db.rawQuery(
      'SELECT f.name AS name, COALESCE(v.value, f.defaultValue) AS value '
      'FROM configfield f LEFT JOIN configvalue v ON v.field_id = f.id',
    );
    return {
      for (final row in rows)
        row['name'] as String: _normalize(row['value'] as String?),
    };
  }

  /// @brief 读单个设置项的生效值，键不存在返回 null。
  Future<String?> config(String key) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(v.value, f.defaultValue) AS value FROM configfield f '
      'LEFT JOIN configvalue v ON v.field_id = f.id WHERE f.name = ? LIMIT 1',
      [key],
    );
    return rows.isEmpty ? null : _normalize(rows.first['value'] as String?);
  }

  /// @brief 把空串（原版的"未设置"）统一折成 null。
  static String? _normalize(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  /// @brief 写一个设置项；值为 null 时等价于删除覆盖值。
  ///
  /// 只写 `configvalue`。
  ///
  /// 原版的键都先在 `configfield` 里声明过；本地复刻另外用到几个原版不放在
  /// 配置表里的键（PIN 与 `session:timeout` —— 原版把它们塞在加密的
  /// `session:cache` 里），首次写入时按需补一条 `configfield` 定义。这样干净
  /// 安装时 `configfield` 仍与原版逐行一致（都是 25 条）。
  Future<void> setConfig(String key, String? value,
      {bool isEncrypted = false}) async {
    if (value == null) return removeConfig(key);
    var field = await _db.query(
      'configfield',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (field.isEmpty) {
      await _db.insert('configfield', {
        'defaultValue': '',
        'name': key,
        'encrypted': null,
        'id': _uuid(),
        'isEncrypted': 0,
        'lastUpdatedBy_id': null,
        'modified': _now(),
        'owner_id': null,
      });
      field = await _db.query(
        'configfield',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [key],
        limit: 1,
      );
    }
    final fieldId = field.first['id'] as String;
    final payload = {
      'field_id': fieldId,
      'value': value,
      'modified': _now(),
      'encrypted': null,
      'isEncrypted': isEncrypted ? 1 : 0,
      'owner_id': null,
      'lastUpdatedBy_id': null,
    };
    final existing = await _db.query(
      'configvalue',
      columns: ['id'],
      where: 'field_id = ?',
      whereArgs: [fieldId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _db.insert('configvalue', {...payload, 'id': _uuid()});
    } else {
      await _db.update(
        'configvalue',
        payload,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  /// @brief 删掉某个键的覆盖值 —— 之后它回落到 `configfield` 里的默认值。
  Future<void> removeConfig(String key) async {
    await _db.rawDelete(
      'DELETE FROM configvalue WHERE field_id IN '
      '(SELECT id FROM configfield WHERE name = ?)',
      [key],
    );
  }

  /// @brief 清空全部覆盖值（键定义与默认值保留）。
  Future<void> clearConfig() async {
    await _db.delete('configvalue');
  }

  // ------------------------------------------------------------------ 备份 --

  /// @brief 导出全部业务数据，用于备份/恢复。
  ///
  /// 原版的备份是云端 AES 加密对象，这里提供一个等价的本地明文导出，
  /// 便于调试与迁移。
  Future<Map<String, Object?>> exportAll() async {
    return {
      'version': schemaVersion,
      'connection': await _db.query('connection'),
      'connectiongroup': await _db.query('connectiongroup'),
      'connectiongroupmembership': await _db.query('connectiongroupmembership'),
      'connectionidentity': await _db.query('connectionidentity'),
      'identity': await _db.query('identity'),
      'snippet': await _db.query('snippet'),
      'portforward': await _db.query('portforward'),
      'host': await _db.query('host'),
      'connectioncounter': await _db.query('connectioncounter'),
      'configvalue': await _db.query('configvalue'),
    };
  }

  /// @brief 用导出的数据整体覆盖本地库。调用方需自行确认。
  Future<void> importAll(Map<String, Object?> payload) async {
    const tables = [
      'connectionidentity',
      'connectiongroupmembership',
      'connectioncounter',
      'portforward',
      'connection',
      'connectiongroup',
      'identity',
      'snippet',
      'host',
      'configvalue',
    ];
    await _db.transaction((txn) async {
      for (final table in tables) {
        await txn.delete(table);
      }
      for (final table in tables.reversed) {
        final rows = payload[table];
        if (rows is! List) continue;
        for (final row in rows) {
          await txn.insert(table, Map<String, Object?>.from(row as Map));
        }
      }
    });
  }
}
