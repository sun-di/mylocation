# Mock Location（修改系统位置）功能说明与排查手册

> 版本：v1.1 ｜ 更新日期：2026-09-20 ｜ 平台：**仅 Android**（iOS / 桌面降级为不可用）
>
> 本功能通过 Android 原生 `LocationManager.addTestProvider` 注册 **Test Provider**，
> 由**前台服务**持续注入伪造的 GPS fix，使其他 APP（高德、百度、微信、打卡类等）读到的是你设定的位置。

---

## 1. 名词约定

| 缩写 | 含义 |
|------|------|
| **UL** | User Location：用户在地图上选中的点（主观意图）——蓝扎标 |
| **ML** | Mock Location：**实际注入系统**的坐标；反推校准会迭代调整它 —— 红车标 |
| **AL** | AMap Location：**高德定位 SDK 看到的**位置（可能被反 mock / 风控加工）—— 紫扎标 |

> 「反推校准」的目标就是让 AL 尽量等于 UL：通过调整 ML 来抵消对方 SDK 的反 mock 处理。

---

## 2. 工作原理

```
┌───────────────────────────────┐   MethodChannel    ┌──────────────────────────────────────┐
│ Flutter                       │  "show_location/   │ Android 原生                          │
│  HomePage（UI / 编排）         │ ─── mock" ───────▶ │  MainActivity.kt                     │
│  MockController              │                    │   · 权限检查 / 跳开发者选项            │
│   · MockState 状态机          │                    │   · setAmapApiKey / startMock 等      │
│   · runCalibration 反推循环   │                    │   · requestRealLocation（真实定位）    │
│  MockService（Dart 桥）       │                    │   · requestAmapLocation（AL 探针）     │
└───────────────────────────────┘                    │  MockLocationService.kt（前台服务）    │
                                                     │   · startForeground + WakeLock        │
                                                     │   · 500ms 推送循环（GPS + NETWORK）    │
                                                     └────────────────┬─────────────────────┘
                                                                      │ setTestProviderLocation
                                                                      ▼
                                            系统 LocationManager（Test Provider）
                                                     │  ┌────────────────────────────────┐
                                                     └─▶│ 第三方 APP 读到注入位置            │
                                                        │ 高德定位 SDK（AL 探针）读到"加工后"位置 │
                                                        └────────────────────────────────┘
```

关键点：**推送循环在原生前台服务里跑**（`ScheduledExecutorService`），Dart 层不再持有 `Timer`，
因此退后台 / 熄屏不会被 ROM 冻结（配合 `PARTIAL_WAKE_LOCK`）。

---

## 3. MethodChannel 契约（`show_location/mock`）

| 方法 | 参数 | 说明 |
|------|------|------|
| `isMockEnabled` | — | 是否已授予「模拟位置应用」（`AppOpsManager.OPSTR_MOCK_LOCATION`） |
| `openDevOptions` | — | 跳转「开发者选项」，让用户选择本 APP |
| `setAmapApiKey` | `key` | 把高德 Key 传给定位 SDK（`initWithContext` 时由 Dart 侧调用一次） |
| `startMock` | `lat,lng,mirrorToNetwork=true` | **启动前台服务并持续推送（当前主路径）** |
| `updateMockTarget` | `lat,lng` | 更新推送目标（反推校准每轮调用） |
| `stopMock` | — | 停止前台服务 |
| `readRealLocation` | — | 被动读 `getLastKnownLocation(GPS)` 缓存 |
| `requestRealLocation` | — | 主动请求一帧真实 fix（8s 超时） |
| `requestAmapLocation` | — | AL 探针：`AMapLocationClient` 单次定位（8s 超时） |

非 Android 平台调用会抛 `MissingPluginException`，`MockService` 已捕获并返回失败语义（不崩溃）。

---

## 4. 注入的 fix 长什么样

