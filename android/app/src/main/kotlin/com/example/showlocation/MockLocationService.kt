package com.example.showlocation

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Criteria
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * 前台服务：在后台持续向系统 LocationManager 注入 mock 位置。
 *
 * 为什么必须是前台服务（而不是 Dart Timer / 普通后台线程）：
 *  - 鸿蒙 / 华为等 ROM 在"电池供电 + 非前台"时会冻结后台进程的 CPU 调度，
 *    导致任何普通线程（含 Dart Timer）都停止触发，mock 断供；
 *  - startForeground() 把进程优先级提升为"用户可感知前台进程"，
 *    系统不会冻结它，插不插 USB 都稳定。
 *
 * 生命周期：
 *  - onStartCommand  → startForeground + 注册 Test Provider + 启动 500ms 推送循环；
 *  - 坐标通过 companion 静态字段 @Volatile 共享，Dart 经 MainActivity 的
 *    MethodChannel 写入（startMock / updateMockTarget）；
 *  - onDestroy       → 停止循环 + 移除 Test Provider。
 */
class MockLocationService : Service() {

    private lateinit var executor: ScheduledExecutorService
    private var pushCount = 0
    /// 上一次 elapsedRealtimeNanos，保证 mock fix 时间戳严格单调递增。
    private var lastElapsedRealtimeNanos: Long = 0L

