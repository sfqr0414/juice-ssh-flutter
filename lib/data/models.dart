/// 数据模型 —— 字段与原版 JuiceSSH 3.2.2 的 ORMLite 实体一一对应。
///
/// 表结构与字段名的依据是包里的 `res/raw/ormlite_config.txt`
/// （ORMLite 自动生成的配置，列出了每张表的每个字段、主键、外键与列名映射）。
/// 这样做的目的是让数据库内容与原版可对照，便于日后做备份互通。
library;

import 'dart:convert';

/// @brief 连接类型，取值为 ssh / telnet / mosh / local；没有 ssh-forward。
///
/// 取值依据 `AndroidManifest.xml` 里 TerminalEmulatorActivity
/// 注册的 scheme：ssh / ssh-forward / telnet / local / mosh。
enum ConnectionType {
  /// @brief SSH 连接 —— 默认类型
  ssh('ssh'),

  /// @brief Telnet 连接
  telnet('telnet'),

  /// @brief Mosh 连接（依赖服务端 mosh-server）
  mosh('mosh'),

  /// @brief 本地终端，不建立网络连接
  local('local');

  /// @brief 用枚举值字符串构造，如 `ConnectionType('ssh')`
  const ConnectionType(this.value);

  /// @brief 持久化到数据库 `connection.type` 的字符串
  final String value;

  /// @brief 把数据库里的字符串解析成类型，未知值回落到 ssh
  static ConnectionType fromValue(String? raw) => ConnectionType.values.firstWhere(
        (type) => type.value == raw,
        orElse: () => ConnectionType.ssh,
      );

  /// @brief 对应的 i18n 键名，由界面层翻译成显示名。
  ///
  /// 对应 `@string/` 里的显示名，交由界面层用 i18n 取。
  String get labelKey => switch (this) {
        ConnectionType.ssh => 'connection_type_ssh',
        ConnectionType.telnet => 'connection_type_telnet',
        ConnectionType.mosh => 'connection_type_mosh',
        ConnectionType.local => 'connection_type_local',
      };
}

/// @brief 端口转发模式，对应 `PortForward.mode` 字段。
enum PortForwardMode {
  /// @brief 本地转发（-L）
  local(0),

  /// @brief 远程转发（-R）
  remote(1),

  /// @brief 动态转发 / SOCKS 代理（-D）
  dynamic(2);

  /// @brief 用枚举值整数构造
  const PortForwardMode(this.value);

  /// @brief 持久化到数据库 `portforward.mode` 的整数
  final int value;

  /// @brief 把数据库里的整数解析成模式，未知值回落到 local
  static PortForwardMode fromValue(int? raw) => PortForwardMode.values.firstWhere(
        (mode) => mode.value == raw,
        orElse: () => PortForwardMode.local,
      );
}

/// @brief 终端里退格键发送的字节，对应 `Connection.backspaceMode`。
enum BackspaceMode {
  /// @brief 发送 DEL (0x7F) —— 原版默认
  del(0, 'backspace_mode_del'),

  /// @brief 发送 BS (0x08)
  backspace(1, 'backspace_mode_backspace');

  /// @brief 用整数值与 i18n 标签键构造
  const BackspaceMode(this.value, this.labelKey);

  /// @brief 持久化到数据库 `connection.backspaceMode` 的整数
  final int value;

  /// @brief 对应的 i18n 标签键名
  final String labelKey;

  /// @brief 把数据库里的整数解析成模式，未知值回落到 del
  static BackspaceMode fromValue(int? raw) => BackspaceMode.values.firstWhere(
        (mode) => mode.value == raw,
        orElse: () => BackspaceMode.del,
      );
}

/// @brief 所有实体共有的同步元数据字段（原版的 BaseModel）。
mixin SyncMetadata {
  /// @brief 主键
  int get id;

  /// @brief 最后修改时间戳（毫秒），云同步冲突判定用
  int? get modified;

  /// @brief 加密后的载荷，解密后才是明文
  String? get encrypted;

  /// @brief 该行是否加密存储
  bool get isEncrypted;

  /// @brief 所属用户的云同步 id
  int? get owner;

  /// @brief 最后修改该行的用户 id
  int? get lastUpdatedBy;
}

