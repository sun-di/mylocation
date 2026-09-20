# 三方地图 SDK 选型评估（含最终落地结论）

> 版本：v1.1 ｜ 更新日期：2026-09-20 ｜ 状态：已落地（高德 + 社区维护插件 + 本地 vendor 覆盖）

---

## 1. 比较维度

目标：在 Flutter 跨平台 App 中加载地图、显示定位、拾取位置、标记，并**允许读取「SDK 视角下的位置」**（本项目反 mock 需要）。

| 维度 | 高德 AMap | 百度 BaiduMap | 腾讯 TencentMap |
|------|-----------|---------------|-----------------|
| 计费模式 | 个人 / 企业免费（含配额），商用按 QPS 阶梯 | 免费额度 + 超额计费 | 免费额度 + 超额计费 |
| Flutter 插件 | 官方 `amap_flutter_map`（长期未更新）+ 社区 `csp_amap_flutter_map`（活跃，兼容 AGP8） | 官方 `flutter_baidu_mapapi_map`（更新较慢） | 第三方 `tencent_map`（生态弱） |
| 独立定位 SDK | ✅ `AMapLocationClient`（可单独拿"高德视角"位置，反 mock 观测关键） | 有 | 有 |
| 逆地理编码 | ✅ Web REST `geocode/regeo`（免费、字段全） | 内置 | 内置 |
| 关键字联想 | ✅ Web REST `assistant/inputtips`（对泛词友好） | 一般 | 一般 |
| 包体积影响 | 中（本项目用整合包 `3dmap-location-search`） | 大（含导航等模块） | 中 |
| 文档 / 示例 | 完善、中文友好 | 一般 | 一般 |
| 鸿蒙适配 | 有鸿蒙版 SDK（AMap-Harmony） | 有鸿蒙版 | 有鸿蒙版 |

---

## 2. 成本评估

- **直接成本**：三家对个人开发者均免费，申请 Key 无费用。高德 Web 服务有日调用配额（个人 Key 量级足够本项目）。
- **间接成本（开发）**：高德文档最全、插件生态最成熟，调试成本最低；百度初始化配置繁琐（隐私协议参数多）；
  腾讯 Flutter 资料少，往往需要自建 Platform Channel。

---

## 3. 最终结论（已落地）

**采用高德地图**，但**不使用 pub.dev 上的官方 `amap_flutter_map`**，而是：

1. **地图层**：社区维护的 `csp_amap_flutter_map`（1.1.1），并以**本地 path 依赖**方式引入（`vendor/csp_amap_flutter_map`）。
   - 原因 A：官方插件长期未更新，在新 AGP / compileSdk 下编译受阻；`csp` 版已适配 AGP8、compileSdk 35+。
   - 原因 B：需要**热修业务 bug** —— vendor 版修复了 `location2Map` 把**纬度校验误写成海拔校验**的问题。
     若不修，真实 GPS 海拔 > 90m 时 `onLocationChanged` 会被插件静默丢弃（地图永远拿不到定位）。
   - 因此**不要**把该依赖改回 pub.dev 版本（详见 `README.md` 第 7 节）。
2. **原生 SDK**：`com.amap.api:3dmap-location-search:10.1.200_loc6.4.9_sea9.7.4`（地图 + 定位 + 搜索整合包）。
   - 注意：整合包已含定位类，**不能**再单独添加 `com.amap.api:location`，否则出现 Duplicate class。
3. **Web 服务**：逆地理编码 `restapi.amap.com/v3/geocode/regeo`、输入提示 `restapi.amap.com/v3/assistant/inputtips`
   （使用独立的 **Web 服务 Key**，与 Android Key 分开申请）。
4. **AL 探针**：`AMapLocationClient`（高德独立定位 SDK）单次定位，配置
   `Hight_Accuracy` / `setOnceLocation(true)` / `setOnceLocationLatest(true)` / `setNeedAddress(false)` /
   `setLocationCacheEnable(false)` / **`setMockEnable(true)`** / `setHttpTimeOut(8000)`。
   - 用途：读取「其他高德系 APP 会看到的位置」，作为反推校准的观测值 AL。

**架构预留**：厂商隔离在 `lib/map/map_strategy.dart` 的 `MapStrategy` 抽象之后，
新增腾讯实现只需添加 `TencentStrategy implements MapStrategy`，页面层无需改动。

---

## 4. 风险提示（与现状对应）

| 风险 | 现状 / 应对 |
|------|-------------|
| Key 需按平台分别申请（Android 用包名 + 签名 SHA1，iOS 用 BundleId） | Key 经 `--dart-define-from-file=keys/dart_define.json` 注入（模板 `keys/dart_define.example.json`，真实文件已 gitignore）；源码已无明文 Key，**但历史提交中的旧 Key 视为泄露，需在高德控制台删除并重新生成** |
| 调试签名与发布签名 SHA1 不同 | 高德控制台需分别绑定，否则发布包地图空白 |
| 反 Mock 策略 | 高德会识别 `Location.isFromMockProvider` 并降权；本项目用「反推校准」逼近，效果不保证 |
| 鸿蒙端 | 需高德鸿蒙版 SDK + Flutter 鸿蒙分支，当前**未适配**（双框架机型可直接跑 Android APK） |
| 定位权限 | Android `ACCESS_FINE_LOCATION` + 运行时申请；iOS `NSLocationWhenInUseUsageDescription`（**尚未配置**） |
