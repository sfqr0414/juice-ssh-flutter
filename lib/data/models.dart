/// 数据模型 —— 字段与原版 JuiceSSH 3.2.2 的 ORMLite 实体一一对应。
///
/// 表结构与字段名的依据是包里的 `res/raw/ormlite_config.txt`
/// （ORMLite 自动生成的配置，列出了每张表的每个字段、主键、外键与列名映射）。
/// 这样做的目的是让数据库内容与原版可对照，便于日后做备份互通。
library;

import 'dart:convert';

/// 连接类型。取值依据 `AndroidManifest.xml` 里 TerminalEmulatorActivity
/// 注册的 scheme：ssh / ssh-forward / telnet / local / mosh。
enum ConnectionType {
  ssh('ssh'),
  telnet('telnet'),
  mosh('mosh'),
  local('local');

  const ConnectionType(this.value);

  final String value;

  static ConnectionType fromValue(String? raw) => ConnectionType.values.firstWhere(
        (type) => type.value == raw,
        orElse: () => ConnectionType.ssh,
      );

  /// 对应 `@string/` 里的显示名，交由界面层用 i18n 取。
  String get labelKey => switch (this) {
        ConnectionType.ssh => 'connection_type_ssh',
        ConnectionType.telnet => 'connection_type_telnet',
        ConnectionType.mosh => 'connection_type_mosh',
        ConnectionType.local => 'connection_type_local',
      };
}

/// 端口转发模式。`PortForward.mode` 字段。
enum PortForwardMode {
  /// 本地转发（-L）
  local(0),

  /// 远程转发（-R）
  remote(1),

  /// 动态转发 / SOCKS 代理（-D）
  dynamic(2);

  const PortForwardMode(this.value);

  final int value;

  static PortForwardMode fromValue(int? raw) => PortForwardMode.values.firstWhere(
        (mode) => mode.value == raw,
        orElse: () => PortForwardMode.local,
      );
}

/// 终端里退格键发送的字节。`Connection.backspaceMode`。
enum BackspaceMode {
  /// 发送 DEL (0x7F) —— 原版默认
  del(0, 'backspace_mode_del'),

  /// 发送 BS (0x08)
  backspace(1, 'backspace_mode_backspace');

  const BackspaceMode(this.value, this.labelKey);

  final int value;
  final String labelKey;

  static BackspaceMode fromValue(int? raw) => BackspaceMode.values.firstWhere(
        (mode) => mode.value == raw,
        orElse: () => BackspaceMode.del,
      );
}

/// 所有实体共有的同步元数据字段（原版的 BaseModel）。
mixin SyncMetadata {
  int get id;
  int? get modified;
  String? get encrypted;
  bool get isEncrypted;
  int? get owner;
  int? get lastUpdatedBy;
}

/// `connection` 表。
///
/// 注意 `via` 是指向本表的自引用外键，表示"经由某台跳板机连接"。
class Connection with SyncMetadata {
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
  final int id;

  /// `nickname` —— 显示名
  final String nickname;

  /// `address` —— 主机名或 IP
  final String address;

  /// `port`
  final int port;

  /// `type` —— ssh / telnet / mosh / local
  final ConnectionType type;

  /// `group` —— 外键，指向 connectiongroup
  final int? groupId;

  /// `via` —— 外键，指向另一条 connection（跳板机）
  final int? viaId;

  /// `snippet` —— 外键，连接成功后自动执行
  final int? snippetId;

  /// `mosh_command` —— 列名映射为 mosh_command
  final String? moshCommand;

  /// `backspaceMode`
  final BackspaceMode backspaceMode;

  @override
  final int? modified;

  @override
  final String? encrypted;

  @override
  final bool isEncrypted;

  @override
  final int? owner;

  @override
  final int? lastUpdatedBy;

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

/// `connectiongroup` 表。
///
/// 原版**没有标签（tag）功能**，分组是唯一的归类方式。
class ConnectionGroup with SyncMetadata {
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
  final int id;
  final String name;
  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

  ConnectionGroup copyWith({int? id, String? name, int? modified}) => ConnectionGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        modified: modified ?? this.modified,
      );

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'name': name,
        'modified': modified,
        'encrypted': encrypted,
        'isEncrypted': isEncrypted ? 1 : 0,
        'owner': owner,
        'lastUpdatedBy': lastUpdatedBy,
      };

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

/// `identity` 表 —— 一套登录凭据（用户名 + 密码或私钥）。
class Identity with SyncMetadata {
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
  final int id;

  /// `nickname`
  final String nickname;

  /// `username`
  final String? username;

  /// `password`
  final String? password;

  /// `privatekey` —— PEM / OpenSSH 私钥文本
  final String? privateKey;

  /// `privatekeyPassword` —— 私钥口令
  final String? privateKeyPassword;

  /// `passUpdated` / `keyUpdated` —— 时间戳，用于云同步冲突判定
  final int? passUpdated;
  final int? keyUpdated;

  /// `snippet` —— 登录成功后自动执行
  final int? snippetId;

  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

  bool get hasPrivateKey => (privateKey ?? '').trim().isNotEmpty;
  bool get hasPassword => (password ?? '').isNotEmpty;

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

/// `connectionidentity` 表 —— 连接与身份的多对多关联。
///
/// 这是原版一个容易被忽略的能力：一条连接可以挂多个身份，
/// 登录时按顺序逐个尝试，直到某个身份通过认证。
class ConnectionIdentity with SyncMetadata {
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
  final int id;
  final int connectionId;
  final int identityId;
  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

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

