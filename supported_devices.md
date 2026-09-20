# ShowLocation 机型与系统版本清单 / 测试矩阵

> 版本：v1.1 ｜ 更新日期：2026-09-20 ｜ 用途：适配与真机测试依据
> 首期以 **Android 真机验证**为主；鸿蒙双框架机型可直接跑 Android APK；纯鸿蒙 / iOS 仅作适配规划。

---

## 1. Android（首期重点）

### 1.1 系统版本与 API 级别

| Android 版本 | API | 适配建议 |
|--------------|-----|----------|
| 5.0 / 6.0 | 21 / 23 | `minSdk` 下限 21（vendor 插件要求）；23 起为运行时权限起点 |
| 7.x / 8.x | 24–27 | 适配；8.0 起前台服务必须发通知 |
| 9 | 28 | 适配（`setTestProviderStatus` 需 P+，代码已做版本分支） |
| 10 | 29 | 适配（`AppOpsManager.unsafeCheckOpNoThrow` 分支；前台服务类型） |
| 11 | 30 | 适配（单次权限） |
| 12 / 12L | 31 / 32 | 主测 |
| 13 / 14 | 33 / 34 | 主测（当前主流） |
| 15 / 16 | 35 / 36 | 主测（最新） |

**版本策略**：工程中 `compileSdk` / `minSdk` / `targetSdk` 均使用 Flutter 模板占位符（`flutter.compileSdkVersion` 等），
**未在项目内硬编码**；`vendor/csp_amap_flutter_map` 的 `compileSdkVersion 35`、`minSdkVersion 21` 构成实际下限。

### 1.2 机型档位（验证抽样建议）

| 档位 | 代表机型 | 验证目的 |
|------|----------|----------|
| 入门 / 老机 | 红米 9A、OPPO A 系列 | minSdk 下可安装运行、地图渲染性能下限 |
| 中端主力 | 红米 Note 系列、荣耀 X 系列、三星 A 系列 | 主力测试群体 |
| 旗舰 | 小米 14/15、Mate/Pura 安卓侧、P60（鸿蒙双框架）、S24/25、vivo X100/200 | 最新 API、厂商省电策略下前台服务存活 |
| 折叠 / 平板 | Z Fold、Magic V、平板 | 可选，布局自适应 |

**最低覆盖建议**：1 台 Android 12–15 中端机 + 1 台 Android 5/6 老机（权限与 minSdk）+ 1 台华为鸿蒙双框架机（前台服务保活）。

### 1.3 厂商策略重灾区（本项目强相关）

模拟位置依赖**原生前台服务 + WakeLock** 保活，以下机型的省电策略会主动冻结后台：

| 厂商 | 现象 | 建议 |
|------|------|------|
| 华为 / 鸿蒙 | 「应用启动管理」自动管理会冻结后台服务 | 关闭自动管理、允许后台活动；本工程已用 `PARTIAL_WAKE_LOCK` + `FOREGROUND_SERVICE_TYPE_LOCATION` |
| 小米 / 红米 | 神隐模式限制后台 | 设置「无限制」+ 锁定后台任务 |
| OPPO / vivo | 后台冻结 | 允许自启动 / 后台运行 |
| 三星 | 省电模式降低定位频率 | 关闭省电模式测试 |

---

## 2. 鸿蒙 HarmonyOS

| 版本 | 形态 | 说明 |
|------|------|------|
| HarmonyOS 3.1 / 4.x（双框架） | 兼容 Android APK | 华为 P60 等：**可直接安装运行本工程的 Android APK**，首期主测路线 |
| HarmonyOS 2 / 3（过渡） | 部分兼容 | 视具体机型，未纳入 |
| HarmonyOS NEXT 5.x | 纯鸿蒙（无 AOSP） | **未适配**：需 Flutter 鸿蒙分支 + 高德鸿蒙 SDK |
| OpenHarmony 4.x / 5.x | 开源基线 | 同 NEXT 路线，未适配 |

**现状**：项目内**没有 `ohos/` 工程**，也**未引入高德鸿蒙 SDK**；`csp_amap_flutter_map` 的 pubspec 虽声明 `ohos` 平台，
但鸿蒙侧需另行提供插件实现（Gitee 完整版）后才能编译。

---

## 3. iOS

| iOS 版本 | 适配建议 |
|----------|----------|
| 13 及以上 | 工程 `IPHONEOS_DEPLOYMENT_TARGET = 13.0` |
| 15 / 16 | 适配 |
| 17 / 18 / 19 | 主测（未来接入时） |

**现状（未接入）**：

- `ios/` 下**没有 `Podfile`**，主工程未集成高德 `AMap3DMap`（仅 `vendor/csp_amap_flutter_map` 的 podspec 声明了依赖，平台 iOS 12+）。
- `ios/Runner/Info.plist` **缺少** `NSLocationWhenInUseUsageDescription` 等定位权限描述。
- `AppDelegate.swift` 未配置高德 iOS Key。
- 原生 mock 通道（`show_location/mock`）**只在 Android 存在**，iOS 上相关调用返回失败语义（不崩溃）。

**约束**：iOS 真机调试 / 上架需 Apple Developer 付费账号（¥688/年）。

---

## 4. 首期测试矩阵

| 平台 | 系统 | 机型示例 | 验证项 |
|------|------|----------|--------|
| Android 原生 | 13 / 14 / 15 | 小米 / 荣耀 / 三星 | 全功能：地图、搜索、收藏、模拟、探针、反推校准 |
| Android 原生 | 5.x / 6.x | 红米 9A | 安装、权限弹窗、地图加载（minSdk 回归） |
| 鸿蒙双框架 | HarmonyOS 3.1 / 4.x | 华为 P60 | 高德 Android SDK 在兼容层下的定位 / 渲染 / 前台服务保活 / mock 生效 |
| 桌面 | Windows | 本机 | UI 可启动，mock 相关提示降级（非崩溃） |
| iOS | — | — | **暂不纳入**（未接入） |

---

## 5. 华为 P60 真机调试

P60（鸿蒙双框架）是首期主测机，详细的开发者选项、驱动安装、日志与验证要点见
[`docs/华为P60.md`](docs/华为P60.md)。要点速览：

1. 开启开发者选项 + USB 调试；驱动装 HiSuite。
2. 开发者选项 → **选择模拟位置应用** → 选中 `showlocation`（模拟功能的前提）。
3. `adb install -r build/app/outputs/flutter-apk/app-debug.apk`，日志过滤 `amap|location|flutter|mock`。
4. 关闭「应用启动管理」自动管理，避免前台服务被冻结。
5. 验证重点：定位权限弹窗、绿车标、地图渲染、**模拟生效与前台服务通知存活**、反推校准收敛情况。

---

## 6. 参考资料

- Android API 级别：https://developer.android.com/tools/release-platforms
- 高德 Android SDK：https://developer.amap.com/api/android-sdk/summary
- 高德定位 SDK（错误码）：https://developer.amap.com/api/android-location-sdk/guide/utilities/errorcode
- Flutter 平台支持：https://docs.flutter.dev/reference/supported-platforms
