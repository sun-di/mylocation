import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart' as amap;
import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart' as b;
import 'map_strategy.dart';
import '../models/location_info.dart';

/// 高德地图策略实现（基于社区维护的 csp_amap_flutter_map，兼容 AGP8）
///
/// ⚠️ Key **不再硬编码在源码里**（公开仓库会泄露），改为构建期注入：
///
/// ```bash
/// # 1) 复制模板并填入自己的 Key
/// cp keys/dart_define.example.json keys/dart_define.json
/// # 2) 运行 / 构建时带上（keys/dart_define.json 已在 .gitignore 中）
/// flutter run --dart-define-from-file=keys/dart_define.json
/// flutter build apk --release --dart-define-from-file=keys/dart_define.json
/// ```
///
/// Key 申请：https://console.amap.com/
///   - Android Key：用「包名 + 打包签名 SHA1」申请
///   - iOS Key：用 BundleId 申请（留空时回退使用 Android Key）
///   - Web 服务 Key：逆地理编码 / 输入提示 REST 接口专用，与 Android Key 分开申请
const String _amapAndroidKey = String.fromEnvironment('AMAP_ANDROID_KEY');
const String _amapIOSKey = String.fromEnvironment('AMAP_IOS_KEY');
const String _amapWebKey = String.fromEnvironment('AMAP_WEB_KEY');

class AMapStrategy implements MapStrategy {
  static bool _inited = false;

  /// 是否已注入高德地图 Key（Android Key 为空视为未配置）。供 UI 提示使用。
  static bool get hasMapKey => _amapAndroidKey.isNotEmpty;

  /// 是否已注入高德 Web 服务 Key（逆地理编码 / 输入提示使用）。
  static bool get hasWebKey => _amapWebKey.isNotEmpty;

  /// 高德 Android Key。供传给原生定位 SDK（AL 探针的 `AMapLocationClient` 需要独立 Key）。
  /// 未注入时为空字符串。
  static String get androidKey => _amapAndroidKey;

  /// 4 枚图标全部从 assets/icons 加载（在 pubspec.yaml 已声明）。
  /// 启动时由 [ensureIcons] 一次性读入并缓存，buildMap 里按需取用。
  static amap.BitmapDescriptor? _carGreenIcon;
  static amap.BitmapDescriptor? _carRedIcon;
  static amap.BitmapDescriptor? _pinBlueIcon;
  static amap.BitmapDescriptor? _pinVioletIcon;

  /// 一次性加载 4 枚图标（asset PNG → ByteData → BitmapDescriptor）。
  /// 同步版本：从 asset 加载不需要异步等待，原来的 [ensureCarIcons] 是 async
  /// 是因为以前用 dart:ui 程序化绘制。
  static void ensureIcons() {
    if (_carGreenIcon != null &&
        _carRedIcon != null &&
        _pinBlueIcon != null &&
        _pinVioletIcon != null) {
      return;
    }
    _carGreenIcon = amap.BitmapDescriptor.fromIconPath(
      'assets/icons/car_green.png',
    );
    _carRedIcon = amap.BitmapDescriptor.fromIconPath(
      'assets/icons/car_red.png',
    );
    _pinBlueIcon = amap.BitmapDescriptor.fromIconPath(
      'assets/icons/pin_blue.png',
    );
    _pinVioletIcon = amap.BitmapDescriptor.fromIconPath(
      'assets/icons/pin_violet.png',
    );
  }
  /// 当前 widget 实例内是否已经触发过首次定位回调。
  /// 之前是 static，会导致 APP 第二次冷启动后 onFirstLocation 永不再触发，
  /// _initCamera 设的"上次真实坐标"缓存点就被冻住，5 秒 GPS 窗口失效。
  /// 改成 instance 字段 → widget 重建时自然重置。
  bool _firstLocationFired = false;

  amap.AMapController? _controller;
  // 跨 AMapWidget 重建保留：只要曾经定位成功，坐标就不丢失
  static b.AMapLocation? _currentLocation;