  static ConnectionIdentity fromMap(Map<String, Object?> map) => ConnectionIdentity(
        id: (map['id'] as num?)?.toInt() ?? 0,
        connectionId: (map['connection'] as num?)?.toInt() ?? 0,
        identityId: (map['identity'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// `snippet` 表 —— 一段可复用的命令，可在连接建立后自动执行。
class Snippet with SyncMetadata {
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
  final int id;
  final String name;
  final String content;

  /// `count` —— 使用次数，用于"常用"排序
  final int count;

  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

  Snippet copyWith({int? id, String? name, String? content, int? count, int? modified}) => Snippet(
        id: id ?? this.id,
        name: name ?? this.name,
        content: content ?? this.content,
        count: count ?? this.count,
        modified: modified ?? this.modified,
      );

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

  static Snippet fromMap(Map<String, Object?> map) => Snippet(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: '${map['name'] ?? ''}',
        content: '${map['content'] ?? ''}',
        count: (map['count'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// `portforward` 表。
class PortForward with SyncMetadata {
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
  final int id;
  final String name;
  final PortForwardMode mode;

  /// `connection` —— 外键，指向承载该转发的连接
  final int? connectionId;

  /// `host` —— 目标主机（本地/远程转发的目标地址）
  final String? host;
  final int? localPort;
  final int? remotePort;

  /// `openInBrowser` —— 建立后自动打开浏览器
  final bool openInBrowser;

  /// `useAsProxy` —— 编辑器里那个复选框。
  ///
  /// 注意：原版 3.2.2 里这个字段**只存不用** —— 全 smali 树里除了
  /// `ManagePortForwardActivity`（读写复选框）和模型本身，没有任何运行时引用；
  /// 转发运行时（`gi0.smali`）只读 `openInBrowser`。所以克隆同样只做持久化 +
  /// 编辑器展示，不接任何行为（不是缺口）。
  final bool useAsProxy;

  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

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

/// `host` 表 —— 已知主机（known hosts）。表名就叫 host。
class KnownHost with SyncMetadata {
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
  final int id;

  /// `hostname`
  final String hostname;

  /// `key` —— 服务端公钥
  final String key;

  /// `type` —— 密钥算法，例如 ssh-rsa / ssh-ed25519
  final String type;

  /// `fingerprint`
  final String? fingerprint;

  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

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

  static KnownHost fromMap(Map<String, Object?> map) => KnownHost(
        id: (map['id'] as num?)?.toInt() ?? 0,
        hostname: '${map['hostname'] ?? ''}',
        key: '${map['key'] ?? ''}',
        type: '${map['type'] ?? ''}',
        fingerprint: map['fingerprint'] as String?,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// `connectioncounter` 表 —— 每条连接的使用次数，供"常用连接"与排序使用。
class ConnectionCounter with SyncMetadata {
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
  final int id;
  final int connectionId;
  final int count;
  @override
  final int? modified;
  @override
  final String? encrypted;
  @override
  final bool isEncrypted;
  @override
  final int? owner;
  @override
  final int? lastUpdatedBy;

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

  static ConnectionCounter fromMap(Map<String, Object?> map) => ConnectionCounter(
        id: (map['id'] as num?)?.toInt() ?? 0,
        connectionId: (map['connection'] as num?)?.toInt() ?? 0,
        count: (map['count'] as num?)?.toInt() ?? 0,
        modified: (map['modified'] as num?)?.toInt(),
      );
}

/// 把 `ConnectionGroupMembership` 简化为一个 (connection, group) 值对象。
class ConnectionGroupMembership {
  const ConnectionGroupMembership({
    required this.connectionId,
    required this.groupId,
  });

  final int connectionId;
  final int groupId;

  static ConnectionGroupMembership fromMap(Map<String, Object?> map) =>
      ConnectionGroupMembership(
        connectionId: (map['connection'] as num?)?.toInt() ?? 0,
        groupId: (map['group'] as num?)?.toInt() ?? 0,
      );
}

/// 连接的身份关联，带一个显示顺序（原版用插入顺序表示尝试顺序）。
class ConnectionIdentityLink {
  const ConnectionIdentityLink({
    required this.connectionId,
    required this.identityId,
    this.position = 0,
  });

  final int connectionId;
  final int identityId;
  final int position;
}

/// settings 的存储模型。
///
/// 原版把设置规范化成 `configfield` + `configvalue` 两张表，目的是给单个字段
/// 加"是否加密"以及云同步元数据。本地复刻不需要这层间接，
/// 因此这里用一张 `config(key, value, isEncrypted)` 直接存储，
/// 键名与原版完全一致（如 `terminal:theme`、`pinlock:enabled`）。
class ConfigEntry {
  const ConfigEntry({
    required this.key,
    required this.value,
    this.isEncrypted = false,
  });

  final String key;
  final String? value;
  final bool isEncrypted;

  static ConfigEntry fromMap(Map<String, Object?> map) => ConfigEntry(
        key: '${map['key'] ?? ''}',
        value: map['value'] as String?,
        isEncrypted: ((map['isEncrypted'] as num?)?.toInt() ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        'key': key,
        'value': value,
        'isEncrypted': isEncrypted ? 1 : 0,
      };
}

/// 便于调试：把 map 里的值转成可读字符串。
String describeMap(Map<String, Object?> map) => json.encode(map);
