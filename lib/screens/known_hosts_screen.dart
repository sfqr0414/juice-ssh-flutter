import 'package:flutter/material.dart';

import '../app/i18n.dart';
import '../data/juice_database.dart';
import '../data/models.dart';
import '../widgets/juice_dialogs.dart';
import '../widgets/pager_list.dart';
import 'identities_screen.dart';

/// @brief 已知主机（known hosts）列表页。
///
/// ### 原版事实：**没有这一页**
/// 反编译资源里不存在 `known_hosts*.xml` 布局，也没有对应的 Activity；
/// 原版把它做成"设置"里的一个动作项，见 `res/xml/settings.xml` 第 11 行：
/// ```xml
/// <com.sonelli.juicessh.views.ActionPreference
///     android:persistent="false" android:background="@drawable/highlight"
///     android:layout="@layout/preference"
///     android:title="@string/clear_known_hosts"
///     android:key="action:clear_known_hosts"
///     android:summary="@string/removes_host_keys" />
/// ```
/// 点击后走 `com/sonelli/ej0.smali` 的 `u()`（第 756-810 行）：
/// * 标题 `@string/clear_known_hosts`（"Clear known hosts"）
/// * 正文 `@string/are_you_sure_clear_known_hosts`
/// * 按钮 `@string/confirm`（"Confirm"）/ `@string/cancel`（"Cancel"）
/// * 确认后清库并 Toast `@string/known_hosts_cleared`
///
/// 所以本页的**动作部分**（清空 + 确认 + 提示）是逐条照抄原版的，
/// 只有**列表外壳**是新增的（原版没有可浏览的界面）。
///
/// ### 因此下面三处文案是"选最接近的真实键"，不是原版原话
/// * 页面标题 —— 资源里没有 `known_hosts` 这类键，取原版描述主机密钥
///   校验流程的 `@string/host_verification`（"Host Verification"）；
/// * 空状态标题 —— 没有 `no_known_hosts`，取 `@string/nothing_to_clear`
///   （"Nothing to clear"）；
/// * 空状态正文 —— 取设置项的 summary `@string/removes_host_keys`
///   （"Wipe previously seen host keys/fingerprints"），它正好描述了本页内容。
///
/// ### 数据
/// `KnownHost` 对应 `host` 表（`res/raw/ormlite_config.txt`），字段
/// `hostname` / `key` / `type` / `fingerprint`。列表行显示
/// **主机名（标题）+ 指纹（副标题）**。
class KnownHostsScreen extends StatefulWidget {
  /// @brief 创建已知主机列表页 widget。
  const KnownHostsScreen({super.key});

  /// @brief AppBar 里"清空"动作的图标键。
  ///
  /// 原版设置项的图标是 `@drawable/highlight` 的默认样式（无图标），
  /// 这里用 Material 的"清空列表"图标作等价表达。
  static const IconData clearIcon = Icons.delete_sweep;

  /// @brief 创建本页的 State。
  @override
  State<KnownHostsScreen> createState() => _KnownHostsScreenState();
}

/// @brief 已知主机列表页的状态：载入主机列表并执行清空。
class _KnownHostsScreenState extends State<KnownHostsScreen> {
  /// @brief 数据库单例，本页只读它与清空 known hosts。
  JuiceDatabase get _db => JuiceDatabase.instance;

  /// @brief 当前已载入的已知主机列表。
  List<KnownHost> _hosts = const <KnownHost>[];
  /// @brief 是否仍在读库；加载期间显示进度圈。
  bool _loading = true;