| 项 | 取值 | 目的 |
|----|------|------|
| 推送间隔 | 500ms | 用高密度压制真实 GPS 输出 |
| `provider` | `gps`，可镜像到 `network` | 反制"双 Provider 校验回退"策略 |
| `elapsedRealtimeNanos` | **严格单调递增**（不足则 +500ms） | 部分 SDK 会丢弃时间戳回退的 fix |
| `time` | 每次刷新的 `currentTimeMillis` | 避免被判为过期数据 |
| `accuracy` | 5f | 表现成正常 GPS 精度 |
| `speed` / `bearing` | 3f / `(pushCount × 0.5) % 360` | 表现成"正在移动"的连续轨迹，避免静止 fix 被忽略 |
| `extras` | `satellites=8`、`maxCn0=40`、`distance`（累计）、`bearing` | 部分 SDK 读这些字段判断信号质量与连续性 |
| `setTestProviderStatus`（P+） | 上报 8 颗星 | 让定位服务认为 GPS 有有效卫星 |

---

## 5. 一次性设置（每个用户只需做一次）

1. `设置 → 关于手机 → 版本号` 连点 **7 次**，开启开发者选项。
2. `设置 → 系统 → 开发者选项`（不同 ROM 路径略有差异）。
3. 找到 **「选择模拟位置应用」**（部分 ROM 叫 "Mock location app" / "允许模拟位置"）。
4. 在列表中选择 **showlocation**。
5. 回到 APP，再次点击 **「应用到系统」**。

> 未完成第 3~4 步时，APP 会自动跳到该设置页并提示，不会静默失败。

## 6. 使用流程

1. 在地图上 **点击 / 长按**（或用顶部搜索）选中一个点 → 出现「已选位置」气泡。
2. 点击底部 **「应用到系统」**，APP 会：

```
① 检查"模拟位置应用"授权 → 未授权：跳开发者选项 + 错误对话框
② startMock → 前台服务 startForeground + 注册 Test Provider + 启动 500ms 推送循环
③ UI：锁定地图手势、隐藏气泡、UL 处叠加红车标、弹出「模拟状态」对话框
④ 等约 1.75s 后跑 AL 探针（最多 3 轮，间隔 3s）→ 紫 pin + 偏差（米）
⑤ 若偏差 > 50m → 自动进入反推校准（最多 4 轮，每轮 6s）
```

3. 对话框标题从「准备中」变为 **「已就绪」** 即表示模拟生效（且无需/已完成校准）。
4. 打开第三方地图 APP，查看注入效果。
5. 点击 **「停止模拟」** → 停止前台服务、注销 Test Provider、解锁地图、清除探针；第三方 APP 恢复真实定位。

## 7. 反推校准（核心机制）

**公式**：第 *i* 轮注入 `ML_i = 2·UL − AL_{i-1}`

直觉：若对方把 ML "拉"到你真实位置的反方向，就反向再推等量的距离，从而抵消其处理。

| 参数 | 取值 | 说明 |
|------|------|------|
| 最大轮次 | 4 | 超过则报「达最大迭代次数，未收敛」 |
| 每轮间隔 | 6s | 等 SDK 重新分发 + 回调 |
| 收敛阈值 | 50m | 偏差 < 50m 即 success |
| 单步限幅 | 10km | `ML` 距 `UL` 超过 10km 时按比例截断（防止跨城跳跃被 map-matching 丢弃） |
| 停滞判定 | 连续两轮偏差变化 < 1m | 判为风控，退出 |
| 探针超时 | 5s | `readAlProbe` 单次等待 |
| 探针连续失败上限 | 2 次（第 1 轮宽容） | 判为风控/定位不可用 |

触发条件：**首轮偏差 > 50m** 才自动启动；≤ 50m 视为无需校准（对话框直接显示「已就绪」）。

## 8. UI 状态与反馈

- **「模拟状态」对话框**（`_MockStatusDialog`）实时显示：
  - 模拟状态：未启用 / 准备中… / 运行中（模拟位置已生效）/ 出错：原因
  - 位置校准：偏差米数（< 50m 绿、< 300m 橙、否则红），无值显示「探测中…」
  - 推理状态：未触发（偏差 ≤ 50m）/ 校准中 i/4… 偏差 x m / 推理完成，残余偏差 x m（推理前 y m）/ 未完成原因