  /// 上一次真实 GPS 位置（mock 启动前的快照）。
  ///
  /// 用途：mock 启动时 [_currentLocation] 必然是真实 GPS（因为此前 [_mockingActive]
  /// 为 false，所有 SDK 回调都正常写入），把它快照到这里；
  /// mock 停止时再把 [_currentLocation] 恢复成这个值，避免"回到当前位置"按钮
  /// 跳到 mock 期间的 ML（海里）。
  ///
  /// 关键点：[_currentLocation] 在 mock 期间**不再被拦截**，会持续接收 SDK 回调
  /// —— 可能是 ML（SDK 接受 mock）或真实 GPS（SDK 反 mock 走真 GPS）。这套
  /// 数据是 Plan B 的 [_HomePageState._runProbe] 5 秒 AL 探测的来源。
  static b.AMapLocation? _lastKnownRealLocation;

  /// 是否处于 mock 进行中。
  ///
  /// 由 [setMockActive] 从 HomePage 同步传入。
  ///
  /// 修复后行为：
  ///  - mock 期间：[onLocationChanged] **正常**写入 [_currentLocation]，
  ///    让反推 control loop 拿到的 AL 反映"SDK 实际看到的"位置；
  ///  - mock 期间：[onFirstLocation] **不触发**（避免跳到 ML）；
  ///  - stop mock：[_currentLocation] 被恢复为 [_lastKnownRealLocation]，
  ///    下一帧真实 GPS 到达时再自然覆盖。
  bool _mockingActive = false;

  /// 切换 mock 状态。由 HomePage 在 _applyToSystem 成功后调 true，
  /// _stopMock 中调 false。
  ///
  /// 状态切换时同步维护 [_lastKnownRealLocation] 快照：
  ///  - true：保存当前 [_currentLocation]（必然是真实 GPS，因为此前允许写入），
  ///    留作 stop 时的"最后一次真实位置"；
  ///  - false：把 [_currentLocation] 恢复成 [_lastKnownRealLocation]，
  ///    让"回到当前位置"按钮立即可用，直到下一帧真实 GPS 自然覆盖。
  void setMockActive(bool active) {
    if (active && !_mockingActive) {
      // 进入 mock：把"最后一次真实 GPS"快照保存
      _lastKnownRealLocation = _currentLocation;
    } else if (!active && _mockingActive) {
      // 退出 mock：恢复 _currentLocation 为真实 GPS，避免 FAB 跳到海里 ML
      _currentLocation = _lastKnownRealLocation;
    }
    _mockingActive = active;
  }

  /// 初始化高德 SDK（隐私合规 + Key）。需要在有 BuildContext 时调用，
  /// 建议在首个页面 initState 中执行（见 HomePage）。
  static Future<void> initWithContext(BuildContext context) async {
    if (_inited) return;
    if (!hasMapKey) {
      debugPrint(
        '[AMap] ⚠️ 未配置高德 Key：地图将无法加载。'
        '请用 flutter run/build --dart-define-from-file=keys/dart_define.json 启动'
        '（模板见 keys/dart_define.example.json）。',
      );
    }
    // 隐私合规：用户同意隐私政策后调用（此处默认已同意，正式发布前接入隐私弹窗）
    amap.AMapInitializer.updatePrivacyAgree(
      const b.AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
    );
    amap.AMapInitializer.init(
      context,
      apiKey: b.AMapApiKey(
        androidKey: _amapAndroidKey,
        // iOS Key 留空时回退用 Android Key（两者常为同一串）
        iosKey: _amapIOSKey.isEmpty ? _amapAndroidKey : _amapIOSKey,
      ),
    );
    ensureIcons(); // 同步从 assets/icons 加载 4 枚图标，无需 await
    _inited = true;
  }

  @override
  Future<void> init() async {
    // 真正的初始化需要 context，由 initWithContext 在页面 initState 中完成
  }

