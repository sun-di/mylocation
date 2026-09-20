# ShowLocation

跨平台地图选点 + 「模拟位置（Mock Location）」实验 App。在地图上选点后，把该坐标注入 Android 系统位置服务，
让高德 / 百度 / 腾讯等第三方地图 APP 读到的是你设定的位置；并提供「反推校准」自动逼近真实 APP 的显示位置。

> 文档版本：v1.1 ｜ 更新日期：2026-09-20
> 当前状态：**Android 功能已实现并真机跑通**；鸿蒙 / iOS 仅预留（未接入）。

---

## 1. 功能清单

| 功能 | 说明 | 主要实现 |
|------|------|----------|
| 地图浏览 | 高德地图，支持缩放 / 拖动 / 旋转 / 倾斜 | `lib/map/amap_strategy.dart` |
| 点选位置 | 点击 / 长按地图选点，自动逆地理编码补全地址 | `lib/pages/home_page.dart` |
| 已选位置气泡 | 屏幕中央偏上浮层，显示名称 / 经纬度 / 地址；滚动地图自动消失 | `_PickedLocationBubble` |
| 关键字搜索 | 顶部搜索框：输入 300ms 防抖联想（inputtips）+ 点击搜索（多结果底部列表） | `_SearchBar` / `_SuggestionList` |
| 真实定位 | 启动 / 点定位按钮 → 绿车标常驻，地图跳到当前位置；「显示当前位置」播报中文地址 | `MockService.requestRealLocation` |
| 收藏与历史 | 保存选点（可改名，上限 10 条）；历史页展开行可 Go / Delete / Run / 勾选 always（启动自动应用） | `lib/persistence/location_bookmark.dart`、`lib/pages/bookmarks_page.dart` |
| 模拟位置 | 「应用到系统」→ 原生前台服务每 500ms 注入一次 mock fix（GPS + 可选 NETWORK 镜像） | `MockLocationService.kt`、`lib/mock_location/` |
| AL 探针 | 用高德独立定位 SDK 拿「高德视角」的位置，紫色 pin 叠加显示，判断是否被反 mock | `requestAmapLocation` |
| 反推校准 | 偏差 > 50m 时自动迭代注入坐标 `ML = 2·UL − AL`，最多 4 轮，收敛到 < 50m | `MockController.runCalibration` |
| 模拟状态对话框 | 实时显示模拟状态 / 位置校准偏差 / 推理进度，标题「准备中 → 已就绪」 | `_MockStatusDialog` |
| 地图锁定 | 模拟期间禁用全部手势与点选回调，停止后自动解锁 | `mapInteractive` |

---

## 2. 技术栈

| 项 | 选型 | 版本 / 说明 |
|----|------|-------------|
| 框架 | Flutter (Dart) | `pubspec.yaml` 约束 Dart `>=3.3.0 <4.0.0`；`pubspec.lock` 实际要求 Flutter `>=3.44.0`、Dart `>=3.12.0` |
| 地图 | `csp_amap_flutter_map` | **本地 path 依赖** `vendor/csp_amap_flutter_map`（1.1.1），兼容 AGP8 / compileSdk 35+ |
| 高德原生 SDK | `com.amap.api:3dmap-location-search` | `10.1.200_loc6.4.9_sea9.7.4`（地图 + 定位 + 搜索整合包，`app/build.gradle.kts` 声明） |
| 网络 | `http` ^1.2.0（解析 1.6.0） | 高德 Web 服务 REST：逆地理编码 `geocode/regeo`、输入提示 `assistant/inputtips` |
| 权限 | `permission_handler` ^11.3.0（11.4.0） | 运行时申请精确定位 |
| 本地存储 | `shared_preferences` ^2.2.3（2.5.5） | 收藏位置 JSON + always 书签 id |
| 状态管理 | `ValueNotifier` / `ValueListenableBuilder` + `StatefulWidget` | 不引入额外状态管理框架 |
| Android 构建 | AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14.3（腾讯云镜像）/ JVM 17 | `android/settings.gradle.kts`、`gradle-wrapper.properties` |

> 高德 Key 通过**构建期注入**（`--dart-define-from-file`），源码中不再包含任何明文 Key，见 §4.2。

---

## 3. 目录结构

