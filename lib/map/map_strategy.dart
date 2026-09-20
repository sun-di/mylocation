import 'package:flutter/widgets.dart';
import '../models/location_info.dart';
// 注释：MapMarker.markerColor 在 AMapStrategy 里通过 pinBuilder 接口生效
// 不被 dart:ui 强依赖，故直接用 dynamic 方式引入（部分 Flutter 版本
// MaterialColor 会与 Color 重名）。
// ignore: unnecessary_import
import 'package:flutter/painting.dart' show Color;

/// 地图策略抽象层
/// 通过此接口隔离具体地图 SDK（高德/百度/腾讯），
/// 业务页面只依赖该抽象，便于后续扩展第二个地图。
abstract class MapStrategy {
  /// 初始化 SDK（如设置 Key、隐私协议）
  Future<void> init();

  /// 构建地图 Widget
  ///
  /// [mapInteractive] 控制地图是否接受用户输入（手势 / tap / longPress）：
  ///  - true  → 全部手势 + tap/longPress 回调照常；
  ///  - false → 禁用所有手势，且 tap/longPress 回调不再触发
  ///    （用于 mock 启动后"锁定地图"）。
  /// 默认 true。
  Widget buildMap({
    required CameraPosition initialCamera,
    required void Function(LocationInfo picked)? onMapTap,
    required List<MapMarker> markers,
    void Function()? onMapCreated,
    void Function(LocationInfo picked)? onMapLongPress,
    void Function(LocationInfo first)? onFirstLocation,
    void Function(CameraPosition camera)? onCameraMove,
    bool mapInteractive = true,
  });

  /// 移动相机到指定位置
  Future<void> moveCamera(LocationInfo target, {double zoom = 15});

  /// 逆地理编码：根据经纬度补全街道/地址信息
  Future<LocationInfo> reverseGeocode(LocationInfo target);

  /// 输入提示（POI 联想搜索）：根据用户输入的关键字返回候选位置列表。
  ///
  /// 走高德「输入提示」接口（assistant/inputtips），这是高德搜索框
  /// 「边输入边联想」的官方接口 —— 对「软件园」这类泛化关键词也能返回
  /// 带经纬度的候选 POI（place/text 关键字搜索对泛词常返回 0 条）。
  ///
  /// 返回空列表表示无结果；多条时由调用方展示列表让用户选择。
  Future<List<LocationInfo>> inputTips(String keyword);

  /// 读取地图 SDK 当前回调的最新定位（用于拿到"SDK 反 mock 后的位置"）。
  ///
  /// 工作原理：地图 SDK（高德）在启用 myLocation 后，会通过原生层持续
  /// 回调一次反 mock 后的位置；应用 mock 前后取这个值，对比差异即可
  /// 直观看出来 AMap 是否接受了我们注入的位置。
  ///
  /// 实现需保证：
  ///  - 没拿到过位置（首次启动 / 没开 myLocation）时返回 null；
  ///  - 等待 [waitTimeout] 给 SDK 一次回调的机会；
  ///  - 等待期间已拿到过位置的变化时，返回最新一次回调（而非首帧）。
  Future<LocationInfo?> readLatestLocation({
    Duration waitTimeout = const Duration(seconds: 5),
  });
}

/// 相机位置
class CameraPosition {
  final double latitude;
  final double longitude;
  final double zoom;
  const CameraPosition({
    required this.latitude,
    required this.longitude,
    this.zoom = 15,
  });
}

/// 扎标样式。
enum MapMarkerStyle {
  /// 普通扎标（默认）。用颜色区分：蓝 = 用户选点 UL，紫 = AMap 探针 AL。
  pin,

  /// 车辆图标（圆形定位点 + 白色方向箭头），用于「真实位置 / 模拟位置」的车标。
  car,
}

/// 地图扎标
class MapMarker {
  final double latitude;
  final double longitude;
  final String? title;

  /// 扎标颜色（高德 SDK 的 [Marker.icon] 接受 [BitmapDescriptor]，
  /// 这里仅作语义标记；具体实现策略把预定义颜色映射到对应 icon）。
  ///
  /// 约定：
  ///  - null  / 蓝色  → 用户选点（UL，蓝色 pin）
  ///  - 紫色          → AMap 反 mock 后的探针位置（AL 候选）
  ///  - car 样式时：绿色 → 真实位置，红色 → 模拟位置
  final Color? markerColor;

  /// 渲染样式，默认 [MapMarkerStyle.pin]。
  final MapMarkerStyle style;

  const MapMarker({
    required this.latitude,
    required this.longitude,
    this.title,
    this.markerColor,
    this.style = MapMarkerStyle.pin,
  });
}