    /// PARTIAL_WAKE_LOCK：强制 CPU 不休眠。
    /// 华为鸿蒙的 FREEZE（进程冻结）会在"后台 + 无活跃 wakelock"时触发，
    /// 持锁后系统会跳过冻结，保证前台服务的推送线程持续运行。
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                // P2 修复：进程被杀后系统重启服务（intent action 为 null）时，
                // 目标坐标已随进程丢失（hasTarget 复位为 false），此时直接停止，
                // 避免残留一个"占通知栏但不推送"的空转前台服务。
                if (!hasTarget) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startAsForeground()
                acquireWakeLock()
                setupTestProvider()
                startPushLoop()
                running = true
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        stopPushLoop()
        releaseWakeLock()
        teardownTestProvider()
        hasTarget = false
        super.onDestroy()
    }

    // -----------------------------------------------------------------------
    // WakeLock（对抗华为鸿蒙 FREEZE）
    // -----------------------------------------------------------------------

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "showlocation:mock_location",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Throwable) { /* 拿不到锁也继续，前台服务本身仍是保底 */ }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Throwable) { /* 忽略 */ }
        wakeLock = null
    }

    // -----------------------------------------------------------------------
    // 前台化 / 通知
    // -----------------------------------------------------------------------

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "位置模拟运行中",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持位置模拟在后台持续运行"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        // 点击通知回到主界面
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            },
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("位置模拟运行中")
            .setContentText("正在向系统注入模拟位置")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pi)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    // -----------------------------------------------------------------------
    // Test Provider 生命周期（与 MainActivity 原实现等价，搬到服务里）
    // -----------------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun setupTestProvider() {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = mutableListOf(LocationManager.GPS_PROVIDER)
        if (mirrorToNetwork) {
            providers.add(LocationManager.NETWORK_PROVIDER)
        }
        for (resolved in providers) {
            try {
                lm.setTestProviderEnabled(resolved, false)
                lm.removeTestProvider(resolved)
            } catch (_: Throwable) { /* 不存在则忽略 */ }

            lm.addTestProvider(
                resolved,
                resolved == LocationManager.NETWORK_PROVIDER,
                resolved == LocationManager.GPS_PROVIDER,
                resolved == LocationManager.NETWORK_PROVIDER,
                false,
                true,
                true,
                true,
                Criteria.POWER_HIGH,
                Criteria.ACCURACY_FINE,
            )
            lm.setTestProviderEnabled(resolved, true)

            if (resolved == LocationManager.GPS_PROVIDER &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
            ) {
                try {
                    val satellites = Bundle().apply {
                        putInt("satellites", 8)
                        putInt("maxCn0", 40)
                        putInt("meanCn0", 38)
                    }
                    val statusMethod = LocationManager::class.java.getMethod(
                        "setTestProviderStatus",
                        String::class.java,
                        Bundle::class.java,
                    )
                    statusMethod.invoke(lm, resolved, satellites)
                } catch (_: Throwable) { /* 吞掉 */ }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun teardownTestProvider() {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = mutableListOf(LocationManager.GPS_PROVIDER)
        if (mirrorToNetwork) {
            providers.add(LocationManager.NETWORK_PROVIDER)
        }
        for (resolved in providers) {
            try {
                lm.setTestProviderEnabled(resolved, false)
                lm.removeTestProvider(resolved)
            } catch (_: Throwable) { /* 忽略 */ }
        }
        lastElapsedRealtimeNanos = 0L
    }

    // -----------------------------------------------------------------------
    // 推送循环
    // -----------------------------------------------------------------------

    private fun startPushLoop() {
        executor = Executors.newSingleThreadScheduledExecutor()
        executor.scheduleAtFixedRate(
            { pushOnce() },
            0,
            PUSH_INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun stopPushLoop() {
        try {
            executor.shutdownNow()
        } catch (_: Throwable) { /* 忽略 */ }
    }

    @SuppressLint("MissingPermission")
    private fun pushOnce() {
        if (!hasTarget) return
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        pushCount++

        // 时间戳严格单调递增
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            val nowNanos = SystemClock.elapsedRealtimeNanos()
            lastElapsedRealtimeNanos =
                if (lastElapsedRealtimeNanos >= nowNanos) {
                    lastElapsedRealtimeNanos + 500_000_000L
                } else {
                    nowNanos
                }
        }

        val bearingDeg = ((pushCount * 0.5) % 360.0).toFloat()
        val distanceAccumulated = pushCount * 3.0 * 0.5 // 与 Dart 原逻辑一致

        val loc = Location(LocationManager.GPS_PROVIDER).apply {
            latitude = targetLat
            longitude = targetLng
            accuracy = 5f
            altitude = 0.0
            bearing = bearingDeg
            speed = 3f
            time = System.currentTimeMillis()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                elapsedRealtimeNanos = lastElapsedRealtimeNanos
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                extras = Bundle().apply {
                    putInt("satellites", 8)
                    putInt("maxCn0", 40)
                    putDouble("distance", distanceAccumulated)
                    putDouble("bearing", bearingDeg.toDouble())
                }
            }
        }
        lm.setTestProviderLocation(LocationManager.GPS_PROVIDER, loc)

        if (mirrorToNetwork) {
            val networkLoc = Location(loc).apply {
                provider = LocationManager.NETWORK_PROVIDER
                accuracy = 25f
            }
            try {
                lm.setTestProviderLocation(LocationManager.NETWORK_PROVIDER, networkLoc)
            } catch (_: Throwable) { /* 忽略 */ }
        }
    }

    // -----------------------------------------------------------------------
    // 供 MainActivity 调用：启动 / 更新坐标 / 停止
    // -----------------------------------------------------------------------

    companion object {
        private const val CHANNEL_ID = "mock_location_service"
        private const val NOTIF_ID = 0x10C4
        private const val PUSH_INTERVAL_MS = 500L

        // -------------------------------------------------------------------
        // 跨线程共享的状态（Dart 侧经 MethodChannel → MainActivity 写入）。
        // 用 @Volatile 保证主线程写入后，服务线程立即可见。
        // -------------------------------------------------------------------
        @Volatile
        var targetLat: Double = 0.0
        @Volatile
        var targetLng: Double = 0.0
        @Volatile
        var hasTarget: Boolean = false
        @Volatile
        var mirrorToNetwork: Boolean = false
        @Volatile
        var running: Boolean = false

        const val ACTION_START = "com.example.showlocation.MockLocationService.START"
        const val ACTION_STOP = "com.example.showlocation.MockLocationService.STOP"

        @SuppressLint("MissingPermission")
        fun start(context: Context, lat: Double, lng: Double, mirror: Boolean) {
            targetLat = lat
            targetLng = lng
            hasTarget = true
            mirrorToNetwork = mirror
            val intent = Intent(context, MockLocationService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun updateTarget(lat: Double, lng: Double) {
            targetLat = lat
            targetLng = lng
            hasTarget = true
        }

        fun stop(context: Context) {
            hasTarget = false
            val intent = Intent(context, MockLocationService::class.java)
                .setAction(ACTION_STOP)
            // 用 stopService 而不是 startService：
            // Android 8+ 后台 startService 会抛 ForegroundServiceStartNotAllowedException，
            // 而 stopService 对已运行的服务直接触发 onDestroy，对未运行的服务是 no-op。
            try {
                context.stopService(intent)
            } catch (_: Throwable) { /* 忽略 */ }
        }
    }
}
