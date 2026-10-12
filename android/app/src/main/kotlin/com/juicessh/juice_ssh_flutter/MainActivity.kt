package com.juicessh.juice_ssh_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 宿主 Activity：只多做一件事 —— 端口转发的常驻通知。
 *
 * 原版 JuiceSSH 每条活动转发都会挂一个通知（`gi0.smali` 里
 * `NotificationCompat.Builder.setUsesChronometer(true)` + 一个
 * `addAction(...)` 的停止动作，文案是 `@string/disconnect`），而
 * `PortForward.openInBrowser` 决定点开通知时去哪：为真就
 * `ACTION_VIEW http://localhost:<localPort>`，否则回到应用本体。
 * 这里用框架 API（minSdk 26，不需要 androidx）复刻同一套行为。
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** 音量键改字号：原版终端页里 keycode 24/25 = 字号 +1 / -1，且事件被吃掉。 */
    private var keyChannel: MethodChannel? = null
    private var volumeKeysActive = false

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (volumeKeysActive &&
            event.action == android.view.KeyEvent.ACTION_DOWN &&
            (event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            val delta = if (event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
            android.util.Log.i("JuiceSshVolume", "volume key delta=$delta")
            keyChannel?.invokeMethod("volumeKey", delta)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    /** 通知上的「停止」动作：把转发 id 送回 Dart 侧去真正断开。 */
    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val id = intent?.getIntExtra(EXTRA_FORWARD_ID, -1) ?: -1
            if (id >= 0) {
                android.util.Log.i("JuiceSshForward", "stop action id=$id")
                channel?.invokeMethod("onStopForward", id)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        keyChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.juicessh.juice_ssh_flutter/hardware_keys",
        )
        keyChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setActive") {
                volumeKeysActive = call.argument<Boolean>("active") ?: false
                android.util.Log.i("JuiceSshVolume", "active=$volumeKeysActive")
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // 状态栏底色：Flutter 侧的 SystemUiOverlayStyle.statusBarColor 在本机
        // （API 36 + Flutter 3.47.7）不生效（Flutter 默认 edgeToEdge），直接设窗口属性则有效。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "juicessh/system_ui",
        ).setMethodCallHandler { call, result ->
            if (call.method == "setStatusBar") {
                // Dart 的 int 超过 32 位时会按 Long 编码（0xFFRRGGBB 必然超），
                // 所以必须按 Number 取再截断 —— 用 argument<Int> 会拿到 null。
                val color = (call.argument<Any>("color") as? Number)?.toInt() ?: 0
                val lightIcons = call.argument<Boolean>("lightIcons") ?: false
                android.util.Log.i(
                    "JuiceSshStatusBar",
                    "setStatusBar color=" + Integer.toHexString(color) + " light=" + lightIcons,
                )
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                    val mask = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    window?.insetsController?.setSystemBarsAppearance(
                        if (lightIcons) mask else 0,
                        mask,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    window?.decorView?.systemUiVisibility =
                        if (lightIcons) android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR else 0
                }
                @Suppress("DEPRECATION")
                window?.statusBarColor = color
                @Suppress("DEPRECATION")
                android.util.Log.i(
                    "JuiceSshStatusBar",
                    "after set: window.statusBarColor=" +
                        Integer.toHexString(window?.statusBarColor ?: 0),
                )
                result.success(null)
            } else if (call.method == "imeVisible") {
                // 输入法此刻是否真的可见。终端页的 Toggle Keyboard 键靠它决定
                // 该弹出还是收起 —— Dart 侧自己记账会在系统手势收起键盘后失配，
                // 表现就是"点了没反应"。
                val insets = window?.decorView?.rootWindowInsets
                val visible = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    insets?.isVisible(android.view.WindowInsets.Type.ime()) ?: false
                } else {
                    @Suppress("DEPRECATION")
                    (insets?.systemWindowInsetBottom ?: 0) > 0
                }
                android.util.Log.i("JuiceSshIme", "imeVisible=$visible")
                result.success(visible)
            } else {
                result.notImplemented()
            }
        }

        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val id = call.argument<Int>("id")
                    if (id == null) {
                        result.error("bad_args", "id is required", null)
                    } else {
                        showNotification(
                            id,
                            call.argument<String>("title") ?: "Port forward",
                            call.argument<String>("text") ?: "",
                            call.argument<String>("url"),
                            call.argument<String>("disconnectLabel") ?: "Disconnect",
                        )
                        result.success(null)
                    }
                }

                "cancel" -> {
                    call.argument<Int>("id")?.let {
                        android.util.Log.i("JuiceSshForward", "cancel id=$it")
                        getSystemService(NotificationManager::class.java).cancel(it)
                    }
                    result.success(null)
                }
                // 终端响铃（`terminal:bell_mode = 2`，见 zi0.smali / Config.smali）。
                "bell" -> {
                    showBell(
                        call.argument<String>("title") ?: "Terminal Bell",
                        call.argument<String>("text") ?: "Terminal bell received!",
                    )
                    result.success(null)
                }

                "requestPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        val filter = IntentFilter(ACTION_STOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(stopReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(stopReceiver)
        } catch (_: IllegalArgumentException) {
            // 没注册成功时忽略。
        }
        channel = null
        super.onDestroy()
    }

    private fun createNotificationChannel(
        id: String = CHANNEL_ID,
        name: String = "Port forwards",
        description: String = "Active SSH port forwards",
    ) {
        val manager = getSystemService(NotificationManager::class.java)
        // 渠道的重要性创建之后不可修改，定义变了要先删掉再建。
        val existing = manager.getNotificationChannel(id)
        if (existing != null &&
            existing.importance == NotificationManager.IMPORTANCE_DEFAULT
        ) {
            return
        }
        if (existing != null) {
            manager.deleteNotificationChannel(id)
        }
        val channel = NotificationChannel(
            id,
            name,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            this.description = description
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    // 响铃通知用固定 id：连续响铃是在**更新同一条**通知，对应原版那条
    // `x_terminal_bells` = "%d terminal bells"（多条时换成计数文案）。
    private val bellChannelId = "terminal_bell"
    private val bellNotificationId = 9001

    private fun showBell(title: String, text: String) {
        createNotificationChannel(
            bellChannelId,
            "Terminal bell",
            "Terminal bell received while connected",
        )
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val notification = Notification.Builder(this, bellChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setColor(0xFFD5BA31.toInt())
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .build()
        android.util.Log.i("JuiceSshForward", "bell title=$title text=$text")
        getSystemService(NotificationManager::class.java)
            .notify(bellNotificationId, notification)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4711)
        }
    }

    private fun showNotification(
        id: Int,
        title: String,
        text: String,
        url: String?,
        disconnectLabel: String,
    ) {
        // 点开通知的去向由 `PortForward.openInBrowser` 决定（原版 `gi0.smali`）。
        val contentIntent = if (url != null) {
            PendingIntent.getActivity(
                this,
                id,
                Intent(Intent.ACTION_VIEW).setData(Uri.parse(url)).setFlags(0x40080000),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            PendingIntent.getActivity(
                this,
                id,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val stopIntent = PendingIntent.getBroadcast(
            this,
            id,
            Intent(ACTION_STOP)
                .setPackage(packageName)
                .putExtra(EXTRA_FORWARD_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // 便于验证：原版 `openInBrowser` 决定的就是这个值，打出来以便
        // `adb logcat` 核对（为真时应是 http://localhost:<localPort>）。
        android.util.Log.i(
            "JuiceSshForward",
            "notification id=$id title=$title url=$url",
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setUsesChronometer(true)
            .setOngoing(true)
            .setAutoCancel(false)
            .setColor(ACCENT_COLOR)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.mipmap.ic_launcher),
                    disconnectLabel,
                    stopIntent,
                ).build(),
            )
            .build()
        try {
            getSystemService(NotificationManager::class.java).notify(id, notification)
        } catch (_: SecurityException) {
            // 没有 POST_NOTIFICATIONS 权限时静默失败，不影响转发本身。
        }
    }

    companion object {
        private const val CHANNEL_NAME = "com.juicessh.juice_ssh_flutter/port_forwards"
        private const val CHANNEL_ID = "port_forwards"
        private const val ACTION_STOP = "com.juicessh.juice_ssh_flutter.STOP_FORWARD"
        private const val EXTRA_FORWARD_ID = "forward_id"

        /** 品牌黄 `@color/accent_bold`，与原版通知的 `setColor` 一致。 */
        private const val ACCENT_COLOR = 0xFFD5BA31.toInt()
    }
}
