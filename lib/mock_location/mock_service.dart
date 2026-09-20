import 'dart:async';
import 'package:flutter/services.dart';

/// 与 Android 原生层 MethodChannel `show_location/mock` 通信的桥。
///
/// 所有方法：
///  - 在非 Android 平台（iOS / 桌面）调用会抛 [MissingPluginException]，
///    使用方应在外层捕获处理；
///  - 原生抛 [PlatformException] 时转换为 [MockLocationException]，
///    异常 message 已是可读中文，便于直接展示给用户。
class MockService {
  MockService._();

  static const MethodChannel _channel = MethodChannel('show_location/mock');

  /// 检查当前 APP 是否已被系统设置为"模拟位置应用"。
  ///
  /// 返回 `true` 表示可以调用 [startMock]，
  /// `false` 需引导用户去"开发者选项→选择模拟位置应用"。
  static Future<bool> isMockEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isMockEnabled');
      return res ?? false;
    } on MissingPluginException {
      return false; // 非 Android
    } on PlatformException {
      return false;
    }
  }

  /// 跳转到"开发者选项"页面，让用户选定本 APP 为模拟位置应用。
  /// 调用后会回到系统设置，不会自动回到本 APP，
  /// Dart 层需提示用户选完后手动切回。
  static Future<bool> openDevOptions() async {
    try {
      await _channel.invokeMethod<bool>('openDevOptions');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw _toMockException(e);
    }
  }

  /// 把高德 Android Key 传给原生定位 SDK（AL 探针用）。
  ///
  /// AMapLocationClient 需要独立的 Key（地图 SDK 经 AMapInitializer 设置的
  /// Key 不会自动传给定位 SDK），须在首次 [requestAmapLocation] 之前调用一次。
  /// 非 Android / 未注入 Key 时静默失败（返回 false）。
  static Future<bool> setAmapApiKey(String key) async {
    if (key.isEmpty) return false;
    try {
      await _channel.invokeMethod<bool>('setAmapApiKey', {'key': key});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 启动后台前台服务，持续向系统注入 mock 位置（方案 A：前台服务保活）。
  ///
  /// 与旧 [startProvider] + 定时器 push 的方式不同：
  ///  - 推送循环完全在原生前台服务里跑（ScheduledExecutorService），
  ///    退后台也不会被鸿蒙/华为等 ROM 冻结；
  ///  - Dart 只负责发"启动/更新坐标/停止"指令，不再持有 Timer。
  ///
  /// [lat]/[lng] 初始目标坐标；[mirrorToNetwork] 是否同时镜像到 NETWORK_PROVIDER。
  static Future<bool> startMock({
    required double lat,
    required double lng,
    bool mirrorToNetwork = true,
  }) async {
    try {
      await _channel.invokeMethod<bool>('startMock', {
        'lat': lat,
        'lng': lng,
        'mirrorToNetwork': mirrorToNetwork,
      });
      return true;
    } on PlatformException catch (e) {
      throw _toMockException(e);
    }
  }

  /// 更新前台服务正在推送的目标坐标（反推校准后调用）。
  static Future<bool> updateMockTarget({
    required double lat,
    required double lng,
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateMockTarget', {
        'lat': lat,
        'lng': lng,
      });
      return true;
    } on PlatformException catch (e) {
      throw _toMockException(e);
    }
  }

  /// 停止前台服务，移除 Test Provider。
  static Future<bool> stopMock() async {
    try {
      await _channel.invokeMethod<bool>('stopMock');
      return true;
    } on PlatformException catch (e) {
      throw _toMockException(e);
    }
  }

  /// 读取系统 GPS_PROVIDER 上的真实坐标。
  ///
  /// **使用时机**：必须在 [stopMock] 之后调用 —— test provider 被移除后，
  /// LocationManager 会把"上一次真实 GPS fix"回填到 getLastKnownLocation(GPS) 上。
  /// 在 mock 启动时调用会拿到 null 或非常旧的 fix（被 test provider 盖掉了）。
  ///
  /// **返回 null 的语义**：
  ///  - GPS_PROVIDER 当前不可用（无硬件 / 用户关了 GPS）；
  ///  - 系统从未有过真实 fix（首次冷启动 / 长期待在室内）；
  ///  - 权限缺失（非 Android 平台走 MissingPluginException 也会返回 null）。
  ///
  /// 返回的快照只含 lat/lng/accuracy/time 四个字段，不含 isFromMockProvider
  /// （因为这个 call 的目的就是确认"这是真 GPS"，不应再被 mock 残留污染）。
  static Future<RealLocationSnapshot?> readRealLocation() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'readRealLocation',
      );
      if (res == null) return null;
      return RealLocationSnapshot(
        lat: (res['lat'] as num).toDouble(),
        lng: (res['lng'] as num).toDouble(),
        accuracy: (res['accuracy'] as num).toDouble(),
        time: (res['time'] as num).toInt(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 主动请求一帧真实定位（方案 A）。
  ///
  /// 与 [readRealLocation]（被动读 getLastKnownLocation 缓存）不同：
  ///  - 原生层注册 requestLocationUpdates 主动逼系统出一帧真实 fix；
  ///  - 8 秒超时，期间先读缓存快路径（<60s 直接返回），再等主动 fix；
  ///  - 室内冷启动也能在数秒内拿到，解决"启动 30s 拿不到位置"。
  ///
  /// 返回 null 表示 8 秒内未拿到任何真实 fix（GPS 硬件不可用 / 权限缺失）。
  ///
  /// **使用时机**：非 mock 期间（mock running 时 test provider 占用 GPS，
  /// 会污染结果，调用方应先过滤 mock 状态）。
  static Future<RealLocationSnapshot?> requestRealLocation() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'requestRealLocation',
      );
      if (res == null) return null;
      return RealLocationSnapshot(
        lat: (res['lat'] as num).toDouble(),
        lng: (res['lng'] as num).toDouble(),
        accuracy: (res['accuracy'] as num).toDouble(),
        time: (res['time'] as num).toInt(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 用高德独立定位 SDK（AMapLocationClient）拿一次"高德视角"的位置（AL 探针）。
  ///
  /// 与 [requestRealLocation]（系统 LocationManager 裸值）不同：
  ///  - 这里走的是高德定位 SDK，内部做 map-matching / 反 mock / 多源融合，
  ///    回调的坐标 == 其他高德系 APP 显示的位置，是 AL 探针真正要观测的对象；
  ///  - 替代残缺的地图蓝点回调（插件未 setLocationSource，蓝点回调永不触发）。
  ///
  /// 返回 [AmapLocationResult]：
  ///  - errorCode == 0 → 定位成功，携带 lat/lng/accuracy/locationType 等；
  ///  - errorCode != 0 → 定位失败/超时/被风控，携带 errorInfo。
  static Future<AmapLocationResult> requestAmapLocation() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'requestAmapLocation',
      );
      if (res == null) {
        return const AmapLocationResult(errorCode: -9, errorInfo: '无返回');
      }
      final code = (res['errorCode'] as num?)?.toInt() ?? -9;
      if (code != 0) {
        return AmapLocationResult(
          errorCode: code,
          errorInfo: res['errorInfo'] as String? ?? '未知错误',
        );
      }
      return AmapLocationResult(
        errorCode: 0,
        lat: (res['lat'] as num).toDouble(),
        lng: (res['lng'] as num).toDouble(),
        accuracy: (res['accuracy'] as num).toDouble(),
        time: (res['time'] as num).toInt(),
        locationType: (res['locationType'] as num?)?.toInt() ?? 0,
        locationDetail: res['locationDetail'] as String?,
        provider: res['provider'] as String?,
        isFromMockProvider: res['isFromMockProvider'] as bool? ?? false,
      );
    } on MissingPluginException {
      return const AmapLocationResult(errorCode: -9, errorInfo: '非 Android 平台');
    } on PlatformException {
      return const AmapLocationResult(errorCode: -9, errorInfo: '平台异常');
    } on TypeError {
      return const AmapLocationResult(errorCode: -9, errorInfo: '数据类型异常');
    }
  }

  static MockLocationException _toMockException(PlatformException e) {
    return MockLocationException(
      e.message ?? '调用原生层失败（code=${e.code}）',
    );
  }
}