- 对话框在 mock 启动后弹出，**mock 状态回到 idle 时自动关闭**，也可手动关闭（不影响模拟继续运行）。
- 地图扎标：绿车标（真实位置）/ 红车标（ML）/ 蓝 pin（UL，未模拟时）/ 紫 pin（AL 探针）。
- 模拟期间地图**锁定**（禁手势 + 禁点选），避免误操作改变选点。

## 9. 已知限制

| 项 | 说明 |
|----|------|
| 第三方 APP 反 Mock | 高德等通过 `Location.isFromMockProvider()` 与多源校验识别 mock 并降权（只给城市级 / 标注不可信）。本项目的反推校准**只能逼近，无法保证 100% 生效**，这是系统级限制（需 ROOT / 系统级方案） |
| 首次定位仍走真实源 | 「回到当前位置」「显示当前位置」在模拟期间被禁用，避免把 ML 当作真实位置展示 |
| 前台服务通知 | Q+ 必须显示常驻通知（`FOREGROUND_SERVICE_LOCATION`），属系统要求，不可去掉 |
| ROM 冻结 | 华为 / 小米 / OPPO / vivo 需手动加入白名单并关闭省电限制，详见 [`../../supported_devices.md`](../../supported_devices.md) |
| 平台限制 | 仅 Android。鸿蒙 NEXT（纯鸿蒙）需重新实现原生层；iOS 需 Xcode 的 Location 模拟或真机签名方案；桌面不支持 |
| 多 APP 同时模拟 | 系统只允许一个 Test Provider 写入者，其他 mock 工具会与本 APP 冲突 |

## 10. 故障排查

| 现象 | 排查方向 |
|------|----------|
| 点「应用到系统」无反应 | 是否在开发者选项里选中了本 APP；`adb logcat \| grep -i mock` 看原生报错 |
| 报 `SecurityException: not allowed to access` | 未获「模拟位置应用」授权；或 ROM 把入口藏得更深 |
| 报 Provider 已存在 / 状态残留 | 上次未正常停止：重启 APP，或 `adb shell appops set com.example.showlocation MOCK_LOCATION allow` 后重试 |
| 第三方 APP 仍显示真实位置 | ① 开发者选项设置做了吗；② 是否有其他 mock 工具在抢 Provider；③ 大概率是对方反 Mock 降权（预期行为，非本工程 Bug） |
| 状态框一直「准备中」/ 偏差不刷新 | 探针没拿到 AL：检查网络定位、高德 Key 是否绑定当前签名；看日志 `[AMap] onLocationChanged` 是否出现 |
| 偏差始终收敛不下来 | 对方风控：对话框会显示「疑似风控」；可停止后重试，或换更接近真实位置的点 |
| 后台几分钟后 mock 断了 | ROM 冻结：把 APP 加入电池 / 后台白名单（华为见 [`../../docs/华为P60.md`](../../docs/华为P60.md) 第 7 节） |
| 地图空白但 mock 正常 | 高德 Key 未绑定当前签名 SHA1 / 包名 |

## 11. 文件结构

```
android/app/src/main/AndroidManifest.xml                     # 权限 + <service .MockLocationService foregroundServiceType="location">
android/app/src/main/kotlin/.../MainActivity.kt              # MethodChannel 9 方法 + 真实定位 + AL 探针
android/app/src/main/kotlin/.../MockLocationService.kt       # 前台服务：500ms 推送循环 + WakeLock + 通知
lib/mock_location/mock_service.dart                          # Native bridge（Dart → Android）
lib/mock_location/mock_controller.dart                       # MockState 状态机 + runCalibration 反推 control loop
lib/mock_location/mock_location_zh.md                        # 本文档
lib/pages/home_page.dart                                     # 「应用到系统」/「停止模拟」+ 状态对话框集成
```

> ⚠️ 不要给 `<application>` 加 `android:mockLocation="true"`：该属性并非 Android 官方属性，AAPT 会报错。
> 授权完全依赖 `<uses-permission android:name="android.permission.ACCESS_MOCK_LOCATION">` +
> 开发者选项选定本 APP + `AppOpsManager.OPSTR_MOCK_LOCATION` 校验。
