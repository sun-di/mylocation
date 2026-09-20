# csp_amap_flutter_map

[![pub package](https://img.shields.io/badge/pub-v1.1.0-blue)](https://gitee.com/chenshipeng0914/csp_amap_flutter_map)
[![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios%20%7C%20harmonyos-lightgrey)](https://gitee.com/chenshipeng0914/csp_amap_flutter_map)
[![license](https://img.shields.io/badge/license-Apache%202.0-green)](https://gitee.com/chenshipeng0914/csp_amap_flutter_map/blob/develop/LICENSE)

基于[高德开放平台地图SDK](https://lbs.amap.com/api/)的 Flutter 插件，支持 **Android**、**iOS**、**HarmonyOS** 三大平台。

## ✨ 特性

- 🌍 **三平台支持**: Android、iOS、HarmonyOS 全平台覆盖
- 🗺️ **丰富的地图功能**: 多种地图类型、标记、路径绘制、定位等
- 📦 **内置基础库**: 定位、POI 搜索、API Key 管理与隐私合规能力随包提供，无需额外依赖
- 🎨 **自定义样式**: 支持自定义地图样式和标记图标
- 📱 **响应式设计**: 支持各种屏幕尺寸和分辨率
- 🔧 **易于集成**: 简单的 API 设计，快速集成到项目中
- 📋 **合规处理**: 内置隐私合规处理方案

## 📋 目录

- [准备工作](#准备工作)
- [安装使用](#安装使用)
- [快速开始](#快速开始)
- [API 文档](#api-文档)
- [示例代码](#示例代码)
- [平台配置](#平台配置)
- [常见问题](#常见问题)
- [更新日志](#更新日志)
- [贡献指南](#贡献指南)

## 🚀 准备工作

### 1. 申请 API Key

登录[高德开放平台官网](https://lbs.amap.com/)申请 API Key：

- **Android**: [获取 Android Key](https://lbs.amap.com/api/poi-sdk-android/develop/create-project/get-key/?sug_index=2)
- **iOS**: [获取 iOS Key](https://lbs.amap.com/api/poi-sdk-ios/develop/create-project/get-key/?sug_index=1)
- **HarmonyOS**: [获取 HarmonyOS Key](https://lbs.amap.com/api/harmonyosnext-map3d-sdk/guide/get-key)

### 2. 引入高德地图 SDK

- **Android**: [Android Studio 配置工程](https://lbs.amap.com/api/android-sdk/guide/create-project/android-studio-create-project)
- **iOS**: [iOS 安装地图 SDK](https://lbs.amap.com/api/ios-sdk/guide/create-project/cocoapods)
- **HarmonyOS**: [HarmonyOS 配置](https://lbs.amap.com/api/harmonyosnext-map3d-sdk/guide/create-map/show-map)

### 3. 平台特殊配置

#### iOS 配置

在 iOS 工程的 `info.plist` 中添加以下配置（Flutter 1.22.0 之前版本需要）：

```xml
<key>io.flutter.embedded_views_preview</key>
<string>YES</string>
```

#### HarmonyOS 配置

1. 确保项目使用 HarmonyOS Next 版本
2. 在 `ohos/oh-package.json5` 中配置高德地图 SDK 依赖
3. 在 `ohos/src/main/module.json5` 中配置所需权限和 API Key
4. 获得定位权限后使用

> 📝 **注意**: 详细的 HarmonyOS 配置请参考 [HARMONYOS_SETUP.md](HARMONYOS_SETUP.md)

## 📦 安装使用

### pub.dev 版本（Android + iOS）

```yaml
dependencies:
  csp_amap_flutter_map: ^1.1.0
```

### 完整版本（Android + iOS + HarmonyOS）

如需要 **HarmonyOS 支持**，请使用 Gitee 仓库版本：

```yaml
dependencies:
  csp_amap_flutter_map:
    git:
      url: https://gitee.com/chenshipeng0914/csp_amap_flutter_map.git
      ref: develop
```

> 📝 **说明**: pub.dev 版本为了兼容性考虑，仅包含 Android 和 iOS 平台支持。完整的 HarmonyOS 支持请使用 Gitee 仓库版本。

### 1. 安装依赖

```bash
# 使用 FVM（推荐）
fvm flutter pub get

# 或者直接使用 Flutter
flutter pub get
```

> 📝 **推荐使用 FVM**: 本项目使用 FVM 管理 Flutter 版本，支持 HarmonyOS 的定制 Flutter 版本 3.22.1-ohos-0.1.1

### 2. 导入包

> 📦 **注意**: 基础库（`csp_amap_flutter_base`）已内置到本包，无需额外安装。

```dart
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';
```

## 🚀 快速开始

### 1. 初始化 SDK

```dart
// 在 main.dart 中初始化
AMapInitializer.init(
  context,
  apiKey: AMapApiKey(
    androidKey: 'your_android_key',
    iosKey: 'your_ios_key',
    ohosKey: 'your_harmonyos_key', // HarmonyOS 支持
  ),
);
```

### 2. 合规处理

根据[高德 SDK 合规使用方案](https://lbs.amap.com/news/sdkhgsy)，需要进行授权交互：

```dart
// 在用户同意隐私协议后调用
AMapInitializer.updatePrivacyAgree(
  AMapPrivacyStatement(
    hasContains: true,  // 是否包含高德隐私政策
    hasShow: true,      // 是否已展示隐私政策
    hasAgree: true,     // 是否同意隐私政策
  ),
);
```

### 3. 基本使用

```dart
import 'package:flutter/material.dart';
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';

class BasicMapPage extends StatefulWidget {
  @override
  _BasicMapPageState createState() => _BasicMapPageState();
}

class _BasicMapPageState extends State<BasicMapPage> {
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(39.909187, 116.397451), // 北京天安门
    zoom: 10.0,
  );

  AMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('高德地图示例')),
      body: AMapWidget(
        initialCameraPosition: _initialPosition,
        onMapCreated: (AMapController controller) {
          _mapController = controller;
        },
        onTap: (LatLng latLng) {
          print('点击位置: $latLng');
        },
      ),
    );
  }
}
```

## 📋 API 文档

## 📱 示例代码

### 基础地图显示

```dart
import 'package:amap_flutter_map_example/base_page.dart';
import 'package:flutter/material.dart';

import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:st_amap_flutter_base/st_amap_flutter_base.dart';

class ShowMapPage extends BasePage {
  ShowMapPage(String title, String subTitle) : super(title, subTitle);
  @override
  Widget build(BuildContext context) {
    return _ShowMapPageBody();
  }
}

class _ShowMapPageBody extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ShowMapPageState();
}

class _ShowMapPageState extends State<_ShowMapPageBody> {
  static final CameraPosition _kInitialPosition = const CameraPosition(
    target: LatLng(39.909187, 116.397451),
    zoom: 10.0,
  );
  List<Widget> _approvalNumberWidget = List<Widget>();
  @override
  Widget build(BuildContext context) {
    final AMapWidget map = AMapWidget(
      initialCameraPosition: _kInitialPosition,
      onMapCreated: onMapCreated,
    );

    return ConstrainedBox(
      constraints: BoxConstraints.expand(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: map,
          ),
          Positioned(
              right: 10,
              bottom: 15,
              child: Container(
                alignment: Alignment.centerLeft,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: _approvalNumberWidget),
              ))
        ],
      ),
    );
  }

  AMapController _mapController;
  void onMapCreated(AMapController controller) {
    setState(() {
      _mapController = controller;
      getApprovalNumber();
    });
  }

  /// 获取审图号
  void getApprovalNumber() async {
    //普通地图审图号
    String mapContentApprovalNumber =
        await _mapController?.getMapContentApprovalNumber();
    //卫星地图审图号
    String satelliteImageApprovalNumber =
        await _mapController?.getSatelliteImageApprovalNumber();
    setState(() {
      if (null != mapContentApprovalNumber) {
        _approvalNumberWidget.add(Text(mapContentApprovalNumber));
      }
      if (null != satelliteImageApprovalNumber) {
        _approvalNumberWidget.add(Text(satelliteImageApprovalNumber));
      }
    });
    print('地图审图号（普通地图）: $mapContentApprovalNumber');
    print('地图审图号（卫星地图): $satelliteImageApprovalNumber');
  }
}

```

### 添加自定义Widget的Marker

```dart
// 添加一个预览图片的方法
  void _addCustomMarkerImage() async {
    // 创建一个 GlobalKey 来获取 Widget 的渲染对象
    final GlobalKey repaintKey = GlobalKey();

    // 创建一个自定义的 Widget
    final Widget customWidget = RepaintBoundary(
      key: repaintKey,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(25),
          ),
          child: const Center(
            child: Text(
              '自定义',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
    );

    // 首先将 Widget 添加到 Overlay 中进行渲染
    final OverlayState? overlayState = Overlay.of(context);
    final OverlayEntry entry = OverlayEntry(
      builder: (context) => Positioned(
        left: -1000, // 放在屏幕外
        top: -1000,
        child: customWidget,
      ),
    );

    overlayState?.insert(entry);

    // 等待下一帧完成渲染
    await Future.delayed(const Duration(milliseconds: 20));

    // 获取渲染对象并转换为图片
    final RenderRepaintBoundary? boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null) {
      entry.remove();
      return;
    }

    // 渲染为图片
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);

    // 使用完后移除 Overlay
    entry.remove();

    final Uint8List? bytes = byteData?.buffer.asUint8List();
    if (bytes != null) {
      final markerPosition =
          LatLng(_currentLatLng.latitude, _currentLatLng.longitude + 2 / 1000);
      final BitmapDescriptor bitmapDescriptor =
          BitmapDescriptor.fromBytes(bytes);
      final Marker marker = Marker(
        position: _currentLatLng,
        icon: bitmapDescriptor,
      );
      //调用setState触发AMapWidget的更新，从而完成marker的添加
      setState(() {
        _currentLatLng = markerPosition;
        //将新的marker添加到map里
        _markers[marker.id] = marker;
      });
    }
  }
```

### 添加Marker和Polyline实例

```dart
int colorsIndex = 0;
  List<Color> colors = <Color>[
    Colors.purple,
    Colors.red,
    Colors.green,
    Colors.pink,
  ];
  final Map<String, Polyline> _polylines = <String, Polyline>{};
  String? selectedPolylineId;
  LatLng mapCenter = const LatLng(36.811483, 118.497235);
  final Map<String, Marker> _initMarkerMap = <String, Marker>{};
  final BitmapDescriptor _markerIcon =
      BitmapDescriptor.fromIconPath('assets/start.png');
  final BitmapDescriptor _markerIcon1 =
      BitmapDescriptor.fromIconPath('assets/end.png');
  void _onMapCreated(AMapController controller) {}
  List<LatLng> points = <LatLng>[];
  List<LatLng> _createPoints() {
    final List<LatLng> points = <LatLng>[];
    points.add(const LatLng(39.90403, 116.407525));
    points.add(const LatLng(31.238068, 121.501654));
    points.add(const LatLng(30.679879, 104.064855));
    return points;
  }

  /// 获取polyline数据
  void readJsonFileToMap() async {
    String jsonString =
        await DefaultAssetBundle.of(context).loadString("assets/map.json");
    Map<String, dynamic> jsonMap = jsonDecode(jsonString);
    String polylinesPositions = jsonMap['data']['polyline'];

    List<String> pointsString = polylinesPositions.split(';');
    for (String point in pointsString) {
      List<String> latLng = point.split(',');
      if (latLng.length == 2) {
        points.add(LatLng(double.parse(latLng[0]), double.parse(latLng[1])));
      }
    }
    final Polyline polyline = Polyline(
        color: Colors.red, width: 5, points: points, onTap: _onPolylineTapped);
    LatLng position = points[0];
    LatLng endPosition = points.last;
    LatLng centerPosition = points[points.length ~/ 2];

    Marker startMarker = Marker(
      position: position,
      alpha: 1,
      icon: _markerIcon,
      zIndex: 1,
      infoWindow: const InfoWindow(title: '起点', snippet: '这里是起点'),
    );

    Marker endMarker = Marker(
      position: endPosition,
      alpha: 1,
      icon: _markerIcon1,
      zIndex: 1,
      infoWindow: const InfoWindow(title: '终点', snippet: '这里是终点'),
    );

    setState(() {
      _polylines[polyline.id] = polyline;
      mapCenter = centerPosition;
      _initMarkerMap[startMarker.id] = startMarker;
      _initMarkerMap[endMarker.id] = endMarker;
    });
  }

  void _add() {
    final Polyline polyline = Polyline(
        color: Colors.red,
        width: 10,
        points: _createPoints(),
        onTap: _onPolylineTapped);
    print('Polyline: ${polyline.toMap().toString()} 被添加了');
    setState(() {
      _polylines[polyline.id] = polyline;
    });
  }
  @override
  Widget build(BuildContext context) {
    final AMapWidget map = AMapWidget(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: mapCenter,
        zoom: 5,
      ),
      markers: Set<Marker>.of(_initMarkerMap.values),
      polylines: Set<Polyline>.of(_polylines.values),
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            width: MediaQuery.of(context).size.width,
            child: map,
          ),
          ElevatedButton(
            onPressed: _add,
            child: const Text('添加Polyline'),
          ),
        ],
      ),
    );
  }
```

### 地图视图

```dart
///用于展示高德地图的Widget
class AMapWidget extends StatefulWidget {
  /// 初始化时的地图中心点
  final CameraPosition initialCameraPosition;

  ///地图类型
  final MapType mapType;

  ///自定义地图样式
  final CustomStyleOptions? customStyleOptions;

  ///定位小蓝点
  final MyLocationStyleOptions? myLocationStyleOptions;

  ///缩放级别范围
  final MinMaxZoomPreference? minMaxZoomPreference;

  ///地图显示范围
  final LatLngBounds? limitBounds;

  ///显示路况开关
  final bool trafficEnabled;

  /// 地图poi是否允许点击
  final bool touchPoiEnabled;

  ///是否显示3D建筑物
  final bool buildingsEnabled;

  ///是否显示底图文字标注
  final bool labelsEnabled;

  ///是否显示指南针
  final bool compassEnabled;

  ///是否显示比例尺
  final bool scaleEnabled;

  ///是否支持缩放手势
  final bool zoomGesturesEnabled;

  ///是否支持滑动手势
  final bool scrollGesturesEnabled;

  ///是否支持旋转手势
  final bool rotateGesturesEnabled;

  ///是否支持倾斜手势
  final bool tiltGesturesEnabled;

  /// logo 位置，此字段高德只支持Android，本插件iOS借用logoCenter做了实现
  final LogoPosition? logoPosition;

  /// logo 底部间距(px)，此字段高德只支持Android，本插件iOS借用logoCenter做了实现
  final int? logoBottomMargin;

  /// logo 靠左间距(px)，此字段高德只支持Android，本插件iOS借用logoCenter做了实现
  final int? logoLeftMargin;

  /// 地图上显示的Marker
  final Set<Marker> markers;

  /// 地图上显示的polyline
  final Set<Polyline> polylines;

  /// 地图上显示的polygon
  final Set<Polygon> polygons;

  /// 地图创建成功的回调, 收到此回调之后才可以操作地图
  final MapCreatedCallback? onMapCreated;

  /// 相机视角持续移动的回调
  final ArgumentCallback<CameraPosition>? onCameraMove;

  /// 相机视角移动结束的回调
  final ArgumentCallback<CameraPosition>? onCameraMoveEnd;

  /// 地图单击事件的回调
  final ArgumentCallback<LatLng>? onTap;

  /// 地图长按事件的回调
  final ArgumentCallback<LatLng>? onLongPress;

  /// 地图POI的点击回调，需要`touchPoiEnabled`true，才能回调
  final ArgumentCallback<AMapPoi>? onPoiTouched;

  ///位置回调
  final ArgumentCallback<AMapLocation>? onLocationChanged;

  ///需要应用到地图上的手势集合
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// 设置地图语言
  final MapLanguage? mapLanguage;

  /// Marker InfoWindow 适配器
  final InfoWindowAdapter? infoWindowAdapter;
}
```

### 地图控制器

```dart

class AMapController {

  ///改变地图视角
  ///
  ///通过[CameraUpdate]对象设置新的中心点、缩放比例、放大缩小、显示区域等内容
  ///
  ///（注意：iOS端设置显示区域时，不支持duration参数，动画时长使用iOS地图默认值350毫秒）
  ///
  ///可选属性[animated]用于控制是否执行动画移动
  ///
  ///可选属性[duration]用于控制执行动画的时长,默认250毫秒,单位:毫秒
  Future<void> moveCamera(CameraUpdate cameraUpdate,
      {bool animated = true, int duration = 250});

  ///地图截屏
  Future<Uint8List?> takeSnapshot();

  /// 清空缓存
  Future<void> clearDisk();

  /// 经纬度转屏幕坐标
  Future<ScreenCoordinate> toScreenCoordinate(LatLng latLng);

  /// 屏幕坐标转经纬度
  Future<LatLng> fromScreenCoordinate(ScreenCoordinate screenCoordinate);
}


```

## ⚙️ 平台配置

### Android 平台

1. **最低版本要求**: Android API 21+
2. **targetSDKVersion >= 30 问题修复**:
   在 `android/app/src/main/AndroidManifest.xml` 中添加:

   ```xml
   <application android:allowNativeHeapPointerTagging="false">
       <!-- 其他配置 -->
   </application>
   ```

3. **权限配置**:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   ```

### iOS 平台

1. **最低版本要求**: iOS 11.0+
2. **Info.plist 配置**:

   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>本应用需要在使用期间访问位置服务来显示您的定位</string>

   <!-- Flutter 1.22.0 之前版本需要 -->
   <key>io.flutter.embedded_views_preview</key>
   <string>YES</string>
   ```

### HarmonyOS 平台

1. **系统要求**: HarmonyOS Next 5.0+
2. **依赖配置**: 请参考 [HARMONYOS_SETUP.md](HARMONYOS_SETUP.md)
3. **权限配置**: 在 `module.json5` 中配置定位权限

## 📄 AMapController API

地图控制器提供了丰富的地图控制功能：

```dart
class AMapController {
  // 相机控制
  Future<void> moveCamera(CameraUpdate cameraUpdate, {
    bool animated = true,
    int duration = 250,
  });

  // 地图截屏
  Future<Uint8List?> takeSnapshot();

  // 坐标转换
  Future<ScreenCoordinate> toScreenCoordinate(LatLng latLng);
  Future<LatLng> fromScreenCoordinate(ScreenCoordinate screenCoordinate);

  // 其他功能
  Future<void> clearDisk();  // 清空缓存
  Future<String?> getMapContentApprovalNumber();  // 获取审图号
  Future<String?> getSatelliteImageApprovalNumber(); // 获取卫星审图号
}
```

## ⚠️ 常见问题

### 1. iOS 地图销毁时 Main Thread Checker 报警

**问题**: Flutter 插件在 iOS 端，MapView 销毁时一定概率触发 Main Thread Checker 的报警。

**原因**: 经过对比测试确认是 Flutter 的 bug 所致。

**解决方案**:

- 依赖 Flutter 升级修复
- 建议使用 Flutter 1.24.0+ 版本
- 参考: [Flutter Issue #68490](https://github.com/flutter/flutter/issues/68490)

### 2. Android targetSDKVersion >= 30 地图页返回闪退

**问题**: 当 app 的 targetSDKVersion >= 30 时，地图页返回可能闪退。

**解决方案**: 在 AndroidManifest.xml 中添加配置：

```xml
<application android:allowNativeHeapPointerTagging="false">
    <!-- 其他配置 -->
</application>
```

**参考**: [Google 官方说明](https://source.android.com/devices/tech/debug/tagged-pointers)

### 3. HarmonyOS 平台问题

**问题**: HarmonyOS 平台编译或运行错误。

**解决方案**:

1. 确保使用 FVM 和支持 HarmonyOS 的 Flutter 版本
2. 检查 oh-package.json5 中的依赖配置
3. 参考 [HARMONYOS_SETUP.md](HARMONYOS_SETUP.md) 进行配置

### 4. API Key 相关问题

**问题**: 地图不显示或显示错误信息。

**解决方案**:

1. 检查 API Key 是否正确配置
2. 确认 API Key 的平台和包名匹配
3. 检查 API Key 是否在高德控制台启用
4. 确认已调用合规初始化方法

### 5. Android 构建问题

**问题**: Android 构建失败，出现 "Java heap space" 或 SDK 版本相关错误。

**解决方案**:

1. 确保 compileSdkVersion 设置为 36 或更高版本
2. 在 gradle.properties 中增加内存分配: `org.gradle.jvmargs=-Xmx4096M`
3. 移除弃用的配置项如 `android.enableR8`
4. 清理 Gradle 缓存后重新构建

## 📦 更新日志

### v1.0.1 (2025-09-04)

- 🐛 **Android 构建修复**: 解决了 Android 平台上的构建问题
  - 升级 compileSdkVersion 从 35 到 36
  - 增加 Gradle 内存分配到 -Xmx4096M
  - 移除弃用的 android.enableR8 配置
- 🛠️ **Gradle 配置优化**: 更新了 Gradle 配置以提高兼容性和性能

### v1.0.0 (2024-12-19)

- ✨ 新增 HarmonyOS 平台支持
- 🔧 从 st_amap_flutter_map 重构为 csp_amap_flutter_map
- 🐛 修复所有编译错误和 linting 问题
- 📋 添加完整的文档和示例
- 🎨 优化代码结构和质量
- 🔧 支持 FVM 版本管理

## 🤝 贡献指南

欢迎贡献代码和建议！

### 开发环境

1. **克隆仓库**:

   ```bash
   git clone https://gitee.com/chenshipeng0914/csp_amap_flutter_map.git
   cd csp_amap_flutter_map
   ```

2. **安装 FVM**:

   ```bash
   # 安装 FVM
   dart pub global activate fvm

   # 使用项目指定的 Flutter 版本
   fvm use custom_3.22.0
   ```

3. **安装依赖**:
   ```bash
   fvm flutter pub get
   cd example && fvm flutter pub get
   ```

### 贡献流程

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交修改 (`git commit -m 'Add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

### 代码规范

- 遵循 Flutter 和 Dart 官方编码规范
- 使用 `fvm flutter analyze` 检查代码质量
- 添加必要的注释和文档
- 确保所有平台都能正常编译和运行

## 📞 联系支持

- **问题报告**: [Gitee Issues](https://gitee.com/chenshipeng0914/csp_amap_flutter_map/issues)
- **功能建议**: [Gitee Issues](https://gitee.com/chenshipeng0914/csp_amap_flutter_map/issues)
- **讨论交流**: [Gitee 讨论区](https://gitee.com/chenshipeng0914/csp_amap_flutter_map)

## 📜 许可证

本项目采用 [Apache 2.0](LICENSE) 许可证。

## 🙏 致谢

- [高德开放平台](https://lbs.amap.com/) 提供的优秀 SDK
- [Flutter 社区](https://flutter.dev/) 的技术支持
- 所有为本项目贡献代码和建议的开发者

---

<div align="center">
  <sub>由 ❤️ 制作，为 Flutter 开发者提供更好的地图解决方案</sub>
</div>
