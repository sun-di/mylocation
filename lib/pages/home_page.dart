import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../map/map_strategy.dart';
import '../map/amap_strategy.dart' show AMapStrategy;
import '../mock_location/mock_controller.dart';
import '../mock_location/mock_service.dart';
import '../models/location_info.dart';
import '../persistence/location_bookmark.dart';
import 'bookmarks_page.dart';

/// 首页：地图选点 + Mock Location 控制
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _strategy = AMapStrategy();
  /// 初始相机（默认天安门）。启动后由 AMap SDK 在 [AMapStrategy.buildMap]
  /// 的 [onFirstLocation] 回调拿到首帧真实 GPS 后自动 moveCamera 跳过去；
  /// 不再读任何"上次真实坐标"缓存 —— 每次冷启动都等 SDK 实时上报。
  final CameraPosition _initCamera = const CameraPosition(
    latitude: 39.909187,
    longitude: 116.397451,
    zoom: 15,
  );

  /// 蓝扎标：用户选点（UL）。
  final List<MapMarker> _markers = [];
  LocationInfo? _selected;
  bool _mapReady = false;

  /// 红扎标：AMap SDK 反 mock 探针位置（AL 候选）。
  /// 应用 mock 之后通过 [AMapStrategy.readLatestLocation] 拿到的最新值。
  /// 拿到后用红色扎标叠加显示，便于直观对比 UL/AL 差异。
  MapMarker? _probeMarker;

  /// 绿色车辆图标：真实位置（启动定位成功后固定，生命周期内常驻）。
  MapMarker? _realMarker;

  /// 红色车辆图标：mock 成功后叠加在 UL 上（替代蓝色扎标），stop 后清除。
  MapMarker? _mockCarMarker;

  /// 探针 vs 选点的偏差（米），用于在状态对话框里显示"AL 探针偏差"。
  /// 用 [ValueNotifier] 承载，便于 [_MockStatusDialog] 实时监听刷新。
  final ValueNotifier<double?> _probeDeviation = ValueNotifier<double?>(null);

  /// 长按地图弹出的"经纬度大气泡"是否可见。
  ///
  /// 行为契约：
  ///  - 长按地图 / 点击地图选点 → 显示气泡；
  ///  - 滚动地图（相机移动） → 立即隐藏气泡；
  ///  - 再次长按地图 → 重新显示气泡。
  ///
  /// 实现说明：SDK 自带的 InfoWindow 关闭了（见 [AMapStrategy.buildMap] 的
  /// `infoWindowEnable: false`），这里用 Flutter 自己的 [_PickedLocationBubble]
  /// 在 Stack 上叠一个固定位置（屏幕中央偏上）的卡片，完全控制可见性。
  bool _bubbleVisible = false;

  /// 地图是否接受用户输入。false = 锁定所有手势 + 禁掉 tap/longPress 回调。
  ///
  /// 行为契约：
  ///  - mock 启动成功 → 设为 false，气泡常驻（因为锁后不再触发 onCameraMove）；
  ///  - 用户点"停止模拟" → 设回 true，气泡自动按旧规则隐藏。
  ///  - App 切到后台时不动这个值（mock 状态自然变化即可）。
  bool _mapInteractive = true;

  /// 顶部搜索框的文本控制器 + 焦点节点。
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// 是否正在搜索（控制搜索按钮 loading 态，防重复点击）。
  bool _searching = false;

  /// 输入联想候选列表（随输入实时刷新，展示在搜索框正下方）。
  List<LocationInfo> _suggestions = [];

  /// 输入防抖定时器：停止输入 300ms 后才发起联想请求，避免每敲一个字就打一次接口。
  Timer? _suggestionDebounce;

  // Mock Location 控制器，全生命周期持有。
  // 必须 late final：在 initState 中构造，因为构造时需要把 _strategy
  // 的 readLatestLocation 注入做"反推读 AL 回调"。
  late final MockController _mock;

  @override
  void initState() {
    super.initState();
    // 构造 MockController 并注入"读 AMap 反 mock 后位置"回调，
    // 让反推 control loop 能拿到 AL 来校准 ML。
    // ★ 改用高德独立定位 SDK（AMapLocationClient）作为 AL 探针：
    //   地图蓝点回调（readLatestLocation）因插件未 setLocationSource 而永不触发，
    //   改为直调原生 AMapLocationClient 拿"高德视角加工后"的位置。
    _mock = MockController(
      readAlProbe: ({
        Duration waitTimeout = const Duration(seconds: 5),
      }) async {
        final res = await MockService.requestAmapLocation();
        if (res.isSuccess) {
          return LocationInfo(latitude: res.lat!, longitude: res.lng!);
        }
        return null;
      },
    );
    _mock.calibrationListenable.addListener(_onCalibrationChanged);
    // 注册生命周期监听：用于 AppLifecycleState.paused 兜底清理 mock。
    WidgetsBinding.instance.addObserver(this);
    _requestLocationPermission();
    // 初始化高德 SDK（需要 context）。必须在地图 Widget 创建前完成，
    // 否则会白屏。init 是同步的，完成后 setState 触发 build 才真正建地图。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AMapStrategy.initWithContext(context);
      // P0 修复：把高德 Android Key 传给原生定位 SDK（AL 探针的 AMapLocationClient
      // 需要独立 Key，地图 SDK 经 AMapInitializer 设置的 Key 不会自动给它）。
      await MockService.setAmapApiKey(AMapStrategy.androidKey);
      if (mounted) setState(() => _mapReady = true);
      // Key 未注入时给出明确提示（否则表现为"地图一直空白"，难排查）。
      if (!AMapStrategy.hasMapKey && mounted) {
        _snack('未配置高德 Key：请用 --dart-define-from-file=keys/dart_define.json 启动');
      }
      await _applyAlwaysBookmarkIfAny();
    });
  }

  /// 启动时：若存在被勾选 "always" 的书签，自动将其应用到系统。
  Future<void> _applyAlwaysBookmarkIfAny() async {
    final alwaysId = await LocationBookmarks.readAlwaysId();
    if (alwaysId == null) return;
    final list = await LocationBookmarks.readAll();
    LocationBookmark? target;
    for (final e in list) {
      if (e.id == alwaysId) {
        target = e;
        break;
      }
    }
    if (target == null || !mounted) return;
    await _applyBookmarkLocation(target);
  }

  /// 反推进度变化回调：把"最新一轮 AL"同步到地图探针扎标 + 偏差米数。
  /// 偏差同步到 [_probeDeviation] notifier，供状态对话框实时监听。
  void _onCalibrationChanged() {
    if (!mounted) return;
    final p = _mock.calibration;
    final al = p.alProbe;
    setState(() {
      if (al != null) {
        _probeMarker = MapMarker(
          latitude: al.latitude,
          longitude: al.longitude,
          title: 'AMap 探针',
          markerColor: Colors.purple, // 紫色 pin = AL 探针（避免与红色车标混淆）
        );
      }
    });
    // 首轮时 initialDeviation 还没建立，currentDeviation 可能为 null；
    // 但只要有 alProbe，currentDeviation 一定有值。
    _probeDeviation.value = p.currentDeviation;
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mock.calibrationListenable.removeListener(_onCalibrationChanged);
    _mock.dispose();
    _probeDeviation.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isPermanentlyDenied) {
      // 提示用户去设置页开启
      await openAppSettings();
    }
  }

  Future<void> _onMapTap(LocationInfo picked) async {
    // 逆地理编码补全街道/地址
    final enriched = await _strategy.reverseGeocode(picked);
    _selectLocation(enriched, showBubble: true);
  }

  /// 通用"选中一个点"逻辑：设置 _selected + 蓝扎标 + 气泡 + 清空探针/模拟车标。
  ///
  /// 被「地图点选」（[_onMapTap]）与「关键字搜索命中」共用，
  /// 保证搜索命中后与 tab 流程完全一致（可保存、可「应用到系统」）。
  ///
  /// [showBubble]：是否立即显示"已选位置"气泡。地图点选为 true；
  /// 搜索命中后紧接 moveCamera，气泡由用户滚动地图时自然隐藏，此处也传 true 保持体验一致。
  void _selectLocation(LocationInfo location, {bool showBubble = true}) {
    if (!mounted) return;
    final marker = MapMarker(
      latitude: location.latitude,
      longitude: location.longitude,
      title: location.displayText,
      markerColor: Colors.blue, // 蓝扎标 = 用户选点 UL
    );
    setState(() {
      _selected = location;
      _markers.clear();
      _markers.add(marker);
      _bubbleVisible = showBubble;
      // ★ 选了新点（UL 变了），旧的 AL 探针/偏差对新基准无意义，清空
      _probeMarker = null;
      _probeDeviation.value = null;
      _mockCarMarker = null; // 防御：选了新点，清掉旧的模拟车标
    });
  }

  /// 相机移动回调：滚动 / 缩放地图时立即隐藏"经纬度大气泡"。
  ///
  /// 用户期望的行为：
  ///  - 长按地图 → 弹气泡
  ///  - 滚动地图 → 气泡消失
  ///  - 再次长按地图 → 气泡再次出现
  void _onCameraMove(CameraPosition _) {
    if (_bubbleVisible) {
      setState(() => _bubbleVisible = false);
    }
  }

  /// 地图创建完成后：主动定位并跳转到当前位置。
  ///
  /// ★ 优先用高德定位 SDK（requestAmapLocation）拿"高德视角"的位置，
  ///   使其与右上角 SDK 自带的"我的位置"蓝点同源、基本重合，避免裸 GPS
  ///   在城区楼宇环境下漂移几百米造成绿车标与蓝点严重不一致。
  ///   仅在非 mock 期间使用（mock 时高德会反 mock，本方法只在启动时调用一次）。
  /// 失败时 fallback 到系统裸 GPS（requestRealLocation），保证冷启动
  /// （首次无网络定位）也能显示绿车标。
  /// 拿不到就静默保持默认视图，不弹错误（避免启动时打断用户）。
  Future<void> _onMapCreated() async {
    // 1) 优先：高德定位 SDK（与右上角 SDK 蓝点同源）
    final amap = await MockService.requestAmapLocation();
    if (amap.isSuccess && amap.lat != null && amap.lng != null && mounted) {
      setState(() {
        _realMarker = MapMarker(
          latitude: amap.lat!,
          longitude: amap.lng!,
          title: '真实位置',
          markerColor: Colors.green,
          style: MapMarkerStyle.car,
        );
      });
      await _strategy.moveCamera(
        LocationInfo(latitude: amap.lat!, longitude: amap.lng!),
      );
      return;
    }

    // 2) 兜底：系统裸 GPS（冷启动 / 无网络定位时）
    final me = await MockService.requestRealLocation();
    if (me != null && mounted) {
      setState(() {
        _realMarker = MapMarker(
          latitude: me.lat,
          longitude: me.lng,
          title: '真实位置',
          markerColor: Colors.green,
          style: MapMarkerStyle.car,
        );
      });
      await _strategy.moveCamera(
        LocationInfo(latitude: me.lat, longitude: me.lng),
      );
    }
  }

  Future<void> _backToMyLocation() async {
    final me = await _waitForLocationWithPermission(
      promptOnMock: '请先停止模拟，再回到真实位置',
    );
    if (me == null || !mounted) return;
    // ★ 移动相机的同时补画绿车标：无论启动时序如何，
    //   点一下定位图标，绿车标必现并常驻（避免启动时定位未就绪导致车标缺失）。
    setState(() {
      _realMarker = MapMarker(
        latitude: me.latitude,
        longitude: me.longitude,
        title: '真实位置',
        markerColor: Colors.green,
        style: MapMarkerStyle.car,
      );
    });
    await _strategy.moveCamera(me);
  }

  Future<void> _showCurrentAddress() async {
    final me = await _waitForLocationWithPermission(
      promptOnMock: '请先停止模拟，再查看当前位置',
    );
    if (me == null || !mounted) return;
    final info = await _strategy.reverseGeocode(me);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('当前位置是${info.displayText}')),
    );
  }

  /// 搜索按钮回调：调输入提示搜索，多结果弹列表让用户选，单结果直接采用。
  Future<void> _onSearch(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      _snack('请输入关键字');
      return;
    }
    if (_searching) return;
    _suggestionDebounce?.cancel(); // 关掉还没触发的联想，避免与搜索结果打架
    _searchFocusNode.unfocus();
    setState(() {
      _searching = true;
      _suggestions = [];
    });
    try {
      final results = await _strategy.inputTips(kw);
      if (!mounted) return;
      if (results.isEmpty) {
        _snack('未找到「$kw」相关位置');
        return;
      }
      if (results.length == 1) {
        await _applySearchResult(results.first);
        return;
      }
      // 多个候选 → 弹底部列表让用户选
      final chosen = await _showSearchResultsSheet(results);
      if (chosen != null && mounted) {
        await _applySearchResult(chosen);
      }
    } catch (e) {
      debugPrint('[Search] 搜索异常: $e');
      if (mounted) _snack('搜索失败：$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// 输入框内容变化回调：防抖 300ms 后拉取输入提示（联想），展示在搜索框下方。
  void _onSearchTextChanged(String text) {
    _suggestionDebounce?.cancel();
    final kw = text.trim();
    if (kw.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _strategy.inputTips(kw);
      if (!mounted) return;
      // 用户在这期间又改了输入 → 丢弃这次过期结果
      if (_searchController.text.trim() != kw) return;
      setState(() => _suggestions = results);
    });
  }

  /// 采用一个搜索结果：设为选中点 + 迁移地图到该位置（与 tab 流程一致）。
  Future<void> _applySearchResult(LocationInfo result) async {
    // 收起键盘 + 收起联想下拉
    _searchFocusNode.unfocus();
    setState(() => _suggestions = []);
    // 把选中的 POI 名回填到搜索框（程序改 text 不触发 onChanged，不会重复联想）
    _searchController.text = result.displayText;
    // 设为选中点（蓝扎标 + 气泡），后续可保存 / 可「应用到系统」
    _selectLocation(result, showBubble: true);
    // 迁移地图到关键字位置。moveCamera 是 channel 调用，可能挂起，
    // 用 fire-and-forget 避免阻塞（与书签 Run 的写法一致）。
    // ignore: unawaited_futures
    _strategy.moveCamera(result).catchError((_) {
      // 地图 controller 尚未就绪时忽略移动失败。
    });
  }

  /// 弹出底部候选列表，返回用户选中的 LocationInfo（取消返回 null）。
  Future<LocationInfo?> _showSearchResultsSheet(List<LocationInfo> results) {
    return showModalBottomSheet<LocationInfo>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '搜索结果',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    return ListTile(
                      leading: const Icon(Icons.place, color: Colors.blue),
                      title: Text(
                        r.displayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: r.address != null && r.address!.isNotEmpty
                          ? Text(
                              r.address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () => Navigator.of(ctx).pop(r),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// "保存" 按钮：把当前 _selected（用户在地图上选中的点 / UL）写入本地书签。
  ///
  /// 设计：方案 A —— 只存 UL（用户主观意图的位置）。
  ///  - 不依赖真 GPS（与 mock 状态无关，mock 期间也能保存）；
  ///  - 不依赖 mock 反推后的 ML（保留用户原始意图）；
  ///  - 下次历史页 Go 时，_strategy.moveCamera 跳到 UL，
  ///    与 AMap SDK 上报的 AL 自动做反推（4 轮 ML_i = 2·UL − AL_{i-1}）。
  ///
  /// 流程：
  ///  1. 防御性空检查（按钮理论上能挡住 _selected == null 的情形）；
  ///  2. [_promptBookmarkName] 弹对话框让用户改名（默认填 displayText）；
  ///  3. 用户点取消 → 直接 return；点确认 → 写入书签；
  ///  4. 上限 10 个 → [LocationBookmarks.add] 抛 StateError → snackbar 提示并 return。
  Future<void> _bookmarkSelectedLocation() async {
    final sel = _selected;
    if (sel == null || !mounted) return;

    // 弹对话框让用户改名。空字符串视为取消（避免清空名称保存成空 name）。
    final userName = await _promptBookmarkName(
      defaultName: sel.displayText,
      latitude: sel.latitude,
      longitude: sel.longitude,
      address: sel.address,
    );
    if (userName == null || !mounted) return; // 用户点了取消

    final bm = LocationBookmark.create(
      latitude: sel.latitude,
      longitude: sel.longitude,
      name: userName.trim().isEmpty ? sel.displayText : userName.trim(),
      address: sel.address,
    );
    try {
      await LocationBookmarks.add(bm);
    } on StateError catch (e) {
      // 上限提示兜底（按钮理论上能挡住这种情形，但并发可能漏过）
      if (!mounted) return;
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    _snack('已保存：${bm.displayText}');
  }

  /// "保存"对话框：返回用户输入的名字，取消时返回 null。
  ///
  /// - 默认值：[defaultName] = address（取自逆地理）或经纬度 fallback。
  /// - 副标题展示经纬度 + address，让用户确认"这就是要保存的点"。
  /// - 30 字以内（避免 UI 列表被压扁），无则与取消等价。
  /// 弹出对话框让用户为收藏点改名，返回输入的字符串（取消时返回 null）。
  ///
  /// 为什么用 [StatefulWidget] 而不是 `_bookmarkSelectedLocation` 里直接
  /// `showDialog` + builder 闭包 + `controller.dispose()`：
  ///  - TextEditingController 必须在 TextField dispose 之后**再** dispose，
  ///    但 builder 闭包外的 controller 拿不准 TextField 的 unmount 时机；
  ///  - 早期版本曾触发 framework.dart line 6268 附近的
  ///    `InheritedElement._dependents.isEmpty` 断言（焦点/滚动等
  ///    InheritedWidget 在 deactivate 时还有 dependents 引用）；
  ///  - StatefulWidget 让 controller.dispose() 与 dispose() 同步触发，
  ///    是 Flutter 官方推荐写法，避免任何时序 race。
  ///
  /// 副标题展示经纬度 + address，让用户确认"这就是要保存的点"。
  /// 30 字以内（避免 UI 列表被压扁），空字符串视为取消。
  Future<String?> _promptBookmarkName({
    required String defaultName,
    required double latitude,
    required double longitude,
    String? address,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => BookmarkNameDialog(
        defaultName: defaultName,
        latitude: latitude,
        longitude: longitude,
        address: address,
      ),
    );
  }

  /// "历史" 按钮：push BookmarksPage，等待返回的 BookmarkResult。
  /// go → moveCamera 跳图；run → 跳图 + 应用到系统。
  Future<void> _openBookmarksList() async {
    final result = await Navigator.of(context).push<BookmarkResult>(
      MaterialPageRoute(
        builder: (_) => BookmarksPage(strategy: _strategy),
      ),
    );
    if (result == null || !mounted) return;
    if (result.action == BookmarkAction.run) {
      await _applyBookmarkLocation(result.bookmark);
    } else {
      await _strategy.moveCamera(
        LocationInfo(
          latitude: result.bookmark.latitude,
          longitude: result.bookmark.longitude,
        ),
      );
    }
  }

  /// 通用"等定位"helper（SDK 回调 + OS 缓存 fallback）。
  ///
  /// 行为契约（被左下角定位按钮 + "显示当前位置"按钮共用）：
  ///  1. mock 期间直接拒绝（避免把 ML 当成真实位置误导用户）；
  ///  2. 没权限 → 主动申请精确位置 → 仍拒绝则 _snack 提示并 return null；
  ///  3. 调 [_readLocationWithFallback] 在 5s 内两路探测（SDK 回调 + OS 缓存），
  ///     谁先到用谁；
  ///  4. 5s 仍未拿到 → 弹具体排查提示 → return null；
  ///  5. 拿到 → 返回 LocationInfo。
  ///
  /// [promptOnMock] 给 mock 拒绝时用，每个按钮文案略有不同。
  ///
  /// ★ 修复：原版本 30s 轮询只读 `_strategy.currentLocation`（高德 SDK 回调），
  /// 但 csp_amap_flutter_map 在 `myLocationEnabled` 开启后不一定主动回调，
  /// 室内首次冷启动需要 30-60s，导致 UI 看着"30 秒拿不到位置"。
  /// 现在 fallback 到 OS 的 lastKnownLocation（瞬时拿到），用户体验立刻变好。
  Future<LocationInfo?> _waitForLocationWithPermission({
    required String promptOnMock,
  }) async {
    if (_mock.state == MockState.running ||
        _mock.state == MockState.preparing) {
      _snack(promptOnMock);
      return null;
    }

    final perm = await _ensureLocationPermission();
    if (perm == null) return null;

    final me = await _readLocationWithFallback(
      totalTimeout: const Duration(seconds: 5),
    );
    if (me == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '5 秒内未拿到定位。\n'
            '请检查：① 系统设置→位置 是否开启  '
            '② 系统位置开关是否关闭  '
            '③ 室内/地下室 GPS 信号弱',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      return null;
    }
    return me;
  }

  /// 读当前位置：SDK 回调优先 → OS lastKnownLocation 兜底。
  ///
  /// ★ 关键修复：csp_amap_flutter_map 的 `myLocationEnabled: true` 开启后，
  /// SDK 内部 LocationManager **不一定主动回调** `onLocationChanged` 到 dart 层。
  /// 实测室内首次冷启动需要 30-60 秒拿首帧真实 GPS fix，期间 UI 完全拿不到位置。
  ///
  /// 解决：500ms 内 SDK 回调没来，立刻调 [MockService.readRealLocation]
  /// 走 platform channel 直调 native
  /// `LocationManager.getLastKnownLocation(GPS_PROVIDER)` 拿系统缓存，
  /// 瞬时返回（除非系统从未拿到过首帧，这时也是 null）。
  ///
  /// 两个数据源优先级：
  ///  - SDK 回调（_strategy.currentLocation）：高德内部处理过（map-matching / 风控），
  ///    反映用户在该 SDK 视角下的"上报位置"——这是地图 APP 真正关心的；
  ///  - OS lastKnownLocation：原始 GPS fix，未经任何 SDK 处理，反映系统最新读到的
  ///    真实坐标。
  ///
  /// 注意：
  ///  - **mock running 期间不能调** readRealLocation —— test provider 重新占用
  ///    GPS_PROVIDER 命名空间，lastKnownLocation 会被 mock 坐标污染；
  ///  - 调用方应在调用前先检查 `_mock.state != MockState.running`。
  ///    本方法不做这层判断，因为本项目里调用方只有上述两个按钮，都是
  ///    `_waitForLocationWithPermission` 已经过滤过 mock 状态的。
  Future<LocationInfo?> _readLocationWithFallback({
    Duration totalTimeout = const Duration(seconds: 5),
    Duration firstWait = const Duration(milliseconds: 500),
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    // ★ 方案 A：真实定位切 OS 原生「主动定位」优先。
    // requestRealLocation 会主动 requestLocationUpdates 逼系统出一帧真实 fix
    // （8 秒超时兜底缓存），不再依赖高德 SDK 回调（受插件 altitude bug 干扰）
    // 或 getLastKnownLocation 被动缓存（冷启动常为 null）。
    final os = await MockService.requestRealLocation();
    if (os != null) {
      if (!mounted) return null;
      return LocationInfo(latitude: os.lat, longitude: os.lng);
    }

    // 2) OS 主动定位没拿到 → 等 SDK 首次回调（500ms 内拿到就用 SDK 值）
    await Future.delayed(firstWait);
    if (!mounted) return null;
    final sdk = _strategy.currentLocation;
    if (sdk != null) return sdk;

    // 3) SDK 没来 → 再走 OS lastKnownLocation 缓存兜底（最后的被动读）
    final osCached = await MockService.readRealLocation();
    if (osCached != null) {
      if (!mounted) return null;
      return LocationInfo(latitude: osCached.lat, longitude: osCached.lng);
    }

    // 4) 等到 totalTimeout，期间轮询 SDK 回调 + OS 缓存两个 source
    final start = DateTime.now();
    while (DateTime.now().difference(start) < totalTimeout) {
      await Future.delayed(pollInterval);
      if (!mounted) return null;
      final sdk2 = _strategy.currentLocation;
      if (sdk2 != null) return sdk2;
      final os2 = await MockService.readRealLocation();
      if (os2 != null) {
        if (!mounted) return null;
        return LocationInfo(latitude: os2.lat, longitude: os2.lng);
      }
    }
    return null;
  }

  /// 主动确保位置权限已授予（用 locationWhenInUse 精确位置）。
  ///
  /// 返回：
  ///  - PermissionStatus.granted / limited → 可以继续；
  ///  - null → 已拒绝，已 snackbar 提示，调用方应直接 return。
  Future<PermissionStatus?> _ensureLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isGranted || status.isLimited) return status;

    // 第一次请求（系统会弹"精确位置 / 大致位置"对话框）
    status = await Permission.locationWhenInUse.request();
    if (status.isGranted || status.isLimited) return status;

    if (!mounted) return null;
    if (status.isPermanentlyDenied) {
      _snack('定位权限被永久拒绝。请到 系统设置→应用→ShowLocation→权限 中开启"位置"');
    } else {
      _snack('未授予定位权限，无法定位');
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Mock Location 控制
  // ---------------------------------------------------------------------

  Future<void> _applyToSystem() async {
    if (_selected == null) {
      _snack('请先在地图上选个点');
      return;
    }
    await _applyLocation(_selected!);
  }

  /// 把 [target] 作为模拟位置应用到系统（_applyToSystem / Run / 启动自动应用共用）。
  Future<void> _applyLocation(LocationInfo target) async {
    try {
      await _mock.start(target);
      debugPrint('[Run] _applyLocation: mock.start 完成, state=${_mock.state}');
      if (!mounted) return;

      // ★ mock 启动后核心动作：锁地图 + 消去气泡 + 弹出状态对话框。
      // 锁后所有手势关闭、tap/longPress 不再触发，onCameraMove 也不会被调用。
      setState(() {
        _mapInteractive = false;
        _bubbleVisible = false; // ★ 按新流程：应用后消去选点气泡
        // ★ 模拟成功：在 UL 显示红色车标，隐藏蓝色扎标（由 build 里切换）
        _mockCarMarker = MapMarker(
          latitude: target.latitude,
          longitude: target.longitude,
          title: '模拟位置',
          markerColor: Colors.red,
          style: MapMarkerStyle.car,
        );
      });

      // ★ 弹出状态对话框（AL 探针偏差 / 反推进度 / Mock 状态），
      // 内部自监听 controller，实时刷新；stop 时由 _stopMock 关闭。
      _showMockStatusDialog();

      // ★ 通知 AMapStrategy：mock 已启动 → 期间 SDK onLocationChanged 回调的
      // 是 ML（mock 注入点），不能再写入 _strategy.currentLocation，否则
      // stop mock 后用户按"回到当前位置"会跳到海里。
      _strategy.setMockActive(true);

      // 启动后主动让系统回读一次最新 fix，用以：
      //  1. 确认 pushLocation 确实写进去了；
      //  2. 看 isFromMockProvider 是否为 true，预测高德/大众点评是否会降权。
      // 给系统 250ms 分发，避免拿到上一帧缓存。
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      // 原来的诊断弹窗（_showMockVerifyDialog）已删除：
      //  - 气泡 _PickedLocationBubble 已经实时显示 AL 偏差 + Mock 状态，
      //    终端用户能在地图上直接看到"反推是否生效 / 被风控 / 成功"三种状态；
      //  - 弹 dialog 体验差：和"结果还要等 5 秒 + 反推"异步，关闭后又
      //    仿佛"没生效"，反复启动-关闭 dialog 容易"18 次才能关掉"；
      //  - 启动失败/异常改用 _showErrorDialog 兜底。
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      await _runProbe();

      // 反推（阶段3）：如果首轮偏差 > 50m，自动启动 control loop，
      // 把 ML 用 ML_{i} = 2*UL - AL_{i-1} 反向修正，使 SDK 报回的 AL 收敛。
      // calibration 内部会自动更新 progress 通知 UI，气泡会显示进度。
      // 注意：不 await，避免阻塞 _applyToSystem 返回；用户可见"启动完成"。
      if (!mounted) return;
      final initialDev = _probeDeviation.value;
      if (initialDev != null && initialDev > 50.0) {
        // 故意用 unawaited：calibration 是异步 control loop，
        // 主流程不等它结束，让用户先看到 mock 跑起来的反馈。
        unawaited(_mock.runCalibration());
      }
    } on MockLocationException catch (e) {
      debugPrint('[Run] _applyLocation MockLocationException: ${e.message}');
      if (!mounted) return;
      _showErrorDialog(e.message);
    } catch (e) {
      debugPrint('[Run] _applyLocation 未知异常: $e');
      if (!mounted) return;
      _showErrorDialog('启动失败：$e');
    }
  }

  /// 把书签位置设置为选中点 + 跳图 + 应用到系统（Run / 启动自动应用共用）。
  Future<void> _applyBookmarkLocation(LocationBookmark b) async {
    debugPrint('[Run] _applyBookmarkLocation 开始: ${b.displayText}');
    final info = LocationInfo(
      latitude: b.latitude,
      longitude: b.longitude,
      address: b.address,
    );
    setState(() {
      _selected = info;
      _markers
        ..clear()
        ..add(MapMarker(
          latitude: b.latitude,
          longitude: b.longitude,
          title: b.displayText,
          markerColor: Colors.blue,
        ));
      _bubbleVisible = false;
      _probeMarker = null;
      _probeDeviation.value = null;
      _mockCarMarker = null;
    });
    // ★ 关键：moveCamera 是 channel 调用，pop 返回后地图正在重建，
    // 可能挂起（不返回也不抛异常）。若 await 它，会把后面的 apply 一起卡住，
    // 导致"地图跳了但位置没应用到系统"。改成 fire-and-forget，apply 独立推进。
    // ignore: unawaited_futures
    _strategy.moveCamera(info).catchError((_) {
      // 启动自动应用时地图 controller 可能尚未就绪，忽略移动失败。
    });
    await _applyLocation(info);
  }

  /// 主动让高德独立定位 SDK 探一次当前定位，并在地图上叠加红扎标。
  ///
  /// ★ 改用 AMapLocationClient（高德独立定位 SDK）作为 AL 探针：
  ///  - 地图蓝点回调（readLatestLocation）因插件未 setLocationSource 而永不触发；
  ///  - AMapLocationClient 内部做 map-matching / 反 mock / 多源融合，
  ///    回调的坐标 == 其他高德系 APP 显示的位置，正是 AL 探针要观测的对象。
  ///
  /// 如果红扎标 ≈ 蓝扎标（UL），说明 AMap 接受了 mock；
  /// 如果红扎标 ≠ 蓝扎标，说明 AMap 反 mock 走了真实 GPS。
  ///
  /// 重试机制：
  ///   - 每轮调一次 requestAmapLocation（原生 8 秒超时），最多 3 轮，间隔 3 秒；
  ///   - 任一拿到 → 立即渲染返回；
  ///   - 3 轮全空 → 报「疑似风控」。
  Future<void> _runProbe() async {
    const maxRounds = 3;
    const roundGap = Duration(seconds: 3);

    String? lastErrorInfo;
    for (int round = 1; round <= maxRounds; round++) {
      if (!mounted) return;
      final res = await MockService.requestAmapLocation();
      if (!mounted) return;

      if (res.isSuccess) {
        await _renderProbeResult(
          LocationInfo(latitude: res.lat!, longitude: res.lng!),
          locationType: res.locationType,
          isFromMockProvider: res.isFromMockProvider,
        );
        return;
      }
      lastErrorInfo = res.errorInfo;
      if (round < maxRounds) {
        _snack('AMap 定位失败（${res.errorInfo}），第 $round/$maxRounds 轮，'
            '${roundGap.inSeconds}s 后重试…');
        await Future.delayed(roundGap);
      }
    }

    // 3 轮全空 → 判定为异常（疑似风控 / 定位服务不可用）
    if (!mounted) return;
    _snack('AMap 连续 $maxRounds 轮未返回位置'
        '${lastErrorInfo != null ? '（$lastErrorInfo）' : ''}，疑似被风控');
    setState(() {
      _probeMarker = null;
    });
    _probeDeviation.value = null;
  }

  /// 把探针结果渲染到地图红扎标 + 更新偏差显示。
  Future<void> _renderProbeResult(
    LocationInfo probe, {
    int locationType = 0,
    bool isFromMockProvider = false,
  }) async {
    final sel = _selected;
    final dev = sel == null
        ? null
        : _haversineMeters(
            sel.latitude, sel.longitude, probe.latitude, probe.longitude,
          );
    setState(() {
      _probeMarker = MapMarker(
        latitude: probe.latitude,
        longitude: probe.longitude,
        title: 'AMap 探针',
        markerColor: Colors.purple, // 紫色 pin = AL 探针
      );
    });
    _probeDeviation.value = dev;
  }

  /// 用 Haversine 公式计算两点间球面距离（米）。
  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // 地球半径（米）
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;


  Future<void> _stopMock() async {
    await _mock.stop();
    if (!mounted) return;
    // ★ 通知 AMapStrategy：mock 已停止 → 恢复 onLocationChanged 写入
    // _currentLocation。SDK 重新订阅真实 GPS，首帧 fix 到达后
    // _currentLocation 自然被填充，"回到当前位置"即可正常工作。
    //
    // 不再调用 AMapStrategy.clearCurrentLocation() —— 历史原因：
    // 该方法在 stop 时清空 _currentLocation，但 csp_amap_flutter_map
    // stop mock 后 SDK 并不主动重订阅真实 GPS（_firstLocationFired 也
    // 已被置 true 不会再次触发 onFirstLocation），导致 _currentLocation
    // 永久 null，按 FAB 等 30s 也拿不到。现在改用 setMockActive(false)
    // 让 SDK 下一帧真实 fix 自然重写 _currentLocation。
    _strategy.setMockActive(false);
    // ★ 停止模拟：关闭状态对话框（对话框随 mock 生命周期显示/消失）。
    _closeMockStatusDialog();
    // 解锁地图：恢复手势 + tap/longPress 回调。
    // 气泡不主动清 —— 用户一旦滚动地图，onCameraMove 会把它置 false。
    setState(() {
      _mapInteractive = true;
      _mockCarMarker = null; // ★ 停止模拟：消去红色车标，恢复蓝色扎标
      // ★ 停止模拟后清空探针状态，避免下次选点弹出旧气泡内容
      _probeMarker = null;
      _probeDeviation.value = null;
    });
    _snack('已停止模拟');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mock Location 未生效'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// mock 状态对话框是否正在显示（防止重复弹出）。
  bool _mockStatusDialogVisible = false;

  /// 弹出「模拟状态」对话框：AL 探针偏差 + 反推进度 + Mock 状态。
  ///
  /// 设计：
  ///  - 对话框内部用 [ValueListenableBuilder] 自监听 [_mock] 的
  ///    stateListenable / calibrationListenable，实时刷新，无需外部 setState；
  ///  - mock 状态回到 idle（停止）时，对话框内部自动 pop 关闭；
  ///  - 用户手动点关闭 → 标记 [_mockStatusDialogVisible]=false，不影响 mock 运行。
  void _showMockStatusDialog() {
    if (_mockStatusDialogVisible || !mounted) return;
    _mockStatusDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MockStatusDialog(
        mockStateListenable: _mock.stateListenable,
        mockLastError: _mock.lastError?.toString(),
        calibrationListenable: _mock.calibrationListenable,
        probeDeviation: _probeDeviation,
        onDismiss: () {
          _mockStatusDialogVisible = false;
          Navigator.of(ctx).pop();
        },
      ),
    ).then((_) {
      _mockStatusDialogVisible = false;
    });
  }

  /// 关闭状态对话框（由 [_stopMock] 调用）。
  void _closeMockStatusDialog() {
    if (!_mockStatusDialogVisible) return;
    _mockStatusDialogVisible = false;
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  // (旧 _stateText/_stateColor 已迁移到 _PickedLocationBubble 内部，
//  合并气泡后不再需要顶层方法)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地图选点')),
      body: _mapReady
          ? Stack(
              children: [
                _strategy.buildMap(
                  initialCamera: _initCamera,
                  markers: [
                    // 绿色真实位置车标：定位成功后常驻
                    if (_realMarker != null) _realMarker!,
                    // 模拟中显示红色车标（UL），否则显示蓝色扎标（UL）
                    if (_mockCarMarker != null)
                      _mockCarMarker!
                    else
                      ..._markers,
                    // 紫色 AMap 探针（AL 候选）
                    if (_probeMarker != null) _probeMarker!,
                  ],
                  // mock 锁定时 tap / longPress 都不传 → 整个回调关闭
                  onMapTap: _mapInteractive ? _onMapTap : null,
                  onMapLongPress: _mapInteractive ? _onMapTap : null,
                  // 每次启动后等 AMap SDK 主动给的首帧真实 GPS fix，
                  // 拿到就 moveCamera 跳过去 —— 不读任何缓存。
                  onFirstLocation: _strategy.moveCamera,
                  // ★ 地图创建完成后主动用系统定位跳转到当前位置。
                  // 不再依赖 SDK 的 onFirstLocation 蓝点回调（插件未 setLocationSource，
                  // 蓝点回调永不触发，导致启动后地图一直停在天安门）。
                  onMapCreated: _onMapCreated,
                  // 滚动地图时立即隐藏"经纬度大气泡"
                  onCameraMove: _onCameraMove,
                  // ★ 新增：地图可交互性受 mock 状态控制
                  mapInteractive: _mapInteractive,
                ),
                // 顶部：关键字搜索框 + 输入联想下拉
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        searching: _searching,
                        onSearch: _onSearch,
                        onChanged: _onSearchTextChanged,
                      ),
                      if (_suggestions.isNotEmpty)
                        _SuggestionList(
                          suggestions: _suggestions,
                          onSelect: _applySearchResult,
                        ),
                    ],
                  ),
                ),
                // 右下角：回到当前位置按钮
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: FloatingActionButton(
                    heroTag: 'locate',
                    tooltip: '回到当前位置',
                    onPressed: _backToMyLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                // 屏幕中央偏上：长按地图弹出的"已选位置"气泡。
                // 内容仅含：displayText + 经纬度 + address + 关闭按钮。
                // AL 探针偏差 / 反推进度 / Mock 状态已迁移到「模拟状态」对话框，
                // 由 _applyToSystem 成功后弹出、_stopMock 时关闭。
                // 可见性由 _bubbleVisible 控制：
                //  - 长按地图 → 显示；
                //  - 滚动地图 → 隐藏（见 _onCameraMove）；
                //  - 再次长按 → 重新显示；
                //  - mock 启动后强制隐藏（信息转移到对话框）。
                if (_bubbleVisible && _selected != null)
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0, -0.25),
                      child: _PickedLocationBubble(
                        latitude: _selected!.latitude,
                        longitude: _selected!.longitude,
                        displayText: _selected!.displayText,
                        address: _selected!.address,
                        onDismiss: () {
                          setState(() => _bubbleVisible = false);
                        },
                      ),
                    ),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mock 启动 / 停止按钮（根据状态切换）
              ValueListenableBuilder<MockState>(
                valueListenable: _mock.stateListenable,
                builder: (_, state, __) {
                  final isRunning =
                      state == MockState.running || state == MockState.preparing;
                  return SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: isRunning
                        ? ElevatedButton.icon(
                            onPressed: _stopMock,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text(
                              '停止模拟',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _applyToSystem,
                            icon: const Icon(Icons.publish),
                            label: const Text(
                              '应用到系统',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                  );
                },
              ),
              const SizedBox(height: 8),
              // 第二行：保存（左）+ 历史（右）。
// "保存"按钮置灰条件：_selected == null（用户从未选过点）。与 mock 状态无关，
// 因为方案 A 只存 UL（用户选点），mock 期间也能保存。
// 选中点后 _onMapTap 触发 setState → build 重新计算 _selected → 按钮自动变可点。
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _selected == null
                            ? null
                            : _bookmarkSelectedLocation,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text(
                          '保存',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _openBookmarksList,
                        icon: const Icon(Icons.history),
                        label: const Text(
                          '历史',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // "重新探测 AMap" 按钮已经合并进 [_PickedLocationBubble] 内部
              // （见气泡底部 "重新探测 AMap" 文本按钮），这里不再重复。
              // "显示当前位置" 按钮（保留原功能）
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _showCurrentAddress,
                  icon: const Icon(Icons.place_outlined),
                  label: const Text(
                    '显示当前位置',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



/// 顶部关键字搜索框：TextField + 搜索按钮。
///
/// 纯 Flutter UI，与地图 SDK 无关。输入关键字后点搜索（或键盘回车）
/// 触发 [onSearch]，由 [_HomePageState._onSearch] 调 POI 搜索并处理结果。
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onSearch,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.search, size: 20, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: onSearch,
                decoration: const InputDecoration(
                  hintText: '搜索地点（如：天安门、北京大学）',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            // 搜索按钮：搜索中显示 loading，否则显示"搜索"
            SizedBox(
              height: 36,
              child: TextButton(
                onPressed: searching ? null : () => onSearch(controller.text),
                child: searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('搜索'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索框下方的输入联想下拉列表。
///
/// 展示 [_strategy.inputTips] 返回的候选 POI（名称 + 地址），
/// 用户点选后由 [_HomePageState._applySearchResult] 选中并跳图。
class _SuggestionList extends StatelessWidget {
  final List<LocationInfo> suggestions;
  final ValueChanged<LocationInfo> onSelect;

  const _SuggestionList({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = suggestions[i];
            final subtitle = (r.address != null && r.address!.isNotEmpty)
                ? r.address!
                : (r.district != null && r.district!.isNotEmpty
                    ? r.district!
                    : null);
            return ListTile(
              dense: true,
              leading: const Icon(Icons.place, size: 20, color: Colors.blue),
              title: Text(
                r.displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => onSelect(r),
            );
          },
        ),
      ),
    );
  }
}

/// 长按地图后弹出的"已选位置"气泡。
///
/// 之所以不用 AMap SDK 自带的 InfoWindow：
///  - 它由 SDK 内部 Flutter widget 实现，相机移动（地图滚动）不会自动隐藏；
///  - 原 bug 即来自这里：长按 → 气泡 → 滚动地图 → 气泡不消失。
///
/// 本 widget 在 [HomePage] 的 Stack 上叠一个固定位置（屏幕中央偏上）的卡片，
/// 只承载"已选位置"信息（displayText + 经纬度 + address + 关闭按钮）：
///  - 长按 / 点击地图：[HomePage] 把 [_bubbleVisible] 置 true → 显示；
///  - 滚动地图：[HomePage._onCameraMove] 立即置 false → 立刻消失；
///  - mock 启动后 [_bubbleVisible] 置 false → 隐藏（信息迁移到状态对话框）。
///
/// 注意：AL 探针偏差 / 反推进度 / Mock 状态原本也在这里，现已迁移到
/// [_MockStatusDialog]（apply → 弹框，stop → 关框）。
class _PickedLocationBubble extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String displayText;
  final String? address;
  final VoidCallback onDismiss;

  const _PickedLocationBubble({
    required this.latitude,
    required this.longitude,
    required this.displayText,
    required this.address,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              blurRadius: 8,
              color: Colors.black26,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1) Header：已选位置 + 关闭按钮
              Row(
                children: [
                  const Icon(Icons.place, size: 18, color: Colors.blue),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '已选位置',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onDismiss,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 18, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              // 2) displayText 大字
              Text(
                displayText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              // 3) 经纬度
              Text(
                '纬度：${latitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
              Text(
                '经度：${longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
              // 4) address
              if (address != null && address!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  address!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「模拟状态」对话框：AL 探针偏差 + 反推进度 + Mock 状态。
///
/// 替代原先气泡内的三块状态信息。弹出时机：
///  - [_HomePageState._applyToSystem] mock 启动成功后 → 弹出；
///  - [_HomePageState._stopMock] → 关闭；对话框内部监听 mock 状态回到 idle
///    时也会自动关闭（双保险）。
///
/// 内部用 [ValueListenableBuilder] 自监听 [_mock] 的 stateListenable /
/// calibrationListenable / probeDeviation，状态实时刷新，无需外部 setState。
class _MockStatusDialog extends StatefulWidget {
  final ValueListenable<MockState> mockStateListenable;
  final String? mockLastError;
  final ValueListenable<CalibrationProgress>? calibrationListenable;
  final ValueListenable<double?> probeDeviation;
  final VoidCallback onDismiss;

  const _MockStatusDialog({
    required this.mockStateListenable,
    required this.mockLastError,
    required this.calibrationListenable,
    required this.probeDeviation,
    required this.onDismiss,
  });

  @override
  State<_MockStatusDialog> createState() => _MockStatusDialogState();
}

class _MockStatusDialogState extends State<_MockStatusDialog> {
  @override
  void initState() {
    super.initState();
    // 监听 mock 状态：回到 idle（停止模拟）时自动关闭对话框。
    widget.mockStateListenable.addListener(_onMockStateChanged);
  }

  @override
  void dispose() {
    widget.mockStateListenable.removeListener(_onMockStateChanged);
    super.dispose();
  }

  void _onMockStateChanged() {
    if (!mounted) return;
    if (widget.mockStateListenable.value == MockState.idle) {
      widget.onDismiss();
    }
  }

  static String _stateText(MockState s, String? lastError) {
    switch (s) {
      case MockState.idle:
        return '未启用';
      case MockState.preparing:
        return '准备中…';
      case MockState.running:
        return '运行中（模拟位置已生效）';
      case MockState.error:
        return '出错：${lastError ?? "未知"}';
    }
  }

  static Color _stateColor(MockState s) {
    switch (s) {
      case MockState.idle:
        return Colors.grey;
      case MockState.preparing:
        return Colors.orange;
      case MockState.running:
        return Colors.green;
      case MockState.error:
        return Colors.red;
    }
  }

  /// 对话框标题：
  ///  - 默认「准备中」；
  ///  - Mock 已生效（running）且动态修正（推理）完成后 →「已就绪」。
  String _titleText() {
    final mock = widget.mockStateListenable.value;
    if (mock != MockState.running) return '准备中';

    final cal = widget.calibrationListenable?.value;
    if (cal != null) {
      if (cal.state == CalibrationState.success) return '已就绪';
      // 推理未触发（偏差 ≤ 50m）：视为无需修正、已完成。
      if (cal.state == CalibrationState.idle) {
        final dev = widget.probeDeviation.value;
        if (dev != null && dev <= 50.0) return '已就绪';
      }
      return '准备中';
    }
    return '已就绪';
  }

  static String _fmtMeters(double? v) {
    if (v == null || v.isNaN) return '—';
    return v.toStringAsFixed(0);
  }

  Widget _caliRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// AL 探针偏差行的颜色：<50m 绿、<300m 橙、其余红。
  static Color _deviationColor(double dev) {
    if (dev < 50) return Colors.green.shade700;
    if (dev < 300) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                widget.mockStateListenable,
                if (widget.calibrationListenable != null)
                  widget.calibrationListenable!,
                widget.probeDeviation,
              ]),
              builder: (_, __) => Text(
                _titleText(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: widget.onDismiss,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 20, color: Colors.grey),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1) 模拟状态
            ValueListenableBuilder<MockState>(
              valueListenable: widget.mockStateListenable,
              builder: (_, state, __) {
                return _caliRow(
                  icon: Icons.circle,
                  color: _stateColor(state),
                  text: '模拟状态：${_stateText(state, widget.mockLastError)}',
                );
              },
            ),
            const Divider(height: 16, thickness: 0.5),
            // 2) 位置校准
            ValueListenableBuilder<double?>(
              valueListenable: widget.probeDeviation,
              builder: (_, dev, __) {
                if (dev == null) {
                  return _caliRow(
                    icon: Icons.gps_fixed,
                    color: Colors.grey,
                    text: '位置校准：探测中…',
                  );
                }
                final color = _deviationColor(dev);
                return _caliRow(
                  icon: Icons.gps_fixed,
                  color: color,
                  text: '位置校准：${dev.toStringAsFixed(0)} m',
                );
              },
            ),
            const Divider(height: 16, thickness: 0.5),
            // 3) 推理状态
            if (widget.calibrationListenable != null)
              ValueListenableBuilder<CalibrationProgress>(
                valueListenable: widget.calibrationListenable!,
                builder: (_, p, __) {
                  switch (p.state) {
                    case CalibrationState.idle:
                      return _caliRow(
                        icon: Icons.info_outline,
                        color: Colors.grey,
                        text: '未触发推理（偏差 ≤ 50m 或等待探测中）',
                      );
                    case CalibrationState.running:
                      return _caliRow(
                        icon: Icons.tune,
                        color: Colors.orange.shade700,
                        text: '推理校准中 ${p.iteration}/${p.maxIterations}… '
                            '偏差 ${_fmtMeters(p.currentDeviation)} m',
                      );
                    case CalibrationState.success:
                      return _caliRow(
                        icon: Icons.check_circle,
                        color: Colors.green.shade700,
                        text: '推理完成，残余偏差 '
                            '${_fmtMeters(p.currentDeviation)} m '
                            '（推理前 ${_fmtMeters(p.initialDeviation)} m）',
                      );
                    case CalibrationState.failed:
                      return _caliRow(
                        icon: Icons.error_outline,
                        color: Colors.red.shade700,
                        text: '推理未完成：${p.lastError ?? "未知原因"}',
                      );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// "保存选中位置"对话框。
///
/// StatefulWidget 形态：controller 由 [_BookmarkNameDialogState] 持有，
/// dispose 与 widget lifecycle 完全同步，避免早期 `Future<String?> _promptBookmarkName(...)`
/// 在 builder 外创建 controller + 手动 dispose 时触发的
/// `InheritedElement._dependents.isEmpty` framework 断言。
///
/// 注：class 名为公开 `BookmarkNameDialog`（而非带 `_` 前缀的私有名），
/// 是因为 Dart 在实例方法内引用同名私有类时偶有解析歧义 —— 改公开后
/// `builder: (_) => BookmarkNameDialog(...)` 可以正确解析为构造函数。
class BookmarkNameDialog extends StatefulWidget {
  final String defaultName;
  final double latitude;
  final double longitude;
  final String? address;

  const BookmarkNameDialog({
    super.key,
    required this.defaultName,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  @override
  State<BookmarkNameDialog> createState() => _BookmarkNameDialogState();
}

class _BookmarkNameDialogState extends State<BookmarkNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latText = '纬度：${widget.latitude.toStringAsFixed(6)}';
    final lngText = '经度：${widget.longitude.toStringAsFixed(6)}';
    final addr = widget.address;
    return AlertDialog(
      title: const Text('保存选中位置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(latText, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          Text(lngText, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          if (addr != null && addr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                addr,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLength: 30,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '给这个位置起个名字',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
