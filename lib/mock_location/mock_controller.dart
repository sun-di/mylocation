import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/location_info.dart';
import 'mock_service.dart';

/// 模拟状态机。
///
/// 用法：UI 通过 [stateListenable] 监听当前状态，
/// 业务通过 [start]/[stop] 控制生命周期。
enum MockState {
  /// 未启动。
  idle,

  /// 正在准备（注册 Provider / 跳转设置页）。
  preparing,

  /// 正在周期性向系统推送位置。
  running,

  /// 出错（具体原因见 [MockController.lastError]）。
  error,
}

/// 反推校准状态。
///
/// 状态机：
///   idle    → 用户尚未触发反推
///   running → control loop 正在迭代 ML，逼近 UL
///   success → 偏差小于收敛阈值（默认 50m）
///   failed  → 达到最大迭代次数 / 风控拒掉 / 偏差连续两轮无变化
enum CalibrationState { idle, running, success, failed }

/// 反推校准进度对象。
///
/// 由 [MockController.calibrationListenable] 暴露给 UI，UI 据此渲染
/// 「校准中 1/3...」「校准完成，残余偏差 12m」「未校准（风控）」。
class CalibrationProgress {
  final CalibrationState state;

  /// 当前迭代轮次（1-based），0 表示尚未开始。
  final int iteration;

  /// 上限（默认 3 轮）。
  final int maxIterations;

  /// 第一次 push = UL 后的 AL vs UL 偏差（米）—— 作为「反推前基准」。
  final double? initialDeviation;

  /// 最新一轮观测到的偏差（米）。
  final double? currentDeviation;

  /// 上一轮的偏差（米）。用于检测连续两轮无变化 → 风控。
  final double? previousDeviation;

  /// 最新一轮观测到的 AL 坐标。
  final LocationInfo? alProbe;

  /// 失败原因（仅 [CalibrationState.failed] 时有值）。
  final String? lastError;

  const CalibrationProgress({
    required this.state,
    required this.iteration,
    required this.maxIterations,
    this.initialDeviation,
    this.currentDeviation,
    this.previousDeviation,
    this.alProbe,
    this.lastError,
  });

  factory CalibrationProgress.idle({int max = 4}) => CalibrationProgress(
        state: CalibrationState.idle,
        iteration: 0,
        maxIterations: max,
      );

