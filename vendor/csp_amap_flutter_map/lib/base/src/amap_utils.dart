part of '../csp_amap_flutter_base.dart';

class AMapUtil {
  static final AMapUtil _instance = AMapUtil._();
  static double _devicePixelRatio = 0;
  static void init(BuildContext context) {
    _devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  AMapUtil._();

  factory AMapUtil() {
    return _instance;
  }

  /// 获取当前设备的屏幕像素比
  static double get devicePixelRatio => _devicePixelRatio;
}
