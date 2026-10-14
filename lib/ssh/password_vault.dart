import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// @brief 连接密码的**加密持久化**（跨重启）。
///
/// 用户第 2 条实测要求："重启也记住，再做一个（加密）持久化"。
/// 落地实现用 `flutter_secure_storage`：Android 侧由 **Keystore** 支撑，
/// 密文落在应用私有的加密存储里（不是明文 SQLite / SharedPreferences）；
/// iOS/macOS 走 Keychain，Linux 走 libsecret。
///
/// 键格式：`juicessh.pw.<user>@<host>` —— 与 `SshConnector._passwordCache`
/// 的内存键同源，便于两处互相印证。
///
/// 设计取舍（写进注释，避免以后被"顺手优化"掉）：
/// * 存储不可用（Keystore 被重置、设备不支持）时**静默退回**"每次都问"，
///   绝不让它把连接流程带崩；
/// * 值在用户输入后被写入，但如果服务端**再次**索要密码（说明它是错的），
///   调用方会把这条记录删掉 —— 详见 `SshConnector` 里 `#vault` 那段注释。
class PasswordVault {
  /// @brief 私有构造：全部能力都是静态方法。
  PasswordVault._();

  /// @brief 加密存储句柄（Android 由 Keystore 支撑）。
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// @brief 拼出该 user@host 的存储键。
  static String _key(String user, String host) => 'juicessh.pw.$user@$host';

  /// @brief 读出已保存的密码；读不到或存储不可用时返回 null。
  static Future<String?> read({
    required String user,
    required String host,
  }) async {
    try {
      final value = await _storage.read(key: _key(user, host));
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  /// @brief 写入密码；写失败只影响下次是否还要重问。
  static Future<void> write({
    required String user,
    required String host,
    required String password,
  }) async {
    try {
      await _storage.write(key: _key(user, host), value: password);
    } catch (_) {
      // 存储写失败不影响本次连接，只是下次还要再问一遍。
    }
  }

  /// @brief 删掉该 user@host 的密码记录。
  static Future<void> erase({
    required String user,
    required String host,
  }) async {
    try {
      await _storage.delete(key: _key(user, host));
    } catch (_) {}
  }
}