/// MockController.stop() 之后从系统读到的"真实"GPS 快照。
///
/// 含义明确是"真实"，所以没有 isFromMockProvider 字段 —— 该字段在
/// test provider 还在的时候才有意义；stop 后系统回填的就是真实 fix。
class RealLocationSnapshot {
  final double lat;
  final double lng;
  final double accuracy;
  final int time;

  const RealLocationSnapshot({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.time,
  });
}

/// 高德独立定位 SDK 的单次定位结果（AL 探针）。
///
/// errorCode == 0 表示成功，否则携带 [errorInfo] 描述失败原因。
/// 高德标准错误码（部分）：
///  - 0    成功
///  - 4    网络连接失败
///  - 12   缺少定位权限
///  - 15   模拟定位被系统拒绝
///  - 18   定位结果被模拟位置干扰（isFromMockProvider）
///  - -2   本实现自定义：8 秒超时
///  - -3   本实现自定义：定位初始化失败
class AmapLocationResult {
  final int errorCode;
  final String? errorInfo;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final int? time;
  final int locationType;
  final String? locationDetail;
  final String? provider;
  final bool isFromMockProvider;

  const AmapLocationResult({
    required this.errorCode,
    this.errorInfo,
    this.lat,
    this.lng,
    this.accuracy,
    this.time,
    this.locationType = 0,
    this.locationDetail,
    this.provider,
    this.isFromMockProvider = false,
  });

  bool get isSuccess => errorCode == 0 && lat != null && lng != null;
}

/// Mock Location 业务异常。
/// Dart 侧捕获后可直接 toString() 显示给用户。
/// Dart 侧捕获后可直接 toString() 显示给用户。
class MockLocationException implements Exception {
  final String message;
  MockLocationException(this.message);

  @override
  String toString() => 'MockLocationException: $message';
}