  @override
  Widget buildMap({
    required CameraPosition initialCamera,
    required void Function(LocationInfo picked)? onMapTap,
    required List<MapMarker> markers,
    void Function()? onMapCreated,
    void Function(LocationInfo picked)? onMapLongPress,
    void Function(LocationInfo first)? onFirstLocation,
    void Function(CameraPosition camera)? onCameraMove,
    bool mapInteractive = true,
  }) {
    final Set<amap.Marker> amapMarkers = {
      for (final m in markers)
        amap.Marker(
          position: b.LatLng(m.latitude, m.longitude),
          icon: _resolveMarkerIcon(m),
          // ⚠️ 关键：关闭 SDK 自带 InfoWindow，因为：
          //  - 它由 Flutter widget 渲染，相机移动不会自动消失（旧 bug）；
          //  - 改为上层 Flutter 自己用 `_PickedLocationBubble` 实现可控的气泡。
          infoWindowEnable: false,
        ),
    };
    return amap.AMapWidget(
      initialCameraPosition: amap.CameraPosition(
        target: b.LatLng(initialCamera.latitude, initialCamera.longitude),
        zoom: initialCamera.zoom,
      ),
      // 开启"我的位置"小蓝点，并监听 GPS 定位回调
      myLocationEnabled: true,
      myLocationStyleOptions: amap.MyLocationStyleOptions(true),
      markers: amapMarkers,
      // === 地图可交互性：4 个独立手势开关 + tap/longPress 回调 ===
      // 锁定地图 = 关掉所有手势 + 不传 tap/longPress 回调
      zoomGesturesEnabled: mapInteractive,
      scrollGesturesEnabled: mapInteractive,
      rotateGesturesEnabled: mapInteractive,
      tiltGesturesEnabled: mapInteractive,
      // 把相机移动回调透传给上层，用于：
      //  - 用户滚动地图时关闭长按弹出的"经纬度大气泡"（修复相机移动后气泡残留）；
      //  - 其它需要感知相机变化的 UI 行为。
      onCameraMove: onCameraMove == null
          ? null
          : (amap.CameraPosition p) => onCameraMove(
              CameraPosition(
                latitude: p.target.latitude,
                longitude: p.target.longitude,
                zoom: p.zoom,
              ),
            ),
      onMapCreated: (controller) {
        _controller = controller;
        onMapCreated?.call();
      },
      onLocationChanged: (b.AMapLocation loc) {
        // ★ 修复"AMap 未返回位置"的根因：mock 期间不再拦截 SDK 回调。
        //
        // 旧逻辑：mock 期间 if (_mockingActive) return → _currentLocation 不更新 →
        //         HomePage._runProbe 5s timeout 永远读到 null → UI 误报
        //         "SDK 可能被风控拒掉"。
        // 新逻辑：mock 期间也写入 _currentLocation，_runProbe 才能拿到真实的
        //         AL（可能是 ML，说明 SDK 接受 mock；也可能是真实 GPS，
        //         说明 SDK 反 mock 走真 GPS）。stop mock 时 setMockActive(false)
        //         把 _currentLocation 恢复为 _lastKnownRealLocation，避免
        //         FAB 跳到海里 ML。
        AMapStrategy._currentLocation = loc;
        debugPrint(
          '[AMap] onLocationChanged: lat=${loc.latLng.latitude}, lng=${loc.latLng.longitude}'
          '${_mockingActive ? " (mock 期间)" : ""}',
        );
        // 首次拿到定位：移动地图到当前位置。
        // mock 期间回调的是 ML，跳过去就错了 —— 跳过 onFirstLocation。
        // _firstLocationFired 仍置 true，因为启动后再有真实 GPS 回调
        // 也不应该自动跳图（用户已经在地图上）。
        if (!_firstLocationFired) {
          _firstLocationFired = true;
          if (_mockingActive) return;
          onFirstLocation?.call(
            LocationInfo(
              latitude: loc.latLng.latitude,
              longitude: loc.latLng.longitude,
            ),
          );
        }
      },
      // tap：mock 锁定时整个回调关闭（不传 null）
      onTap: !mapInteractive || onMapTap == null
          ? null
          : (b.LatLng latLng) {
              onMapTap(
                LocationInfo(
                  latitude: latLng.latitude,
                  longitude: latLng.longitude,
                ),
              );
            },
      onLongPress: !mapInteractive || onMapLongPress == null
          ? null
          : (b.LatLng latLng) {
              onMapLongPress(
                LocationInfo(
                  latitude: latLng.latitude,
                  longitude: latLng.longitude,
                ),
              );
            },
    );
  }

