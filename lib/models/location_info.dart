/// 位置信息模型：包含经纬度、道路、区域、省市等层级信息
class LocationInfo {
  final double latitude;
  final double longitude;
  final String? province; // 省
  final String? city; // 市
  final String? district; // 区/县
  final String? road; // 道路名
  final String? address; // 详细地址（逆地理编码结果）
  final String? name; // POI 名称（关键字搜索命中的地点名，如"天安门"）

  const LocationInfo({
    required this.latitude,
    required this.longitude,
    this.province,
    this.city,
    this.district,
    this.road,
    this.address,
    this.name,
  });

  /// 生成文本框展示用的位置文案。
  /// 优先 POI 名称（关键字搜索结果），其次详细地址，再回退省市区，最后经纬度。
  String get displayText {
    if (name != null && name!.isNotEmpty) return name!;
    if (address != null && address!.isNotEmpty) return address!;
    final parts = [province, city, district, road]
        .where((e) => e != null && e.isNotEmpty)
        .join(' ');
    if (parts.isNotEmpty) return parts;
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  LocationInfo copyWith({
    double? latitude,
    double? longitude,
    String? province,
    String? city,
    String? district,
    String? road,
    String? address,
    String? name,
  }) {
    return LocationInfo(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      province: province ?? this.province,
      city: city ?? this.city,
      district: district ?? this.district,
      road: road ?? this.road,
      address: address ?? this.address,
      name: name ?? this.name,
    );
  }
}