  CalibrationProgress copyWith({
    CalibrationState? state,
    int? iteration,
    int? maxIterations,
    double? initialDeviation,
    double? currentDeviation,
    double? previousDeviation,
    LocationInfo? alProbe,
    String? lastError,
    bool clearLastError = false,
  }) {
    return CalibrationProgress(
      state: state ?? this.state,
      iteration: iteration ?? this.iteration,
      maxIterations: maxIterations ?? this.maxIterations,
      initialDeviation: initialDeviation ?? this.initialDeviation,
      currentDeviation: currentDeviation ?? this.currentDeviation,
      previousDeviation: previousDeviation ?? this.previousDeviation,
      alProbe: alProbe ?? this.alProbe,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  /// 残余偏差（用于 UI 文本展示）。没有时返回 null。
  double? get residual => currentDeviation;
}

/// 注入给 [MockController] 的"读 AMap 反 mock 后的位置"回调。
///
/// 用 typedef 而不是直接传 [MapStrategy] 是为了解耦：
/// MockController 只关心"等几秒后给我一个 SDK 实际回调的 AL"，
/// 不需要知道是高德 / 百度 / 腾讯哪个 SDK。
typedef ReadAlProbe = Future<LocationInfo?> Function({
  Duration waitTimeout,
});

/// 把"持续向系统推送位置"封装成一个有限状态机。
///
/// 关键设计：
///  1. [start] 前会自动调用 [MockService.isMockEnabled]；
///     若未授权，会跳开发者选项引导用户授权（一次性）；
///  2. [start] 完成后由原生前台服务每 500ms 推送一次（Dart 侧不再持有 Timer）；
///  3. 任何原生调用抛错均转为 error 状态 + 自动 stop；
///  4. UI 必须监听 [stateListenable] 展示运行状态；
///  5. UI 销毁时必须调用 [dispose] 释放监听器；
///  6. 阶段2-方案A：默认开启 NETWORK_PROVIDER 镜像推送，
///     应对高德/腾讯类 APP 的"双 Provider 校验回退"。
///  7. 阶段2-方案A+：push 频率提升到 500ms，启动时连推 5 次"爆发模式"，
///     用密度压制真实 GPS 输出。
///  8. 阶段3-反推：在 [start] 完成后调用 [runCalibration]，自动迭代 ML
///     使其逼近 UL，让 SDK 报回的 AL 也逼近 UL（收敛到 <50m）。
class MockController {
  // ---------------------------------------------------------------------
  // 反推校准参数：4 轮 / 间隔 6s / 收敛 50m
  // ---------------------------------------------------------------------
  static const int _calibrationMaxIterations = 4;
  static const Duration _calibrationIterGap = Duration(seconds: 6);
  static const double _calibrationConvergeMeters = 50.0;
  /// "连续两轮偏差变化 < 1m" 视为风控/卡死，强制退出。
  static const double _calibrationStagnantDelta = 1.0;
  /// A方案：readAlProbe 单次等待时间（延长到 5s，给 SDK 多点时间）。
  static const Duration _readAlProbeTimeout = Duration(seconds: 5);
  /// A方案：连续多少次 readAlProbe 返回 null 才算真风控。
  /// 第 1 轮总是宽容（视为冷启动延迟），从第 2 轮起连续 2 次 null 退出。
  static const int _consecutiveAlMissedMax = 2;
  /// A方案：单次反推 ML 距离 UL 的最大步长（米）。
  /// 防止 "UL 在北京、AL 在沈阳" 时一步反推到海里（高德 map-matching 拒掉）。
  /// 10km 已经是城市级移动，合理上限。
  static const double _maxReverseStepMeters = 10000.0;

  final ValueNotifier<MockState> _state =
      ValueNotifier<MockState>(MockState.idle);
  ValueListenable<MockState> get stateListenable => _state;
  MockState get state => _state.value;

  final ValueNotifier<CalibrationProgress> _calibration =
      ValueNotifier<CalibrationProgress>(
    CalibrationProgress.idle(max: _calibrationMaxIterations),
  );
  ValueListenable<CalibrationProgress> get calibrationListenable => _calibration;
  CalibrationProgress get calibration => _calibration.value;

  /// 用户原始选点（UL）—— 不动，作为反推基准。
  LocationInfo? _targetUL;
  /// 当前实际 push 的点（ML）—— calibration 会迭代调整它。
  LocationInfo? _currentML;
  Object? _lastError;

  /// 注入的"读 SDK 反 mock 后位置"回调（来自 HomePage 持有 AMapStrategy）。
  /// 在 [runCalibration] 中使用。
  final ReadAlProbe? _readAlProbe;

  /// 反推协程取消标志（外部调用 [stop]/[dispose]/新一次 [runCalibration] 时设 true）。
  bool _calibrationCancel = false;

  MockController({ReadAlProbe? readAlProbe}) : _readAlProbe = readAlProbe;

  /// 最近一次错误对象（UI 可选展示）。
  Object? get lastError => _lastError;

  /// 当前是否在运行中（含 preparing 转 running 的过渡）。
  bool get isRunning => _state.value == MockState.running;

  /// 当前正在向系统推送的目标位置（ML），null 表示未启动。
  /// 这是 calibration 调整后的点，不是用户原始 UL —— 用 [userTarget] 拿 UL。
  LocationInfo? get target => _currentML;

  /// 用户原始选点（UL），不受 calibration 影响。
  LocationInfo? get userTarget => _targetUL;

  /// 开始向系统位置服务推送 [target]。
  ///
  /// 流程：
  ///  1. 已在 running → 先 stop；
  ///  2. 检查权限，未授权则跳转开发者选项并抛 [MockLocationException]；
  ///  3. 注册 Test Provider；
  ///  4. 立即推送一次（避免其他 APP 头一秒没 fix）；
  ///  5. 由原生前台服务启动 500ms 推送循环（Dart 侧不持有 Timer）。
  ///
  /// 注意：本方法**不会**自动启动反推 —— 调用方需在 SDK 拿到首帧 AL
  /// 之后调用 [runCalibration]。这让调用方控制节奏（先看首轮 AL，
  /// 再决定要不要迭代；避免对每一次启动都消耗 3 轮）。
  Future<void> start(LocationInfo target) async {
    if (_state.value == MockState.running) {
      await stop();
    }
    _targetUL = target;
    _currentML = target;
    _lastError = null;
    // 重置 calibration 状态：新的 mock 周期，重新评估。
    _calibration.value = CalibrationProgress.idle(
      max: _calibrationMaxIterations,
    );

    // 1. 权限：是否被用户选为"模拟位置应用"
    final enabled = await MockService.isMockEnabled();
    if (!enabled) {
      _state.value = MockState.preparing;
      await MockService.openDevOptions();
      _state.value = MockState.idle;
      throw MockLocationException(
        '请在"开发者选项 → 选择模拟位置应用"中选中 "showlocation"，'
        '然后回到本界面再次点击"应用到系统"',
      );
    }

    // 2. 启动前台服务（方案 A：推送循环在原生前台服务里跑，退后台不被冻结）
    //    前台服务内部会：startForeground + 注册 Test Provider + 500ms 推送循环。
    _state.value = MockState.preparing;
    try {
      await MockService.startMock(
        lat: target.latitude,
        lng: target.longitude,
        mirrorToNetwork: true,
      );
    } catch (e) {
      _lastError = e;
      _state.value = MockState.error;
      rethrow;
    }

    _state.value = MockState.running;
  }

  /// 启动反推校准 control loop。
  ///
  /// 流程：
  ///  1. 记录"反推前"偏差（已经观测到的 AL vs UL）；
  ///  2. 第 i 轮（i >= 2）用 ML_{i} = 2*UL - AL_{i-1} 更新 ML；
  ///  3. 等 4s 让 SDK 重新分发 + 回调；
  ///  4. 读最新 AL，计算偏差：
  ///      - < 50m → success；
  ///      - 连续两轮偏差变化 < 1m → 风控/卡死 → failed；
  ///      - 达到最大轮次 → failed；
  ///  5. 每一步通过 [calibrationListenable] 通知 UI。
  ///
  /// 调用条件：
  ///  - 必须在 [start] 之后调用；
  ///  - 同一时间只允许一个反推协程，重入会直接 return。
  ///  - 如果构造时没注入 [ReadAlProbe]，本方法立即 return。
  Future<void> runCalibration() async {
    if (_state.value != MockState.running) return;
    final ul = _targetUL;
    final readProbe = _readAlProbe;
    if (ul == null || readProbe == null) return;
    if (_calibration.value.state == CalibrationState.running) return;

    _calibrationCancel = false;
    _calibration.value = const CalibrationProgress(
      state: CalibrationState.running,
      iteration: 0,
      maxIterations: _calibrationMaxIterations,
    );

    LocationInfo? lastAl;
    double? prevDist;
    /// A方案：连续 readAlProbe 返回 null 的次数。
    /// 第 1 轮 null = 冷启动延迟，从第 2 轮起连续 2 次才判风控。
    int consecutiveAlMissed = 0;

    for (int i = 1; i <= _calibrationMaxIterations; i++) {
      if (_calibrationCancel) return;

      // 1) 第 i >= 2 轮：用上一轮 AL 反推 ML
      if (i >= 2 && lastAl != null) {
        // ML_{i} = 2*UL - AL_{i-1}
        final rawML = LocationInfo(
          latitude: 2 * ul.latitude - lastAl.latitude,
          longitude: 2 * ul.longitude - lastAl.longitude,
        );
        // A方案：限幅到 UL ± _maxReverseStepMeters，防止一步反推到海里
        // （高德 map-matching 会过滤"距离上一帧跨越过远"的 fix，导致 callback 中断）
        _currentML = _clampStep(rawML, ul, _maxReverseStepMeters);
        // 同步到前台服务：服务线程每 500ms 按 targetLat/targetLng 推送，
        // 不更新的话高德仍会收到上一轮旧坐标，反推无效。
        try {
          await MockService.updateMockTarget(
            lat: _currentML!.latitude,
            lng: _currentML!.longitude,
          );
        } catch (_) { /* 忽略：下一轮再试 */ }
      }

      // 2) 给 SDK 时间重新分发 + 回调
      await Future.delayed(_calibrationIterGap);
      if (_calibrationCancel) return;

      // 3) 探测 SDK 当前回调的最新位置（AL）
      final al = await readProbe(waitTimeout: _readAlProbeTimeout);
      if (_calibrationCancel) return;
      if (al == null) {
        consecutiveAlMissed++;
        // A方案：第 1 轮 null 视为冷启动延迟，不立即判失败
        if (i == 1) {
          _calibration.value = _calibration.value.copyWith(
            iteration: i,
            previousDeviation: prevDist,
            lastError: 'SDK 第 1 轮未响应（冷启动），继续等待',
          );
          continue;
        }
        // 第 2+ 轮连续 null 达到阈值才判风控
        if (consecutiveAlMissed >= _consecutiveAlMissedMax) {
          _calibration.value = _calibration.value.copyWith(
            state: CalibrationState.failed,
            iteration: i,
            previousDeviation: prevDist,
            lastError:
                'SDK 连续 $_consecutiveAlMissedMax 轮未返回位置（疑似风控）',
          );
          return;
        }
        // 单次 null，下一轮继续
        _calibration.value = _calibration.value.copyWith(
          iteration: i,
          previousDeviation: prevDist,
          lastError: 'SDK 第 $i 轮未返回位置，继续等待',
        );
        continue;
      }
      consecutiveAlMissed = 0;
      lastAl = al;

      // 4) 算偏差
      final dist = _haversineMeters(
        ul.latitude, ul.longitude, al.latitude, al.longitude,
      );

      // 5) 风控检测：连续两轮偏差变化 < _calibrationStagnantDelta
      if (prevDist != null && (dist - prevDist).abs() < _calibrationStagnantDelta) {
        _calibration.value = _calibration.value.copyWith(
          state: CalibrationState.failed,
          iteration: i,
          previousDeviation: prevDist,
          currentDeviation: dist,
          alProbe: al,
          lastError: 'SDK 连续两轮无变化（疑似风控）',
        );
        return;
      }

      // 6) 推送进度
      _calibration.value = _calibration.value.copyWith(
        iteration: i,
        initialDeviation: _calibration.value.initialDeviation ?? dist,
        previousDeviation: prevDist,
        currentDeviation: dist,
        alProbe: al,
        clearLastError: true,
      );

      // 7) 收敛判停
      if (dist < _calibrationConvergeMeters) {
        _calibration.value = _calibration.value.copyWith(
          state: CalibrationState.success,
        );
        return;
      }

      prevDist = dist;
    }

    // 达到最大轮次仍未收敛
    final last = _calibration.value;
    _calibration.value = last.copyWith(
      state: CalibrationState.failed,
      lastError: '已达最大迭代次数 $_calibrationMaxIterations，未收敛',
    );
  }

  /// 取消当前反推（如果有），但不停止 mock。
  /// 用于 stop 前的清理，或 UI 主动放弃反推。
  void cancelCalibration() {
    _calibrationCancel = true;
    if (_calibration.value.state == CalibrationState.running) {
      _calibration.value = _calibration.value.copyWith(
        state: CalibrationState.idle,
      );
    }
  }

  /// 停止推送并清理 Test Provider。
  ///
  /// 不再做"读真实坐标 → 写盘"缓存：每次启动都直接等 SDK 首帧实时定位。
  Future<void> stop() async {
    cancelCalibration();
    try {
      await MockService.stopMock();
    } catch (_) { /* 忽略：可能服务本就不在运行 */ }
    _targetUL = null;
    _currentML = null;
    _state.value = MockState.idle;
    // ★ 无条件重置校准进度，避免下次启动/选点显示旧的反推结果
    _calibration.value = CalibrationProgress.idle(
      max: _calibrationMaxIterations,
    );
  }

  /// 仅释放资源，不发 stopProvider。
  /// 适用于 Activity 销毁、UI 重建等场景。
  ///
  /// 注：之前"APP 切后台兜底 stop"的能力由 [pauseMockForBackground] 提供，
  /// 现在 HomePage 不再自动调用它（保留方法备用），本方法也不依赖别处兜底。
  void dispose() {
    _calibrationCancel = true;
    _targetUL = null;
    _currentML = null;
    _state.dispose();
    _calibration.dispose();
  }

  /// 历史方法：原本由 HomePage 在 AppLifecycleState.paused 时调用，强制 stop mock。
  ///
  /// 当前状态：**保留但不再自动调用**。
  /// 变更动机：用户在 mock 期间切到其他 APP 又切回来时，期望 mock 状态保留
  /// （按钮仍显示"停止模拟"，地图保持锁定）。该方法的语义不再适用。
  ///
  /// 若后续需要"系统级解除 mock"的兜底（例如被 OS lowmemory kill 前确认），
  /// 可重新由调用方主动触发本方法。
  ///
  /// 调用条件：仅当当前状态为 preparing / running 时执行；idle / error 时跳过。
  Future<void> pauseMockForBackground() async {
    if (_state.value != MockState.preparing && _state.value != MockState.running) {
      return;
    }
    await stop();
  }

  // -----------------------------------------------------------------------
  // 内部
  // -----------------------------------------------------------------------

  /// 球面空间步长限幅：把 [raw] 沿 (ul → raw) 方向截断到距离 [ul] 不超过 [maxMeters]。
  ///
  /// A方案：用 ML_{i} = 2*UL - AL 反推时，若 AL 距离 UL 太远（比如 UL=北京，AL=沈阳），
  /// 反推后的 ML 会一步跳到海里、跨过几百公里的"不可能跳跃"，
  /// 高德 map-matching 会把它判为 invalid fix，callback 静默中断。
  /// 解决方法：把 raw 沿 (ul → raw) 单位向量缩放到 maxMeters 距离内。
  ///
  /// 返回值：限幅后的 LocationInfo。
  static LocationInfo _clampStep(
    LocationInfo raw,
    LocationInfo ul,
    double maxMeters,
  ) {
    final dist = _haversineMeters(
      ul.latitude, ul.longitude, raw.latitude, raw.longitude,
    );
    if (dist <= maxMeters) return raw;
    final ratio = maxMeters / dist;
    return LocationInfo(
      latitude: ul.latitude + (raw.latitude - ul.latitude) * ratio,
      longitude: ul.longitude + (raw.longitude - ul.longitude) * ratio,
    );
  }

  /// Haversine 球面距离（米）。
  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
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
}