  /// @brief 初始化：载入已知主机列表。
  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// @brief 从数据库重新载入已知主机列表。
  Future<void> _reload() async {
    final hosts = await _db.knownHosts();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _loading = false;
    });
  }

  // ------------------------------------------------------------------ 动作 --

  /// @brief 清空已知主机 —— 逐条照抄 `ej0.u()`。
  Future<void> _clear() async {
    final s = context.s;
    // 先把 messenger 与提示文案取出来，避免 `await` 之后再碰 `context`。
    final messenger = ScaffoldMessenger.of(context);
    final clearedText = s('known_hosts_cleared');
    final confirmed = await JuiceDialogs.confirm(
      context,
      title: s('clear_known_hosts'),
      // 原版这条文案里有个重复词的笔误（"known host hosts"），
      // `strings_en.json` 里已按原样保留。
      message: s('are_you_sure_clear_known_hosts'),
      // 原版 `setPositiveButton(0x7f110093)` = `@string/confirm`（"Confirm"），
      // 负按钮 `setNegativeButton(0x7f110059)` = `@string/cancel`，
      // 正好是 [JuiceDialogs.confirm] 的默认按钮组合。
      confirmLabel: s('confirm'),
    );
    if (!confirmed || !mounted) return;

    await _db.clearKnownHosts();
    if (!mounted) return;
    await _reload();
    if (!mounted) return;

    // 原版是 `Toast.makeText(..., @string/known_hosts_cleared, ...)`。
    messenger.showSnackBar(SnackBar(content: Text(clearedText)));
  }

  /// @brief 点行查看完整信息。
  ///
  /// 原版没有这一页，但在主机密钥确认框里（`JuiceDialogs.confirmHostKey`
  /// 对应的 `this_is_the_first_time_youve_connected` / `host_key_changed`）
  /// 确实会同时展示主机名与指纹。列表行的副标题是单行 12sp，
  /// 长指纹会被省略，所以这里给一个能看全的出口。
  Future<void> _showDetails(KnownHost host) async {
    final s = context.s;
    // 不用标签前缀：`type` / `fingerprint` 在 `strings_en.json` 里没有对应键，
    // 与其编一个，不如让三行内容自解释（类似原版主机密钥框的排布）。
    final details = <String>[
      host.hostname,
      host.type,
      host.fingerprint ?? s('not_set'),
    ].where((line) => line.isNotEmpty).join('\n');

    await JuiceDialogs.message(
      context,
      title: s('host_verification'),
      message: details,
    );
  }

  // ------------------------------------------------------------------ 视图 --

  /// @brief 构建列表页：空列表显示空状态，否则显示主机行。
  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        title: Text(s('host_verification')),
        actions: [
          IconButton(
            icon: const Icon(KnownHostsScreen.clearIcon),
            tooltip: s('clear_known_hosts'),
            onPressed: _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                if (_hosts.isEmpty)
                  _buildEmptyState(context)
                else
                  ListView.separated(
                    itemCount: _hosts.length,
                    // 与 `port_forwards.xml` 一致：`@drawable/highlight` 是空
                    // selector，占 0.5dp 却不画线。
                    separatorBuilder: (_, _) => const SizedBox(height: 0.5),
                    itemBuilder: (context, index) {
                      final host = _hosts[index];
                      return CardListItem(
                        title: host.hostname,
                        subtitle: host.fingerprint ?? s('not_set'),
                        leadingIcon: Icons.vpn_key,
                        onTap: () => _showDetails(host),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  /// @brief 空状态。
  ///
  /// 度量沿用 `port_forwards.xml` / `pager_list.xml` 的写法
  /// （标题 `@dimen/text_heading` = 36sp / `@color/text_heading`，
  /// 正文距标题 5dp、`@color/text_subheading`，
  /// 整块 `padding=@dimen/activity_padding` = 16dp），
  /// 因为原版没有这一页、没有专属布局可抄。
  Widget _buildEmptyState(BuildContext context) {
    // 原版没有独立的已知主机页面（只有设置里的「清除已知主机」入口），
    // 这一页是本复刻新增的；空态沿用 `pager_list.xml` 那套独立列表页的
    // 通用样式（整块居中），与片段页、分组页保持一致。
    return SizedBox.expand(
      child: PagerEmptyState(
        style: PagerEmptyStyle.centered,
        title: context.s('nothing_to_clear'),
        message: context.s('removes_host_keys'),
      ),
    );
  }
}
