# csp_amap_flutter_map

[![pub package](https://img.shields.io/badge/pub-v1.1.0-blue)](https://gitee.com/chenshipeng0914/csp_amap_flutter_map)
[![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios%20%7C%20harmonyos-lightgrey)](https://gitee.com/chenshipeng0914/csp_amap_flutter_map)
[![license](https://img.shields.io/badge/license-Apache%202.0-green)](https://gitee.com/chenshipeng0914/csp_amap_flutter_map/blob/develop/LICENSE)

A Flutter plugin for AMap (Gaode Map) SDK, supporting **Android**, **iOS**, and **HarmonyOS** platforms.

## ✨ Features

- 🌍 **Multi-platform Support**: Full coverage for Android, iOS, and HarmonyOS
- 🗺️ **Rich Map Features**: Multiple map types, markers, polylines, location services, etc.
- 📦 **Bundled Base Library**: Location, POI search, API key management and privacy compliance
  are bundled in this package, no extra dependency required
- 🎨 **Custom Styling**: Support for custom map styles and marker icons
- 📱 **Responsive Design**: Compatible with various screen sizes and resolutions
- 🔧 **Easy Integration**: Simple API design for quick project integration
- 📋 **Compliance Handling**: Built-in privacy compliance solutions

## 📦 Installation

### pub.dev Version (Android + iOS)

```yaml
dependencies:
  csp_amap_flutter_map: ^1.1.0
```

### Full Version (Android + iOS + HarmonyOS)

For **HarmonyOS support**, please use the Gitee repository version:

```yaml
dependencies:
  csp_amap_flutter_map:
    git:
      url: https://gitee.com/chenshipeng0914/csp_amap_flutter_map.git
      ref: develop
```

> 📝 **Note**: The pub.dev version only includes Android and iOS platform support for compatibility considerations. For full HarmonyOS support, please use the Gitee repository version.

### 1. Install Dependencies

```bash
# Using FVM (Recommended)
fvm flutter pub get

# Or directly using Flutter
flutter pub get
```

> 📝 **FVM Recommended**: This project uses FVM to manage Flutter versions, supporting custom Flutter version 3.22.1-ohos-0.1.1 for HarmonyOS.

### 2. Import Packages

> 📦 **Note**: The base library (`csp_amap_flutter_base`) is bundled in this package, no extra install needed.

```dart
import 'package:csp_amap_flutter_map/csp_amap_flutter_map.dart';
import 'package:csp_amap_flutter_map/base/csp_amap_flutter_base.dart';
```

## 🚀 Quick Start

### 1. Initialize SDK

```dart
// Initialize in main.dart
AMapInitializer.init(
  context,
  apiKey: AMapApiKey(
    androidKey: 'your_android_key',
    iosKey: 'your_ios_key',
    ohosKey: 'your_harmonyos_key', // HarmonyOS support
  ),
);
```

### 2. Compliance Handling

```dart
// Call after user agrees to privacy policy
AMapInitializer.updatePrivacyAgree(
  AMapPrivacyStatement(
    hasContains: true,  // Whether includes AMap privacy policy
    hasShow: true,      // Whether privacy policy has been shown
    hasAgree: true,     // Whether user agrees to privacy policy
  ),
);
```

### 3. Basic Usage

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
    target: LatLng(39.909187, 116.397451), // Beijing Tiananmen
    zoom: 10.0,
  );

  AMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AMap Example')),
      body: AMapWidget(
        initialCameraPosition: _initialPosition,
        onMapCreated: (AMapController controller) {
          _mapController = controller;
        },
        onTap: (LatLng latLng) {
          print('Tapped location: $latLng');
        },
      ),
    );
  }
}
```

## ⚙️ Platform Configuration

### Android Platform

1. **Minimum Version**: Android API 21+
2. **targetSDKVersion >= 30 Fix**:
   Add to `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <application android:allowNativeHeapPointerTagging="false">
       <!-- Other configurations -->
   </application>
   ```

3. **Permissions**:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   ```

### iOS Platform

1. **Minimum Version**: iOS 11.0+
2. **Info.plist Configuration**:

   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>This app needs location access to show your position on the map</string>

   <!-- Required for Flutter versions before 1.22.0 -->
   <key>io.flutter.embedded_views_preview</key>
   <string>YES</string>
   ```

### HarmonyOS Platform

1. **System Requirements**: HarmonyOS Next 5.0+
2. **Dependencies**: See [HARMONYOS_SETUP.md](HARMONYOS_SETUP.md)
3. **Permissions**: Configure location permissions in `module.json5`

## ⚠️ Common Issues

### 1. iOS MapView Destruction Main Thread Checker Warning

**Issue**: Flutter plugin on iOS triggers Main Thread Checker warning when MapView is destroyed.

**Cause**: Confirmed to be a Flutter bug.

**Solution**:

- Depends on Flutter upgrade for fix
- Recommend using Flutter 1.24.0+ versions
- Reference: [Flutter Issue #68490](https://github.com/flutter/flutter/issues/68490)

### 2. Android targetSDKVersion >= 30 Crash

**Issue**: App crashes when returning from map page with targetSDKVersion >= 30.

**Solution**: Add configuration in AndroidManifest.xml:

```xml
<application android:allowNativeHeapPointerTagging="false">
    <!-- Other configurations -->
</application>
```

### 3. HarmonyOS Platform Issues

**Issue**: Compilation or runtime errors on HarmonyOS platform.

**Solution**:

1. Ensure using FVM and HarmonyOS-supported Flutter version
2. Check dependency configuration in oh-package.json5
3. Reference [HARMONYOS_SETUP.md](HARMONYOS_SETUP.md) for configuration

### 4. Android Build Issues

**Issue**: Android build failures with "Java heap space" or SDK version related errors.

**Solution**:

1. Ensure compileSdkVersion is set to 36 or higher
2. Increase memory allocation in gradle.properties: `org.gradle.jvmargs=-Xmx4096M`
3. Remove deprecated configurations like `android.enableR8`
4. Clean Gradle cache and rebuild

## 👤 Contributing

Contributions and suggestions are welcome!

### Development Environment

1. **Clone Repository**:

   ```bash
   git clone https://gitee.com/chenshipeng0914/csp_amap_flutter_map.git
   cd csp_amap_flutter_map
   ```

2. **Install FVM**:

   ```bash
   # Install FVM
   dart pub global activate fvm

   # Use project-specified Flutter version
   fvm use custom_3.22.0
   ```

3. **Install Dependencies**:
   ```bash
   fvm flutter pub get
   cd example && fvm flutter pub get
   ```

### Contribution Process

1. Fork this repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Create Pull Request

## 📦 Changelog

### v1.0.1 (2025-09-04)

- 🐛 **Android Build Fix**: Resolved Android platform build issues
  - Upgraded compileSdkVersion from 35 to 36
  - Increased Gradle memory allocation to -Xmx4096M
  - Removed deprecated android.enableR8 configuration
- 🛠️ **Gradle Configuration Optimization**: Updated Gradle settings for better compatibility and performance

### v1.0.0 (2024-12-19)

- ✨ Added HarmonyOS platform support
- 🔧 Refactored from st_amap_flutter_map to csp_amap_flutter_map
- 🐛 Fixed all compilation errors and linting issues
- 📋 Added comprehensive documentation and examples
- 🎨 Optimized code structure and quality
- 🔧 Added FVM version management support

## 📜 License

This project is licensed under the [Apache 2.0](LICENSE) License.

## 🙏 Acknowledgments

- [AMap Open Platform](https://lbs.amap.com/) for excellent SDK
- [Flutter Community](https://flutter.dev/) for technical support
- All developers who contributed code and suggestions to this project

---

<div align="center">
  <sub>Made with ❤️ to provide better map solutions for Flutter developers</sub>
</div>