  /// 把语义（样式 + 颜色）映射到高德图标。
  /// 全部使用 assets/icons 下的 PNG：
  ///  - car 样式 → car_green.png（真实位置）/ car_red.png（模拟位置）
  ///  - pin 样式 → pin_blue.png（UL）/ pin_violet.png（AL 探针）
  amap.BitmapDescriptor _resolveMarkerIcon(MapMarker m) {
    final color = m.markerColor;

    if (m.style == MapMarkerStyle.car) {
      final isRed = color != null &&
          color.r > 0.7 && color.g < 0.4 && color.b < 0.4;
      return isRed
          ? (_carRedIcon ??
              amap.BitmapDescriptor.defaultMarkerWithHue(
                  amap.BitmapDescriptor.hueRed))
          : (_carGreenIcon ??
              amap.BitmapDescriptor.defaultMarkerWithHue(
                  amap.BitmapDescriptor.hueGreen));
    }

    // pin 样式：无颜色或非紫色 → 蓝；有紫色族 → 紫
    final isViolet =
        color != null && color.r > 0.4 && color.b > 0.4 && color.g < 0.4;
    return isViolet
        ? (_pinVioletIcon ??
            amap.BitmapDescriptor.defaultMarkerWithHue(
                amap.BitmapDescriptor.hueViolet))
        : (_pinBlueIcon ??
            amap.BitmapDescriptor.defaultMarkerWithHue(
                amap.BitmapDescriptor.hueBlue));
  }

  /// 清掉 SDK 缓存的"最近一次定位"快照。
  ///
  /// 用于：
  ///  - mock stop 之后：SDK 在 mock 期间回调的 fix 不可信（通常是 mock 坐标），
  ///    必须清掉，否则下次"回到当前位置"会跳到那个海里的坐标。
  ///  - 想强制让上层重新等待新 GPS fix 时。
  ///
  /// 调用安全：无副作用，仅清空静态缓存字段，不影响 SDK 内部 LocationManager。
  ///
  /// 修复后说明：mock 期间 onLocationChanged 不再被拦截，_currentLocation
  /// 持续接收 SDK 回调。stop mock 时 setMockActive(false) 主动恢复为
  /// _lastKnownRealLocation，所以 clearCurrentLocation() 在 stop 流程中
  /// 已不再调用 —— 调用方如果真正需要"丢掉当前缓存重新等新 fix"再调即可。
  static void clearCurrentLocation() {
    _currentLocation = null;
  }

  /// 返回当前 GPS 定位（若已拿到），否则返回 null
  LocationInfo? get currentLocation {
    final loc = AMapStrategy._currentLocation;
    if (loc == null) return null;
    return LocationInfo(
      latitude: loc.latLng.latitude,
      longitude: loc.latLng.longitude,
    );
  }