```
showlocation/
├── lib/
│   ├── main.dart                      # 入口：ensureInitialized + runApp
│   ├── app.dart                       # MaterialApp（Material 3）
│   ├── models/
│   │   └── location_info.dart         # 位置模型 + displayText 展示文案
│   ├── map/
│   │   ├── map_strategy.dart          # 地图抽象（MapStrategy/CameraPosition/MapMarker）
│   │   └── amap_strategy.dart         # 高德实现：地图、相机、regeo、inputtips（Key 由构建期注入）
│   ├── mock_location/
│   │   ├── mock_service.dart          # MethodChannel `show_location/mock` 的 Dart 桥
│   │   ├── mock_controller.dart       # 模拟状态机 + 反推校准 control loop
│   │   └── mock_location_zh.md        # 模拟位置功能说明（含排查手册）
│   ├── persistence/
│   │   └── location_bookmark.dart     # 收藏位置仓库（SharedPreferences，上限 10）
│   └── pages/
│       ├── home_page.dart             # 主页面：地图 + 搜索 + 按钮 + 状态对话框
│       └── bookmarks_page.dart        # 历史位置列表（Go / Run / Delete / always）
├── android/app/src/main/kotlin/com/example/showlocation/
│   ├── MainActivity.kt                # MethodChannel 9 个方法 + 真实定位 + AL 探针
│   └── MockLocationService.kt         # 前台服务：500ms 推送循环 + WakeLock + 通知
├── assets/icons/                      # car_green / car_red / pin_blue / pin_violet
├── keys/
│   └── dart_define.example.json        # 高德 Key 模板（真正的 keys/dart_define.json 不入库）
├── vendor/csp_amap_flutter_map/       # 高德 Flutter 插件（本地覆盖，见下文修复说明）
├── docs/                              # 需求 / 架构 / SDK 评估 / P60 调试指南
├── supported_devices.md               # 机型与系统版本、测试矩阵
├── RELEASE_GUIDE.md                   # 环境、验证、发布全流程
├── build_docx.py / build_pdf.py       # 计划书 md → docx / pdf 的本地构建脚本
└── _run.ps1 / _check.ps1 / _diag.ps1 / _testgradle.ps1   # 本机调试辅助脚本
```

---

## 4. 快速开始

### 4.1 环境要求

| 项 | 要求 |
|----|------|
| Flutter | stable，≥ 3.44（`pubspec.lock` 要求）；`flutter doctor` 全绿 |
| JDK | 17（工程 `compileOptions` / `kotlinOptions` 均为 JVM 17） |
| Android SDK | 含 platform-tools、build-tools；`minSdk` 由 Flutter 模板决定（vendor 插件下限 21） |
| 真机 | Android 6.0+，需开启开发者选项与 USB 调试（模拟位置功能必须真机，模拟器无意义） |

### 4.2 运行

```bash
flutter pub get

# 1) 配置高德 Key（源码中不再有明文 Key，改为构建期注入）
copy keys\dart_define.example.json keys\dart_define.json   # 复制模板并填入 3 个 Key
#    · Android Key：用「包名 + 签名 SHA1」在高德控制台申请并绑定，否则地图空白
#    · iOS Key：用 BundleId 申请（留空则回退用 Android Key）
#    · Web 服务 Key：逆地理编码 / 输入提示 REST 专用（与 Android Key 分开申请）
#    keys/dart_define.json 已在 .gitignore 中，不会被提交

# 2) 运行 / 构建都带上该文件
flutter run --dart-define-from-file=keys/dart_define.json
flutter build apk --debug --dart-define-from-file=keys/dart_define.json
#    产物：build/app/outputs/flutter-apk/app-debug.apk

flutter analyze             # 静态检查
flutter test                # 当前仅占位 smoke test
```

> 未注入 Key 时 App 仍可启动，但地图空白，且会弹出 SnackBar 提示「未配置高德 Key」。

### 4.3 首次使用模拟位置（必须做一次）

1. 手机：`设置 → 关于手机 → 版本号` 连点 7 次，开启开发者选项。
2. `开发者选项 → 选择模拟位置应用`，选中 **showlocation**。
3. 回到 APP，地图上选点 → 点 **应用到系统**；系统通知栏会出现「模拟位置运行中」前台服务通知。
4. 反推校准完成后（对话框标题变为「已就绪」），打开高德 / 百度地图查看注入效果。
5. 用完点 **停止模拟**，移除 Test Provider，其他 APP 恢复真实 GPS。

> 详细原理、参数与故障排查见 [`lib/mock_location/mock_location_zh.md`](lib/mock_location/mock_location_zh.md)。

### 4.4 安装到手机（真机部署）

本 App 需在**真机**上运行（模拟位置功能尤其如此，模拟器无意义）。三步：手机开调试 → 连接 → 安装运行。

**1) 手机开启 USB 调试**

`设置 → 关于手机 → 版本号` 连点 7 次开启开发者模式 → `开发者选项` 打开「USB 调试」→ 数据线连电脑并允许授权。

**2) 确认设备被识别**

```bash
flutter devices      # 或 adb devices
```

