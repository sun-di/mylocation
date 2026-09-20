# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-08-09

### Fixed

- 🐛 修复 Dart 3.12+ 移除 `Stream.whereType` 导致的编译错误（8 处回调改用 `where(...).cast<T>()`）
- 🐛 修复 `AMapWidget.myLocationEnabled` 未传入 `_AMapOptions` 导致显示定位小蓝点失效的问题
- 🔧 完善 HarmonyOS (ohos) 平台支持：修正 `build-profile.json5` HAR 配置、补充权限声明、修复 POI 空值崩溃

## [1.1.0] - 2026-08-08

### Added

- 📦 **内置基础库**: 合并 `csp_amap_flutter_base` 源码到 `lib/base/`，不再需要外部依赖
  - 定位（Location）、POI 搜索、API Key 管理、隐私合规配置等能力随包提供
  - 原有 `import 'package:csp_amap_flutter_base/...'` 改为 `package:csp_amap_flutter_map/base/...`
- 🗺️ 移除对 `csp_amap_flutter_base` 的 pub.dev 依赖，简化集成

## [1.0.2] - 2026-08-07

### Fixed

- 🐛 **HarmonyOS 编译报错**: 支持 `useNormalizedOHMUrl` 以兼容高德字节码 HAR 依赖
- ⚡ **HarmonyOS 折线性能**: 消除属性双重计算与冗余日志，`toPoints()` 改用 `toFloat()` 修复坐标换算
- 📍 **定位功能**: `myLocationEnabled` 独立定位开关在 Android / iOS / HarmonyOS 三端生效
- 🐛 **iOS 定位开关**: `updateMapViewOption` 支持独立 `myLocationEnabled`（未设置 `myLocationStyle` 时生效）
- 🔧 **代码质量**: 移除重复插件类、废弃依赖，统一日志输出

## [1.0.1] - 2025-09-04

### Fixed

- 🐛 **Android Build Issues**: Resolved Gradle build failures on Android by:
  - Upgrading compileSdkVersion from 35 to 36
  - Increasing Gradle memory allocation to -Xmx4096M
  - Removing deprecated android.enableR8 configuration
- 🛠️ **Gradle Configuration**: Updated Gradle settings for better compatibility and performance

## [1.0.0] - 2024-12-19

### Added

- 🎉 Initial release of csp_amap_flutter_map
- 🌍 Multi-platform support for Android, iOS, and HarmonyOS
- 🗺️ Core map functionality including:
  - Map display with multiple map types (normal, satellite, navigation, bus, night)
  - Interactive gestures (zoom, scroll, rotate, tilt)
  - Marker support with custom icons and info windows
  - Polyline and polygon drawing capabilities
  - Location services and blue dot positioning
  - Map screenshots and coordinate conversion
- 🎨 Custom map styling support
- 📱 Responsive design for various screen sizes
- 🔒 Privacy compliance handling
- 📚 Comprehensive documentation and examples
- 🛠️ FVM support with custom Flutter version for HarmonyOS

### Features

- **Map Display**: Support for various map types and configurations
- **Markers**: Add, remove, and customize map markers with custom icons
- **Polylines**: Draw paths with customizable styles and colors
- **Polygons**: Create and manage polygon overlays
- **Location**: Real-time location tracking and display
- **Gestures**: Full gesture support for map interaction
- **Screenshots**: Capture map as image
- **Coordinate Conversion**: Convert between screen and geographic coordinates
- **Custom Styling**: Apply custom map styles and themes
- **Info Windows**: Custom marker info window support
- **Multiple Languages**: Support for different map languages

### Platform Support

- **Android**: Minimum API level 21 (Android 5.0)
- **iOS**: Minimum version iOS 11.0
- **HarmonyOS**: HarmonyOS Next 5.0+

### Dependencies

- Flutter SDK: >=3.22.0
- Dart SDK: >=3.4.0 <4.0.0
- AMap SDK for each platform

### Technical Highlights

- Built on AMap (Gaode Map) SDK
- Uses Flutter Platform Channels for native communication
- Supports custom Widget to Marker conversion
- Comprehensive error handling and validation
- Clean architecture with separation of concerns

### Documentation

- Complete README with installation and usage guides
- API documentation for all components
- Platform-specific setup instructions
- Common issues and troubleshooting guide
- Contributing guidelines for developers

## [Unreleased]

### Planned Features

- Additional map controls and overlays
- Enhanced performance optimizations
- More customization options
- Extended HarmonyOS features

---

For more details about each release, please check the [repository releases](https://gitee.com/chenshipeng0914/csp_amap_flutter_map/releases).
