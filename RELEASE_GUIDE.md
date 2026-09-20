# ShowLocation 全周期指南（环境 → 编码 → 验证 → 发布）

> 版本：v1.1 ｜ 更新日期：2026-09-20 ｜ 读者：不熟悉构建 / 发布的开发者
> 本文档早期版本为「设计阶段概览」（写于本机尚未安装 Flutter 时）。现已按**实际进度与真实版本**重写。

---

## 0. 当前进度快照

| 阶段 | 内容 | 状态 |
|------|------|------|
| 阶段 0 | 环境搭建（Flutter / Android SDK / JDK 17） | ✅ 已完成 |
| 阶段 1 | 编码实现（Android：地图 / 搜索 / 收藏 / 模拟位置 / 反推校准） | ✅ 已完成 |
| 阶段 2 | 本地验证（`flutter analyze`、debug APK 真机运行） | ✅ 已完成 |
| 阶段 3 | Android 发布（签名、加固 Key、隐私合规、上架） | ⬜ 未开始（发布为可选，本工具定位为自用） |
| 阶段 4 | 鸿蒙 / iOS 适配 | ⬜ 未开始（鸿蒙双框架机型可直接跑 Android APK） |

```
阶段 0 环境搭建 ─✅─▶ 阶段 1 编码 ─✅─▶ 阶段 2 真机验证 ─✅─▶ 阶段 3 发布（未做）
                                                      └─▶ 阶段 4 鸿蒙/iOS 适配（未做）
```

---

## 1. 阶段 0：环境（已完成，供换机复现）

| 工具 | 要求 | 说明 |
|------|------|------|
| Git | 任意近版 | 仓库：`https://github.com/sun-di/FakeLocation`（分支 `main`） |
| Flutter | stable，**≥ 3.44** | `pubspec.lock` 要求 Flutter `>=3.44.0`、Dart `>=3.12.0`（`pubspec.yaml` 自身约束 `>=3.3.0 <4.0.0`） |
| JDK | **17** | 工程 `compileOptions` 与 Kotlin `jvmTarget` 均为 JVM 17 |
| Android SDK | platform-tools + build-tools | `compileSdk/minSdk/targetSdk` 取 Flutter 模板占位符，未硬编码 |
| 真机 | Android 6.0+ | 模拟位置功能**必须真机**（模拟器无意义） |

```bash
git clone https://github.com/sun-di/FakeLocation.git
cd FakeLocation
flutter doctor                 # 期望 Android toolchain 全绿
flutter pub get

# 配置高德 Key（不入库，构建期注入）
copy keys\dart_define.example.json keys\dart_define.json
# 填入 AMAP_ANDROID_KEY / AMAP_IOS_KEY / AMAP_WEB_KEY
flutter run --dart-define-from-file=keys/dart_define.json
```

**构建链实际版本**（`android/`）：

| 项 | 版本 | 位置 |
|----|------|------|
| Gradle wrapper | **8.14.3**（腾讯云镜像） | `android/gradle/wrapper/gradle-wrapper.properties` |
| AGP | **8.11.1** | `android/settings.gradle.kts`（vendor 插件 buildscript 同步为 8.11.1） |
| Kotlin | **2.2.20** | 同上 |
| JVM 参数 | `-Xmx8G -XX:MaxMetaspaceSize=4G` | `android/gradle.properties` |

> 这三项原先分别是 8.9 / 8.7.3 / 2.1.0，已被 Flutter 警告「即将不再支持」，现已升级到官方建议的下限之上。

---

## 2. 阶段 1：编码（已完成）

模块与文件清单见 [`docs/architecture.md`](docs/architecture.md) 第 4 节；需求对照见 [`docs/requirements.md`](docs/requirements.md)。

核心能力：地图选点 / 搜索联想 / 逆地理 / 收藏与历史 / 真实定位 / 模拟位置注入（前台服务）/ AL 探针 / 反推校准。

---

## 3. 阶段 2：本地验证（已完成，日常就用这几条）

```bash
# 运行/构建请带上 Key 注入文件（否则地图空白，App 会弹提示）
flutter analyze                       # 静态检查（应 0 error）
flutter test                          # 当前仅占位 smoke test
flutter run --dart-define-from-file=keys/dart_define.json           # 真机调试
flutter build apk --debug --dart-define-from-file=keys/dart_define.json
# 产物：build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# 日志排查（定位 / 高德 / 模拟 / 崩溃）
adb logcat | grep -i -E "amap|location|flutter|mock|AndroidRuntime"
```

**首轮验收清单**（对应 `docs/requirements.md` FR-1~FR-9）：

1. 冷启动 → 弹出定位权限 → 5s 内出绿车标，地图跳到当前位置。
2. 点击 / 长按地图 → 出现「已选位置」气泡（名称 + 6 位小数经纬度 + 地址）；滚动地图气泡消失。
3. 顶部搜索「天安门」→ 出现联想候选；点选后跳图并可保存。
4. 保存 3 条 → 历史页展开行，Go / Run / Delete / always 均生效；重启后数据仍在。
5. 开发者选项里选中 `showlocation` → 「应用到系统」→ 通知栏出现前台服务通知；
   状态对话框显示「准备中 → 已就绪」，「位置校准」偏差数值刷新。