**3) 安装运行（三选一）**

```bash
# 方式 A：直接运行（调试首选，支持热重载）
flutter run --dart-define-from-file=keys/dart_define.json

# 方式 B：构建 debug 包并安装到已连接设备
flutter build apk --debug --dart-define-from-file=keys/dart_define.json
flutter install        # 安装到唯一已连接设备（多设备加 -d <id>）

# 方式 C：手动用 adb 装 APK（发给别人 / 换机）
flutter build apk --debug --dart-define-from-file=keys/dart_define.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

> - 首次使用「模拟位置」前，还需在手机 `开发者选项 → 选择模拟位置应用` 中选中 **showlocation**（见 §4.3）。
> - 手机需允许「安装未知来源应用」；华为 P60 等鸿蒙双框架机型还要关闭「应用启动管理」的自动管理，见 [`docs/华为P60.md`](docs/华为P60.md)。
> - release 正式包与签名配置见 [`RELEASE_GUIDE.md`](RELEASE_GUIDE.md)（当前 release 仍用 debug 签名，仅适合本地）。

---

## 5. 文档索引

| 文档 | 内容 |
|------|------|
| [`docs/requirements.md`](docs/requirements.md) | 需求与验收：功能点 FR-1~FR-9、验收标准、边界与非目标（已按实现回填） |
| [`docs/architecture.md`](docs/architecture.md) | 架构设计：分层、模块清单、关键流程（定位 / 选点 / 模拟 / 反推）、MethodChannel 契约、状态机 |
| [`docs/map_sdk_evaluation.md`](docs/map_sdk_evaluation.md) | 地图 SDK 选型评估与最终结论（高德 + 社区维护插件 + vendor 覆盖原因） |
| [`supported_devices.md`](supported_devices.md) | 机型 / 系统版本清单与首期测试矩阵 |
| [`docs/华为P60.md`](docs/华为P60.md) | 华为 P60（鸿蒙双框架）真机调试指南与验证重点 |
| [`RELEASE_GUIDE.md`](RELEASE_GUIDE.md) | 全周期：环境搭建 → 编码 → 验证 → 发布（含发布前检查清单） |
| [`lib/mock_location/mock_location_zh.md`](lib/mock_location/mock_location_zh.md) | 模拟位置功能原理、使用流程、已知限制、故障排查 |

---

## 6. 已知限制与待办

| 项 | 现状 | 建议 |
|----|------|------|
| 高德 Key **必须轮换** | 源码已改为构建期注入（`--dart-define-from-file`），但**历史提交中的旧 Key 仍在 git 历史里**，视为已泄露 | 去高德控制台**删除旧 Key 并重新生成**；后续用 `keys/dart_define.json`（已 gitignore）注入 |
| iOS | 无 `Podfile`、`Info.plist` 无定位权限描述、`AppDelegate` 未配置高德 Key、无 mock 通道实现 | 走阶段 4 适配，见 `RELEASE_GUIDE.md` |
| 鸿蒙（HarmonyOS NEXT / OpenHarmony） | 未适配（无 `ohos/` 工程，未接高德鸿蒙 SDK）；双框架机型可装 Android APK | 走 Flutter 鸿蒙分支 + 高德鸿蒙 SDK，经 `MapStrategy` 抽象接入 |
| 第三方 APP 反 Mock | 高德等通过 `Location.isFromMockProvider` 判定并降权；本项目用「反推校准」尽量逼近，但**无法保证 100% 生效** | 属系统级限制，需 ROOT / 系统级方案 |
| 单元测试 | `test/widget_test.dart` 为占位 smoke test | 补充 `MapStrategy` / `MockController` 的纯逻辑单测 |
| 调试脚本注释过时 | `_run.ps1` / `_diag.ps1` 注释仍写 AGP 7.4.2 / Gradle 7.5（实际已是 8.11.1 / 8.14.3） | 同步注释（脚本为本地辅助工具，不影响构建） |
| 隐私合规 | `updatePrivacyAgree(hasAgree: true)` 目前是**默认视为同意** | 正式分发前改为先弹隐私政策、按用户选择再初始化 SDK |

---

## 7. 关于 vendor 覆盖

`vendor/csp_amap_flutter_map` 是对 pub.dev 版插件的**本地覆盖**（`pubspec.yaml` 中以 `path:` 引入），修复了：

- `location2Map` 把**纬度校验误写成海拔校验**的 bug —— 否则真实 GPS 海拔 > 90m 时 `onLocationChanged` 会被静默丢弃；
- 与 AGP 8 / compileSdk 35+ 的构建兼容性。

因此**不要**把该依赖改回 pub.dev 版本，否则上述问题会复现。