/// @brief `connection` 表 —— 一条保存好的连接配置。
///
/// 注意 `via` 是指向本表的自引用外键，表示"经由某台跳板机连接"。
class Connection with SyncMetadata {
  /// @brief 构造一条连接，默认 id 为 0、端口 22、类型 ssh。
  const Connection({
    this.id = 0,
    required this.nickname,
    required this.address,
    this.port = 22,
    this.type = ConnectionType.ssh,
    this.groupId,
    this.viaId,
    this.snippetId,
    this.moshCommand,
    this.backspaceMode = BackspaceMode.del,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `nickname` —— 显示名
  final String nickname;

  /// @brief `address` —— 主机名或 IP
  final String address;

  /// @brief `port`
  final int port;

  /// @brief `type` —— ssh / telnet / mosh / local
  final ConnectionType type;

  /// @brief `group` —— 外键，指向 connectiongroup
  final int? groupId;

  /// @brief `via` —— 外键，指向另一条 connection（跳板机）
  final int? viaId;

  /// @brief `snippet` —— 外键，连接成功后自动执行
  final int? snippetId;

  /// @brief `mosh_command` —— 列名映射为 mosh_command
  final String? moshCommand;

  /// @brief `backspaceMode`
  final BackspaceMode backspaceMode;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 复制一份并按传入参数覆盖字段，`clearXxx` 用于显式置空外键。
  Connection copyWith({
    int? id,
    String? nickname,
    String? address,
    int? port,
    ConnectionType? type,
    int? groupId,
    bool clearGroup = false,
    int? viaId,
    bool clearVia = false,
    int? snippetId,
    bool clearSnippet = false,
    String? moshCommand,
    BackspaceMode? backspaceMode,
    int? modified,
  }) =>
      Connection(
        id: id ?? this.id,
        nickname: nickname ?? this.nickname,
        address: address ?? this.address,
        port: port ?? this.port,
        type: type ?? this.type,
        groupId: clearGroup ? null : (groupId ?? this.groupId),
        viaId: clearVia ? null : (viaId ?? this.viaId),
        snippetId: clearSnippet ? null : (snippetId ?? this.snippetId),
        moshCommand: moshCommand ?? this.moshCommand,
        backspaceMode: backspaceMode ?? this.backspaceMode,
        modified: modified ?? this.modified,
        encrypted: encrypted,
        isEncrypted: isEncrypted,
        owner: owner,
        lastUpdatedBy: lastUpdatedBy,
      );

  /// @brief 转成 `connection` 表的列名 → 值映射（id 为 0 时不写该列）。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'nickname': nickname,
        'address': address,
        'port': port,
        'type': type.value,
        'group': groupId,
        'via': viaId,
        'snippet': snippetId,
        'mosh_command': moshCommand,
        'backspaceMode': backspaceMode.value,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `connection` 表的一行还原对象，缺失字段回落到默认值。
  static Connection fromMap(Map<String, Object?> map) => Connection(
        id: (map['id'] as num?)?.toInt() ?? 0,
        nickname: '${map['nickname'] ?? ''}',
        address: '${map['address'] ?? ''}',
        port: (map['port'] as num?)?.toInt() ?? 22,
        type: ConnectionType.fromValue(map['type'] as String?),
        groupId: (map['group'] as num?)?.toInt(),
        viaId: (map['via'] as num?)?.toInt(),
        snippetId: (map['snippet'] as num?)?.toInt(),
        moshCommand: map['mosh_command'] as String?,
        backspaceMode: BackspaceMode.fromValue((map['backspaceMode'] as num?)?.toInt()),
        modified: (map['modified'] as num?)?.toInt(),
        encrypted: map['encrypted'] as String?,
        isEncrypted: ((map['isEncrypted'] as num?)?.toInt() ?? 0) == 1,
        owner: (map['owner'] as num?)?.toInt(),
        lastUpdatedBy: (map['lastUpdatedBy'] as num?)?.toInt(),
      );
}

/// @brief `connectiongroup` 表，连接分组。
///
/// 原版**没有标签（tag）功能**，分组是唯一的归类方式。
class ConnectionGroup with SyncMetadata {
  /// @brief 构造一个连接分组，默认 id 为 0。
  const ConnectionGroup({
    this.id = 0,
    required this.name,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `name` —— 分组名
  final String name;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 复制一份并按传入参数覆盖字段。
  ConnectionGroup copyWith({int? id, String? name, int? modified}) => ConnectionGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        modified: modified ?? this.modified,
      );

  /// @brief 转成 `connectiongroup` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'name': name,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `connectiongroup` 表的一行还原对象。
  static ConnectionGroup fromMap(Map<String, Object?> map) => ConnectionGroup(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: '${map['name'] ?? ''}',
        modified: (map['modified'] as num?)?.toInt(),
        encrypted: map['encrypted'] as String?,
        isEncrypted: ((map['isEncrypted'] as num?)?.toInt() ?? 0) == 1,
        owner: (map['owner'] as num?)?.toInt(),
        lastUpdatedBy: (map['lastUpdatedBy'] as num?)?.toInt(),
      );
}

/// @brief `identity` 表 —— 一套登录凭据（用户名 + 密码或私钥）。
class Identity with SyncMetadata {
  /// @brief 构造一套身份凭据，默认无密码与私钥。
  const Identity({
    this.id = 0,
    required this.nickname,
    this.username,
    this.password,
    this.privateKey,
    this.privateKeyPassword,
    this.passUpdated,
    this.keyUpdated,
    this.snippetId,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `nickname`
  final String nickname;

  /// @brief `username`
  final String? username;

  /// @brief `password`
  final String? password;

  /// @brief `privatekey` —— PEM / OpenSSH 私钥文本
  final String? privateKey;

  /// @brief `privatekeyPassword` —— 私钥口令
  final String? privateKeyPassword;

  /// @brief `passUpdated` —— 密码最后修改时间戳，用于云同步冲突判定
  final int? passUpdated;

  /// @brief `keyUpdated` —— 私钥最后修改时间戳，用于云同步冲突判定
  final int? keyUpdated;

  /// @brief `snippet` —— 登录成功后自动执行
  final int? snippetId;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 是否配置了私钥（按去空白后非空判断）。
  bool get hasPrivateKey => (privateKey ?? '').trim().isNotEmpty;

  /// @brief 是否配置了密码。
  bool get hasPassword => (password ?? '').isNotEmpty;

  /// @brief 复制一份并按传入参数覆盖字段，`clearXxx` 用于显式置空凭据。
  Identity copyWith({
    int? id,
    String? nickname,
    String? username,
    String? password,
    bool clearPassword = false,
    String? privateKey,
    bool clearPrivateKey = false,
    String? privateKeyPassword,
    bool clearPrivateKeyPassword = false,
    int? snippetId,
    bool clearSnippet = false,
    int? passUpdated,
    int? keyUpdated,
    int? modified,
  }) =>
      Identity(
        id: id ?? this.id,
        nickname: nickname ?? this.nickname,
        username: username ?? this.username,
        password: clearPassword ? null : (password ?? this.password),
        privateKey: clearPrivateKey ? null : (privateKey ?? this.privateKey),
        privateKeyPassword: clearPrivateKeyPassword
            ? null
            : (privateKeyPassword ?? this.privateKeyPassword),
        snippetId: clearSnippet ? null : (snippetId ?? this.snippetId),
        passUpdated: passUpdated ?? this.passUpdated,
        keyUpdated: keyUpdated ?? this.keyUpdated,
        modified: modified ?? this.modified,
        encrypted: encrypted,
        isEncrypted: isEncrypted,
        owner: owner,
        lastUpdatedBy: lastUpdatedBy,
      );

  /// @brief 转成 `identity` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'nickname': nickname,
        'username': username,
        'password': password,
        'privatekey': privateKey,
        'privatekeyPassword': privateKeyPassword,
        'passUpdated': passUpdated,
        'keyUpdated': keyUpdated,
        'snippet': snippetId,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `identity` 表的一行还原对象。
  static Identity fromMap(Map<String, Object?> map) => Identity(
        id: (map['id'] as num?)?.toInt() ?? 0,
        nickname: '${map['nickname'] ?? ''}',
        username: map['username'] as String?,
        password: map['password'] as String?,
        privateKey: map['privatekey'] as String?,
        privateKeyPassword: map['privatekeyPassword'] as String?,
        passUpdated: (map['passUpdated'] as num?)?.toInt(),
        keyUpdated: (map['keyUpdated'] as num?)?.toInt(),
        snippetId: (map['snippet'] as num?)?.toInt(),
        modified: (map['modified'] as num?)?.toInt(),
        encrypted: map['encrypted'] as String?,
        isEncrypted: ((map['isEncrypted'] as num?)?.toInt() ?? 0) == 1,
        owner: (map['owner'] as num?)?.toInt(),
        lastUpdatedBy: (map['lastUpdatedBy'] as num?)?.toInt(),
      );
}

/// @brief `connectionidentity` 表 —— 连接与身份的多对多关联。
///
/// 这是原版一个容易被忽略的能力：一条连接可以挂多个身份，
/// 登录时按顺序逐个尝试，直到某个身份通过认证。
class ConnectionIdentity with SyncMetadata {
  /// @brief 构造一条连接与身份的关联记录。
  const ConnectionIdentity({
    this.id = 0,
    required this.connectionId,
    required this.identityId,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `connection` —— 外键，指向 connection
  final int connectionId;

  /// @brief `identity` —— 外键，指向 identity
  final int identityId;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 转成 `connectionidentity` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'connection': connectionId,
        'identity': identityId,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `connectionidentity` 表的一行还原对象。
  static ConnectionIdentity fromMap(Map<String, Object?> map) => ConnectionIdentity(
        id: (map['id'] as num?)?.toInt() ?? 0,
        connectionId: (map['connection'] as num?)?.toInt() ?? 0,
        identityId: (map['identity'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// @brief `snippet` 表 —— 一段可复用的命令，可在连接建立后自动执行。
class Snippet with SyncMetadata {
  /// @brief 构造一个片段，默认 id 为 0、使用次数 0。
  const Snippet({
    this.id = 0,
    required this.name,
    required this.content,
    this.count = 0,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `name` —— 片段名
  final String name;

  /// @brief `content` —— 要执行的命令文本
  final String content;

  /// @brief `count` —— 使用次数，用于"常用"排序
  final int count;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 复制一份并按传入参数覆盖字段。
  Snippet copyWith({int? id, String? name, String? content, int? count, int? modified}) => Snippet(
        id: id ?? this.id,
        name: name ?? this.name,
        content: content ?? this.content,
        count: count ?? this.count,
        modified: modified ?? this.modified,
      );

  /// @brief 转成 `snippet` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'name': name,
        'content': content,
        'count': count,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `snippet` 表的一行还原对象。
  static Snippet fromMap(Map<String, Object?> map) => Snippet(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: '${map['name'] ?? ''}',
        content: '${map['content'] ?? ''}',
        count: (map['count'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// @brief `portforward` 表 —— 端口转发规则。
class PortForward with SyncMetadata {
  /// @brief 构造一条端口转发规则，默认两个开关都关闭。
  const PortForward({
    this.id = 0,
    required this.name,
    required this.mode,
    this.connectionId,
    this.host,
    this.localPort,
    this.remotePort,
    this.openInBrowser = false,
    this.useAsProxy = false,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `name` —— 转发规则名
  final String name;

  /// @brief `mode` —— 本地 / 远程 / 动态
  final PortForwardMode mode;

  /// @brief `connection` —— 外键，指向承载该转发的连接
  final int? connectionId;

  /// @brief `host` —— 目标主机（本地/远程转发的目标地址）
  final String? host;

  /// @brief `localPort` —— 本地端口
  final int? localPort;

  /// @brief `remotePort` —— 远程端口
  final int? remotePort;

  /// @brief `openInBrowser` —— 建立后自动打开浏览器
  final bool openInBrowser;

  /// @brief `useAsProxy` —— 编辑器里那个复选框。
  ///
  /// 注意：原版 3.2.2 里这个字段**只存不用** —— 全 smali 树里除了
  /// `ManagePortForwardActivity`（读写复选框）和模型本身，没有任何运行时引用；
  /// 转发运行时（`gi0.smali`）只读 `openInBrowser`。所以克隆同样只做持久化 +
  /// 编辑器展示，不接任何行为（不是缺口）。
  final bool useAsProxy;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 复制一份并按传入参数覆盖字段，`clearConnection` 用于解绑连接。
  PortForward copyWith({
    int? id,
    String? name,
    PortForwardMode? mode,
    int? connectionId,
    bool clearConnection = false,
    String? host,
    int? localPort,
    int? remotePort,
    bool? openInBrowser,
    bool? useAsProxy,
    int? modified,
  }) =>
      PortForward(
        id: id ?? this.id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        connectionId: clearConnection ? null : (connectionId ?? this.connectionId),
        host: host ?? this.host,
        localPort: localPort ?? this.localPort,
        remotePort: remotePort ?? this.remotePort,
        openInBrowser: openInBrowser ?? this.openInBrowser,
        useAsProxy: useAsProxy ?? this.useAsProxy,
        modified: modified ?? this.modified,
      );

  /// @brief 转成 `portforward` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'name': name,
        'mode': mode.value,
        'connection': connectionId,
        'host': host,
        'localPort': localPort,
        'remotePort': remotePort,
        'openInBrowser': openInBrowser ? 1 : 0,
        'useAsProxy': useAsProxy ? 1 : 0,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `portforward` 表的一行还原对象。
  static PortForward fromMap(Map<String, Object?> map) => PortForward(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: '${map['name'] ?? ''}',
        mode: PortForwardMode.fromValue((map['mode'] as num?)?.toInt()),
        connectionId: (map['connection'] as num?)?.toInt(),
        host: map['host'] as String?,
        localPort: (map['localPort'] as num?)?.toInt(),
        remotePort: (map['remotePort'] as num?)?.toInt(),
        openInBrowser: ((map['openInBrowser'] as num?)?.toInt() ?? 0) == 1,
        useAsProxy: ((map['useAsProxy'] as num?)?.toInt() ?? 0) == 1,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// @brief `host` 表 —— 已知主机（known hosts）。表名就叫 host。
class KnownHost with SyncMetadata {
  /// @brief 构造一条已知主机记录，默认 id 为 0。
  const KnownHost({
    this.id = 0,
    required this.hostname,
    required this.key,
    required this.type,
    this.fingerprint,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `hostname`
  final String hostname;

  /// @brief `key` —— 服务端公钥
  final String key;

  /// @brief `type` —— 密钥算法，例如 ssh-rsa / ssh-ed25519
  final String type;

  /// @brief `fingerprint`
  final String? fingerprint;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 转成 `host` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'hostname': hostname,
        'key': key,
        'type': type,
        'fingerprint': fingerprint,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `host` 表的一行还原对象。
  static KnownHost fromMap(Map<String, Object?> map) => KnownHost(
        id: (map['id'] as num?)?.toInt() ?? 0,
        hostname: '${map['hostname'] ?? ''}',
        key: '${map['key'] ?? ''}',
        type: '${map['type'] ?? ''}',
        fingerprint: map['fingerprint'] as String?,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// @brief `connectioncounter` 表 —— 每条连接的使用次数。
///
/// 供"常用连接"与按使用频率排序使用。
class ConnectionCounter with SyncMetadata {
  /// @brief 构造一条连接使用计数，默认 id 为 0、次数 0。
  const ConnectionCounter({
    this.id = 0,
    required this.connectionId,
    this.count = 0,
    this.modified,
    this.encrypted,
    this.isEncrypted = false,
    this.owner,
    this.lastUpdatedBy,
  });

  @override
  /// @brief 主键，0 表示尚未写库
  final int id;

  /// @brief `connection` —— 外键，指向 connection
  final int connectionId;

  /// @brief `count` —— 累计连接次数
  final int count;

  @override
  /// @brief 最后修改时间戳（毫秒）
  final int? modified;

  @override
  /// @brief 加密载荷，解密后是明文
  final String? encrypted;

  @override
  /// @brief 该行是否加密存储
  final bool isEncrypted;

  @override
  /// @brief 所属用户的云同步 id
  final int? owner;

  @override
  /// @brief 最后修改该行的用户 id
  final int? lastUpdatedBy;

  /// @brief 转成 `connectioncounter` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'connection': connectionId,
        'count': count,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

  /// @brief 从 `connectioncounter` 表的一行还原对象。
  static ConnectionCounter fromMap(Map<String, Object?> map) => ConnectionCounter(
        id: (map['id'] as num?)?.toInt() ?? 0,
        connectionId: (map['connection'] as num?)?.toInt() ?? 0,
        count: (map['count'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// @brief `connectiongroupmembership` 的行 —— 连接与分组的多对多关联。
///
/// 把 `ConnectionGroupMembership` 简化为一个 (connection, group) 值对象。
class ConnectionGroupMembership {
  /// @brief 用连接 id 与分组 id 构造
  const ConnectionGroupMembership({
    required this.connectionId,
    required this.groupId,
  });

  /// @brief `connection` —— 外键，指向 connection
  final int connectionId;

  /// @brief `group` —— 外键，指向 connectiongroup
  final int groupId;

  /// @brief 从 `connectiongroupmembership` 表的一行还原值对象。
  static ConnectionGroupMembership fromMap(Map<String, Object?> map) =>
      ConnectionGroupMembership(
        connectionId: (map['connection'] as num?)?.toInt() ?? 0,
        groupId: (map['group'] as num?)?.toInt() ?? 0,
      );
}

/// @brief 连接与身份的关联，带一个显示顺序。
///
/// 原版用插入顺序表示尝试顺序。
class ConnectionIdentityLink {
  /// @brief 用连接 id、身份 id 与顺序构造
  const ConnectionIdentityLink({
    required this.connectionId,
    required this.identityId,
    this.position = 0,
  });

  /// @brief `connection` —— 外键，指向 connection
  final int connectionId;

  /// @brief `identity` —— 外键，指向 identity
  final int identityId;

  /// @brief 认证尝试顺序，从 0 开始
  final int position;
}

/// @brief 一条设置项 —— 键名 + 值 + 是否加密。
///
/// 原版把设置规范化成 `configfield` + `configvalue` 两张表，目的是给单个字段
/// 加"是否加密"以及云同步元数据。本地复刻不需要这层间接，
/// 因此这里用一张 `config(key, value, isEncrypted)` 直接存储，
/// 键名与原版完全一致（如 `terminal:theme`、`pinlock:enabled`）。
class ConfigEntry {
  /// @brief 用键名、值与加密标记构造
  const ConfigEntry({
    required this.key,
    required this.value,
    this.isEncrypted = false,
  });

  /// @brief 设置键名，与原版 `configfield.name` 一致
  final String key;

  /// @brief 设置值，null 表示未设置
  final String? value;

  /// @brief 该值是否加密存储
  final bool isEncrypted;

  /// @brief 从 `config` 表的一行还原设置项。
  static ConfigEntry fromMap(Map<String, Object?> map) => ConfigEntry(
        key: '${map['key'] ?? ''}',
        value: map['value'] as String?,
        isEncrypted: ((map['isEncrypted'] as num?)?.toInt() ?? 0) == 1,
      );

  /// @brief 转成 `config` 表的列名 → 值映射。
  Map<String, Object?> toMap() => {
        'key': key,
        'value': value,
        'isEncrypted': isEncrypted ? 1 : 0,
      };
}

/// @brief 便于调试：把 map 里的值转成可读字符串。
String describeMap(Map<String, Object?> map) => json.encode(map);