6. 打开第三方地图 APP，确认读到注入位置；反推校准时观察残余偏差是否收敛到 < 50m。
7. 「停止模拟」→ 对话框关闭、地图解锁、第三方 APP 恢复真实定位。
8. 华为 / 小米机型额外验证：熄屏或切后台 2 分钟后 mock 仍持续（前台服务 + WakeLock 保活）。

---

## 4. 阶段 3：Android 发布（未开始）

### 4.1 发布前必须完成的加固（P0）

| # | 事项 | 说明 |
|---|------|------|
| 1 | **轮换高德 Key（唯一未完成项）** | 源码已改为构建期注入（见下），但**历史提交中的旧 Key 仍可被检索到**，必须去高德控制台删除旧 Key 并重新生成 |
| 2 | ~~Key 改为构建期注入~~ | ✅ 已完成：`String.fromEnvironment` + `--dart-define-from-file=keys/dart_define.json`（模板 `keys/dart_define.example.json`，真实文件已 gitignore） |
| 3 | **签名密钥** | 生成 keystore（如 `upload-keystore.jks`）+ `android/key.properties`（已在 `.gitignore` 中排除）。当前 `android/app/build.gradle.kts` 的 `release` 仍沿用 **debug 签名**（模板 TODO），可本地跑通但**不能用于分发** |
| 4 | **高德后台绑定发布签名 SHA1** | 否则发布包地图空白 |
| 5 | **隐私合规** | 当前 `updatePrivacyAgree(hasAgree: true)` 为**默认视为同意**；上架前必须改为先弹隐私政策、按用户选择再初始化 SDK |
| 6 | ~~清理冗余~~ | ✅ 已完成：移除未使用的 `clipboard` / `fluttertoast`（含 iOS 注册文件同步清理）；删除历史日志 `docs/error.txt` |

### 4.2 构建与签名（步骤概览）

```bash
# 1) 生成 keystore
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2) 写 android/key.properties（不入库）
#    storePassword=... / keyPassword=... / keyAlias=upload / storeFile=../upload-keystore.jks
#    并在 android/app/build.gradle.kts 中读取 signingConfigs（当前模板尚未配置）

# 3) 构建
flutter build apk --release         # 直装分发
flutter build appbundle --release   # 商店上架（AAB）
```

### 4.3 分发注意

- 本工具**依赖「模拟位置应用」授权**，上架主流商店存在**合规风险**（多数商店限制修改系统位置类应用）；
  发布前请评估目标渠道政策，或仅内部 / 侧载分发。
- 应用信息：包名 `com.example.showlocation`（若上架需改为自有域名反写）、应用名 `showlocation`。

---

## 5. 阶段 4：鸿蒙 / iOS 适配（未开始）

| 平台 | 待办 |
|------|------|
| 鸿蒙双框架（P60 类） | 无需改造，直接安装 Android APK；需在系统里关闭「应用启动管理」自动管理（见 [`docs/华为P60.md`](docs/华为P60.md)） |
| HarmonyOS NEXT / OpenHarmony | Flutter 鸿蒙分支编译 + 高德鸿蒙 SDK；`csp_amap_flutter_map` 的鸿蒙实现需换 Gitee 完整版；经 `MapStrategy` 接入，页面零改动 |
| iOS | 生成 `Podfile`（iOS 12+）、`Info.plist` 补 `NSLocationWhenInUseUsageDescription`、配置高德 iOS Key（BundleId 绑定）、补 mock 通道（或直接降级隐藏该功能） |

---

## 6. 风险清单（持续更新）

| 项 | 提醒 |
|----|------|
| Key 泄露 | 已发生的既成事实：**先轮换再谈其他**；改注入方式后 `git log` 中的旧 Key 依然可见，只能靠后台重置 |
| 签名丢失 | keystore 务必备份（丢失将无法更新已上架应用） |
| 反 Mock 限制 | 第三方 APP 可通过 `isFromMockProvider` 降权，本项目只能「逼近」；文档已明示，避免误判为 Bug |
| ROM 冻结后台 | 前台服务 + WakeLock 已做，仍建议加入系统白名单（详见 [`supported_devices.md`](supported_devices.md) 1.3） |
| Key 未注入就跑构建 | `flutter run/build` 忘记带 `--dart-define-from-file` 时地图空白（App 会弹 SnackBar 提示），不是 Bug |
| 构建工具再升级 | Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20 已满足当前 Flutter 要求；后续升级 Flutter 时需同步评估 |
| 单测缺失 | 重构反推逻辑前建议先补单测（`MockController` 的参数化逻辑适合纯 Dart 测试） |

---

## 7. 下一步建议（按优先级）

1. **P0**：去高德控制台**删除并重新生成 Key**（历史 Key 已泄露），新 Key 只放本地 `keys/dart_define.json`。
2. **P0**：本地 `copy keys\dart_define.example.json keys\dart_define.json` 并填好 3 个 Key，验证地图与搜索正常。
3. **P1**：补 `MockController`（反推公式 / 收敛判定 / Haversine）单元测试。
4. **P1**：接入隐私政策弹窗（替换 `updatePrivacyAgree` 默认同意）。
5. **P2**：按模块拆分 `home_page.dart`；同步 `_run.ps1` / `_diag.ps1` 的过时版本注释。
6. **P3**：按需推进 iOS / 鸿蒙适配与发布流程。

> 已完成项：Key 构建期注入、移除冗余依赖、删除历史构建日志、升级 Gradle/AGP/Kotlin。
