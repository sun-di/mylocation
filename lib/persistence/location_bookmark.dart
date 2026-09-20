import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化的"收藏位置"。
///
/// 由 [LocationBookmarks] 管理：新增 / 删除 / 全量读取。
/// 只持久化展示所需的最小字段（id/name/lat/lng/address/savedAt），
/// 道路/省市区等冗余信息重新逆地理编码也会变化，没必要缓存。
class LocationBookmark {
  /// 唯一 id（用时间戳 + 随机段自生成）。
  final String id;
  /// 用户命名。空字符串由 UI 回退到 address / 经纬度展示。
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime savedAt;

  const LocationBookmark({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.savedAt,
  });

  /// 列表展示文案（优先 name，其次 address，最后经纬度）。
  String get displayText {
    if (name.isNotEmpty) return name;
    if (address != null && address!.isNotEmpty) return address!;
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'savedAt': savedAt.toIso8601String(),
      };

  factory LocationBookmark.fromJson(Map<String, dynamic> j) => LocationBookmark(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        address: j['address'] as String?,
        savedAt: DateTime.tryParse((j['savedAt'] as String?) ?? '') ??
            DateTime.now(),
      );

  /// 工厂：自动生成 id + savedAt = now()。
  /// name 默认 = 当前点的 displayText（UI 可在保存时改名，目前默认展示取自 LocationInfo.displayText）。
  factory LocationBookmark.create({
    required double latitude,
    required double longitude,
    String name = '',
    String? address,
  }) {
    // 12 位时间戳 + 4 位随机段 → 简单粗暴但足够本地去重。
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = (ts * 31 + latitude.abs().toInt() * 17) & 0xFFFF;
    return LocationBookmark(
      id: '$ts-${rnd.toRadixString(16).padLeft(4, '0')}',
      name: name,
      latitude: latitude,
      longitude: longitude,
      address: address,
      savedAt: DateTime.now(),
    );
  }
}

/// "收藏位置"仓库：本地 SharedPreferences 存储，JSON 编码整 List。
///
/// 不再交给 Isolate / 单独的 service 层 —— 数据量小（典型 < 100 条）
/// 且读写都在 UI 主线程 fire-and-forget，时延可接受。
class LocationBookmarks {
  /// 最大条数 = 10。超过则 [add] 抛 [StateError] 让 UI 提示。
  static const int maxCount = 10;

  /// key 版本号 `_v1`：将来加字段时升 `_v2` + 迁移。
  static const String _key = 'location_bookmarks_v1';

  /// "启动时自动应用"书签 id 的 key（全局只能有一个）。
  static const String _alwaysKey = 'location_bookmarks_always_id_v1';

  /// 全量读取，按 savedAt 倒序（最新在前）。
  static Future<List<LocationBookmark>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final out = list.map(LocationBookmark.fromJson).toList();
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (_) {
      // 解析失败/缺字段都视为空列表，避免页面崩溃。
      return const [];
    }
  }

  static Future<void> _saveAll(List<LocationBookmark> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(all.map((b) => b.toJson()).toList()),
    );
  }

  /// 添加（追加到末尾，不去重）。
  ///
  /// 已达到 [maxCount] 上限时抛 [StateError] —— 由调用方决定是
  /// snackbar 提示"已达上限"还是别的兜底。
  static Future<void> add(LocationBookmark b) async {
    final all = await readAll();
    if (all.length >= maxCount) {
      throw StateError('已达到 $maxCount 个收藏上限');
    }
    final next = all.toList()..add(b);
    await _saveAll(next);
  }

  /// 按 id 删除。id 不存在时静默无操作。
  static Future<void> delete(String id) async {
    final all = (await readAll()).toList()..removeWhere((b) => b.id == id);
    await _saveAll(all);
  }

  /// 清空（调试 / 重置按钮可用）。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_alwaysKey);
  }

  /// 读取当前"启动时自动应用"的书签 id（无则 null）。
  static Future<String?> readAlwaysId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_alwaysKey);
  }

  /// 写入（或清除）"启动时自动应用"的书签 id。传 null 表示取消勾选。
  static Future<void> writeAlwaysId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_alwaysKey);
    } else {
      await prefs.setString(_alwaysKey, id);
    }
  }
}