  /// 等待并返回 AMap SDK 当前回调的最新位置。
  ///
  /// 应用 mock 之后，调用方应该等几秒再调用本方法：
  ///   - 给高德 SDK 一次反 mock + 上报的窗口；
  ///   - 应用前 / 应用后两次调用，对比差异；
  ///   - **返回值就是 AMap 反 mock 后的位置**（这是 Plan B 的 AL 探测源）。
  ///
  /// 实现：每 500ms 读一次 [AMapStrategy._currentLocation]，保留最后一次
  /// 观察到的值。SDK 持续回调时，能拿到"距离调用时刻最近"的 fix；
  /// SDK 不再回调（被风控拒）时，返回"上次看到"的最后值，不为 null。
  ///
  /// 修复后：mock 期间 _currentLocation 持续更新（ML 或反 mock 后的真实 GPS），
  /// 所以 5 秒内一定拿得到回调，UI 不再误报"SDK 可能被风控拒掉"。
  @override
  Future<LocationInfo?> readLatestLocation({
    Duration waitTimeout = const Duration(seconds: 5),
  }) async {
    final start = DateTime.now();
    LocationInfo? last;
    while (DateTime.now().difference(start) < waitTimeout) {
      final cur = currentLocation;
      if (cur != null) last = cur;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (last == null) return null;
    debugPrint(
      '[AMap] readLatestLocation: lat=${last.latitude.toStringAsFixed(6)}, '
      'lng=${last.longitude.toStringAsFixed(6)}',
    );
    return last;
  }

  @override
  Future<void> moveCamera(LocationInfo target, {double zoom = 15}) async {
    debugPrint('[AMap] moveCamera: controller=${_controller != null}, '
        'lat=${target.latitude}, lng=${target.longitude}');
    if (_controller == null) return;
    await _controller!.moveCamera(
      amap.CameraUpdate.newLatLngZoom(
        b.LatLng(target.latitude, target.longitude),
        zoom,
      ),
    );
  }

  @override
  Future<LocationInfo> reverseGeocode(LocationInfo target) async {
    if (!hasWebKey) {
      debugPrint('[AMap] 未配置 Web 服务 Key，跳过逆地理编码');
      return target;
    }
    // 高德 Web 逆地理编码 REST 接口，使用 Web 服务 Key
    final url = Uri.parse(
      'https://restapi.amap.com/v3/geocode/regeo'
      '?key=$_amapWebKey'
      '&location=${target.longitude},${target.latitude}'
      '&extensions=all&radius=1000&roadlevel=0',
    );
    try {
      final resp = await http.get(url);
      debugPrint('[AMap] regeo statusCode=${resp.statusCode}');
      debugPrint('[AMap] regeo body=${resp.body}');
      if (resp.statusCode != 200) return target;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['status'] != '1') return target;
      final regeocode = data['regeocode'] as Map<String, dynamic>?;
      if (regeocode == null) return target;

      final addressComponent =
          regeocode['addressComponent'] as Map<String, dynamic>? ?? {};
      final province = addressComponent['province'] as String?;
      final city = addressComponent['city'] as String?;
      final district = addressComponent['district'] as String?;
      final road = addressComponent['road'] as String?;
      final formatted = regeocode['formatted_address'] as String?;

      // 道路名拼接：道路 + 门牌号（若有）
      final streetNum = addressComponent['streetNumber'] as Map<String, dynamic>?;
      final roadDetail = streetNum != null
          ? '${road ?? ''}${streetNum['number'] ?? ''}'.trim()
          : (road ?? '').trim();

      return target.copyWith(
        province: province,
        city: (city != null && city.isNotEmpty) ? city : province,
        district: district,
        road: roadDetail.isNotEmpty ? roadDetail : null,
        address: formatted,
      );
    } catch (e) {
      return target;
    }
  }

  @override
  Future<List<LocationInfo>> inputTips(String keyword) async {
    if (!hasWebKey) {
      debugPrint('[AMap] 未配置 Web 服务 Key，跳过输入提示');
      return const [];
    }
    // 高德 Web 服务「输入提示」REST 接口，复用 Web 服务 Key。
    // 这是高德官方 App 搜索框「边输入边联想」用的接口，对泛化关键词
    // （如「软件园」）也能返回带经纬度的候选，而 place/text 对泛词常返回 0 条。
    // 返回 tips[] 每条含 name / location("lng,lat") / address / district。
    final url = Uri.parse(
      'https://restapi.amap.com/v3/assistant/inputtips'
      '?key=$_amapWebKey'
      '&keywords=${Uri.encodeComponent(keyword)}'
      '&datatype=poi',
    );
    try {
      final resp = await http.get(url);
      debugPrint('[AMap] inputtips statusCode=${resp.statusCode}');
      debugPrint('[AMap] inputtips body=${resp.body}');
      if (resp.statusCode != 200) return const [];
      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['status'] != '1') return const [];

      final tips = data['tips'] as List<dynamic>?;
      if (tips == null || tips.isEmpty) return const [];

      final results = <LocationInfo>[];
      for (final t in tips) {
        final tip = t as Map<String, dynamic>;
        // 跳过没有经纬度的联想项（纯关键词兜底项 / 公交线路提示）。
        final loc = tip['location'] as String?; // "lng,lat"
        if (loc == null || loc.isEmpty || !loc.contains(',')) continue;
        final parts = loc.split(',');
        if (parts.length < 2) continue;
        final lng = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lng == null || lat == null) continue;

        final name = tip['name'] as String?;
        final address = tip['address'] as String?; // inputtips 的 address 是 String
        final district = tip['district'] as String?; // 完整「省市区」串

        results.add(LocationInfo(
          latitude: lat,
          longitude: lng,
          name: name,
          address: (address != null && address.isNotEmpty) ? address : null,
          district: district,
        ));
      }
      return results;
    } catch (e) {
      debugPrint('[AMap] inputtips 异常: $e');
      return const [];
    }
  }
}
