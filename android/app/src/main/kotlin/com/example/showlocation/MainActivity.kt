package com.example.showlocation

import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import com.amap.api.location.AMapLocationListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ShowLocation 主 Activity。
 *
 * 负责两件事：
 *  1. 高德 / Flutter 引擎默认初始化流程（继承自 FlutterActivity）。
 *  2. 注册 MethodChannel `show_location/mock`，暴露以下方法给 Dart：
 *     - isMockEnabled       : 当前 APP 是否被授予"模拟位置应用"
 *     - openDevOptions      : 跳转"开发者选项"以让用户选择本 APP
 *     - setAmapApiKey(key)  : 把高德 Key 传给定位 SDK（AL 探针用）
 *     - startMock           : 启动前台服务持续注入 mock 位置
 *     - updateMockTarget    : 更新前台服务推送目标（反推校准用）
 *     - stopMock            : 停止前台服务
 *     - readRealLocation    : 被动读系统真实 GPS 缓存
 *     - requestRealLocation : 主动请求一帧真实定位（8s 超时）
 *     - requestAmapLocation : AL 探针（高德独立定位 SDK，8s 超时）
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "show_location/mock"

    /// 高德独立定位 SDK 客户端（AL 探针）。懒加载，避免未用到时也初始化。
    private var _amapLocationClient: AMapLocationClient? = null

    /// 高德定位 SDK 的 API Key（由 Dart 侧经 setAmapApiKey 传入）。
    /// AMapLocationClient 需要独立 Key（地图 SDK 的 Key 不会自动给它）。
    @Volatile
    private var _amapApiKey: String = ""

    /// 高德定位请求进行中标记，防止并发调用互相覆盖 listener 导致回调丢失。
    private val _amapLocating = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isMockEnabled" -> result.success(isMockLocationEnabled())
                        "openDevOptions" -> {
                            openDevOptions()
                            result.success(true)
                        }
                        "setAmapApiKey" -> {
                            // P0 修复：把高德 Android Key 传给定位 SDK（AL 探针的
                            // AMapLocationClient 需要独立 Key，地图 SDK 的 Key 不会自动给它）。
                            val key = call.argument<String>("key") ?: ""
                            _amapApiKey = key
                            result.success(true)
                        }
                        // 前台服务指令：启动后台 mock 推送（替代 Dart Timer）
                        "startMock" -> {
                            val lat = call.argument<Double>("lat") ?: 0.0
                            val lng = call.argument<Double>("lng") ?: 0.0
                            val mirror = call.argument<Boolean>("mirrorToNetwork") ?: false
                            MockLocationService.start(applicationContext, lat, lng, mirror)
                            result.success(true)
                        }
                        // 前台服务指令：更新目标坐标（反推校准后调用）
                        "updateMockTarget" -> {
                            val lat = call.argument<Double>("lat") ?: 0.0
                            val lng = call.argument<Double>("lng") ?: 0.0
                            MockLocationService.updateTarget(lat, lng)
                            result.success(true)
                        }
                        // 前台服务指令：停止后台 mock 推送
                        "stopMock" -> {
                            MockLocationService.stop(applicationContext)
                            result.success(true)
                        }
                        "readRealLocation" -> {
                            // 用户点"停止模拟"后捕获系统回填的真实坐标。
                            // 原理：stopMock 移除 test provider → 系统会回填
                            // 上一次真实 GPS 的 lastKnownLocation（可能较老但有效）。
                            // 调用方应自行判断 time 字段是不是太久远。
                            val payload = readRealLocation()
                            result.success(payload)
                        }
                        "requestRealLocation" -> {
                            // 方案 A：主动定位。不再被动读 getLastKnownLocation 缓存，
                            // 而是注册 requestLocationUpdates 主动请求一帧真实 GPS fix，
                            // 8 秒超时兜底缓存。解决"室内冷启动 30s 拿不到位置"。
                            // 异步回调 result，方法内部用 AtomicBoolean 防重复回调。
                            requestRealLocation(result)
                        }
                        "requestAmapLocation" -> {
                            // AL 探针：用高德独立定位 SDK（AMapLocationClient）拿
                            // "高德视角加工后"的位置（map-matching / 反 mock / 多源融合），
                            // 这是其他高德系 APP 实际显示的位置，替代残缺的地图蓝点回调。
                            // 8 秒超时兜底，返回 errorCode / locationType 供 Dart 判断风控。
                            requestAmapLocation(result)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("MOCK_ERR", e.message ?: "unknown", e.stackTraceToString())
                }
            }
    }

    // -----------------------------------------------------------------------
    // 权限判定：当前进程是否被允许作为 Mock Location App
    // -----------------------------------------------------------------------

    /**
     * 核心入口：
     *   - Android 6.0+ : AppOpsManager.OPSTR_MOCK_LOCATION == MODE_ALLOWED
     *   - Android < 6  : Settings.Secure.ALLOW_MOCK_LOCATION != 0
     * 部分 ROM 把 OPSTR 名字换了，做一次反射兜底。
     */
    @SuppressLint("DiscouragedPrivateApi")
    private fun isMockLocationEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            try {
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Q+ 安全 API：unsafeCheckOpNoThrow
                    appOps.unsafeCheckOpNoThrow(
                        AppOpsManager.OPSTR_MOCK_LOCATION,
                        Process.myUid(),
                        packageName
                    )
                } else {
                    // M-Q : 通过反射拿 checkOpNoThrow，避免低版本编译期 API 限制
                    invokeCheckOpNoThrow(appOps)
                }
                mode == AppOpsManager.MODE_ALLOWED
            } catch (e: Throwable) {
                // 反射失败时，不阻止用户去开发者选项试一次
                false
            }
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(contentResolver, Settings.Secure.ALLOW_MOCK_LOCATION, 0) != 0
        }
    }

    @SuppressLint("DiscouragedPrivateApi")
    private fun invokeCheckOpNoThrow(appOps: AppOpsManager): Int {
        // 兼容 Android M (23) ~ Android P (28) 之间没有 unsafeCheckOpNoThrow 的情况
        val method = AppOpsManager::class.java.getMethod(
            "checkOpNoThrow", Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType, String::class.java
        )
        val opInt = AppOpsManager::class.java.getField("OP_MOCK_LOCATION").getInt(null)
        return method.invoke(appOps, opInt, Process.myUid(), packageName) as Int
    }

    private fun openDevOptions() {
        // 跳转开发者选项（不同 ROM 可能藏在不同深处，至少给个入口）
        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    /**
     * 读取系统 LocationManager 中 GPS_PROVIDER 的最新"真实"fix。
     *
     * 设计意图：在 MockController.stop() 之后调用，能拿到系统回填的
     * 上一次真实 GPS 位置（test provider 被移除后，LocationManager
     * 会把上一次真实 fix 暴露在 getLastKnownLocation(GPS_PROVIDER) 上）。
     *
     * 返回 null 表示：
     *  - GPS Provider 不可用（设备无 GPS 硬件 / 用户关了 GPS 开关），
     *  - 权限缺失（无 ACCESS_FINE_LOCATION），
     *  - 系统从未拿到过真实 fix（罕见，初次启动还没出卫星）。
     */
    @SuppressLint("MissingPermission")
    private fun readRealLocation(): Map<String, Any?>? {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val loc: Location? = try {
            lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        } catch (_: Throwable) {
            null
        }
        if (loc == null) return null
        return mapOf(
            "lat" to loc.latitude,
            "lng" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "time" to loc.time
        )
    }

    /**
     * 方案 A：主动请求一帧真实定位（requestLocationUpdates），8 秒超时兜底缓存。
     *
     * 对比 [readRealLocation]（只被动读 getLastKnownLocation 缓存）：
     *  - 冷启动 / 长期室内时系统缓存可能为 null，被动读永远拿不到；
     *  - 这里主动注册 GPS 监听，逼系统触发一次真实 fix 回调。
     *
     * 流程：
     *  1. 先读 getLastKnownLocation，命中且 <60s 直接返回（快路径）；
     *  2. 否则 requestLocationUpdates(GPS_PROVIDER, 0, 0, listener)；
     *  3. onLocationChanged 里 removeUpdates + result.success(locationToMap)；
     *  4. Handler.postDelayed 8s 超时：removeUpdates + result.success(null)；
     *  5. AtomicBoolean 防 result 重复回调（fix 先到 vs 超时竞态）。
     *
     * 注意：GPS + NETWORK 双 provider 都注册，室内无卫星时 NETWORK 也能出 fix。
     */
    @SuppressLint("MissingPermission")
    private fun requestRealLocation(result: MethodChannel.Result) {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val mainHandler = Handler(Looper.getMainLooper())
        val finished = AtomicBoolean(false)

        // 快路径：60s 内的缓存直接返回，避免不必要的硬件启动。
        try {
            val cached = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            if (cached != null &&
                System.currentTimeMillis() - cached.time < 60_000L
            ) {
                result.success(locationToMap(cached))
                return
            }
        } catch (_: Throwable) { /* 忽略，继续走主动定位 */ }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (finished.compareAndSet(false, true)) {
                    detach()
                    result.success(locationToMap(location))
                }
            }

            override fun onProviderDisabled(provider: String) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onStatusChanged(provider: String, status: Int, extras: Bundle) {}

            private fun detach() {
                try {
                    lm.removeUpdates(this)
                } catch (_: Throwable) { /* 忽略 */ }
                mainHandler.removeCallbacksAndMessages(null)
            }
        }

        // 超时兜底：8 秒后仍未 fix，移除监听并返回 null。
        mainHandler.postDelayed({
            if (finished.compareAndSet(false, true)) {
                try {
                    lm.removeUpdates(listener)
                } catch (_: Throwable) { /* 忽略 */ }
                result.success(null)
            }
        }, 8_000L)

        try {
            // GPS 优先
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener)
        } catch (_: Throwable) { /* GPS 不可用则尝试网络定位 */ }
        try {
            // 网络兜底：室内无卫星时 NETWORK 也能出 fix
            lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0L, 0f, listener)
        } catch (_: Throwable) { /* 忽略 */ }
    }

    /** Location → Dart 可序列化的 Map。 */
    private fun locationToMap(loc: Location): Map<String, Any?> {
        return mapOf(
            "lat" to loc.latitude,
            "lng" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "time" to loc.time,
            "provider" to (loc.provider ?: ""),
            "isFromMockProvider" to loc.isFromMockProvider
        )
    }

    /**
     * AL 探针：用高德独立定位 SDK 拿一次"高德视角加工后"的位置。
     *
     * 为什么不用地图蓝点回调（onMyLocationChange）：
     *  - csp_amap_flutter_map 插件只调了 setMyLocationEnabled(true)，
     *    从未 setLocationSource(...)，导致蓝点定位源未启动 →
     *    蓝点不显示 + onMyLocationChange 永不回调（已在真机日志确认）。
     *  - AMapLocationClient 是高德专门定位服务，内部做 map-matching、
     *    反 mock、GPS/网络多源融合，回调的坐标 == 其他高德系 APP 显示的位置，
     *    正是 AL 探针要观测的对象。
     *
     * 返回：
     *  - 成功：{ lat, lng, accuracy, time, errorCode=0, locationType, ... }
     *  - 失败/超时：{ errorCode, errorInfo }（errorCode 高德标准错误码）
     *
     * 8 秒超时，AtomicBoolean 防重复回调。client 复用（懒加载单例）。
     */
    @SuppressLint("MissingPermission")
    private fun requestAmapLocation(result: MethodChannel.Result) {
        // 并发保护：同一时间只允许一次定位请求，避免复用 client 时互相覆盖 listener。
        if (!_amapLocating.compareAndSet(false, true)) {
            result.success(mapOf("errorCode" to -4, "errorInfo" to "定位请求进行中"))
            return
        }
        val finished = AtomicBoolean(false)
        val mainHandler = Handler(Looper.getMainLooper())
        fun finish() {
            _amapLocating.set(false)
        }

        val listener = AMapLocationListener { aMapLocation ->
            if (aMapLocation == null) {
                if (finished.compareAndSet(false, true)) {
                    finish()
                    result.success(mapOf("errorCode" to -1, "errorInfo" to "定位返回 null"))
                }
                return@AMapLocationListener
            }
            if (aMapLocation.errorCode == 0) {
                // 定位成功
                if (finished.compareAndSet(false, true)) {
                    finish()
                    result.success(amapLocationToMap(aMapLocation))
                }
            } else {
                // 定位失败（含被风控 / 无权限 / 超时等）
                if (finished.compareAndSet(false, true)) {
                    finish()
                    result.success(
                        mapOf(
                            "errorCode" to aMapLocation.errorCode,
                            "errorInfo" to aMapLocation.errorInfo,
                        )
                    )
                }
            }
        }

        // 8 秒超时兜底
        mainHandler.postDelayed({
            if (finished.compareAndSet(false, true)) {
                finish()
                stopAmapLocation()
                result.success(mapOf("errorCode" to -2, "errorInfo" to "定位超时"))
            }
        }, 8_000L)

        try {
            val client = ensureAmapLocationClient(listener)
            client.startLocation()
        } catch (e: Throwable) {
            if (finished.compareAndSet(false, true)) {
                finish()
                result.success(mapOf("errorCode" to -3, "errorInfo" to (e.message ?: "定位初始化失败")))
            }
        }
    }

    /** 懒加载高德定位 client，配置为"单次高精度定位"。 */
    @SuppressLint("MissingPermission")
    private fun ensureAmapLocationClient(listener: AMapLocationListener): AMapLocationClient {
        val existing = _amapLocationClient
        if (existing != null) {
            existing.setLocationListener(listener)
            return existing
        }
        // P0 修复：定位 SDK 需要独立 Key（地图 SDK 的 Key 不会自动给它）。
        // setApiKey 必须在构造 AMapLocationClient 之前调用。
        if (_amapApiKey.isNotEmpty()) {
            try {
                AMapLocationClient.setApiKey(_amapApiKey)
            } catch (_: Throwable) { /* 旧版本定位 SDK 无此方法时忽略 */ }
        }
        val client = AMapLocationClient(applicationContext)
        val option = AMapLocationClientOption().apply {
            locationMode = AMapLocationClientOption.AMapLocationMode.Hight_Accuracy
            setOnceLocation(true)           // 单次定位，拿到一帧即可
            setOnceLocationLatest(true)     // 返回最新一帧，而非缓存
            setNeedAddress(false)
            setLocationCacheEnable(false)
            setMockEnable(true)             // 允许返回 mock 结果（否则 SDK 会过滤掉我们的 test provider）
            setHttpTimeOut(8000)            // 联网超时 8 秒（与 Dart 层超时兜底对齐）
        }
        client.setLocationOption(option)
        client.setLocationListener(listener)
        _amapLocationClient = client
        return client
    }

    /** 停止高德定位（单次定位完成后 SDK 会自动停止，这里做兜底）。 */
    private fun stopAmapLocation() {
        try {
            _amapLocationClient?.stopLocation()
        } catch (_: Throwable) { /* 忽略 */ }
    }

    /** AMapLocation → Dart 可序列化的 Map。 */
    private fun amapLocationToMap(loc: AMapLocation): Map<String, Any?> {
        return mapOf(
            "errorCode" to loc.errorCode,
            "lat" to loc.latitude,
            "lng" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "time" to loc.time,
            "locationType" to loc.locationType,
            "locationDetail" to loc.locationDetail,
            "provider" to (loc.provider ?: ""),
            "isFromMockProvider" to loc.isFromMockProvider
        )
    }

}
