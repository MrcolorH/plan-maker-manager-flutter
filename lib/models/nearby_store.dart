/// 周边实体餐饮店铺模型与定位信息
library;

class NearbyStore {
  final String name;
  final String address;
  final int distanceMeters;
  final String type;
  final double? latitude;
  final double? longitude;

  const NearbyStore({
    required this.name,
    this.address = '',
    this.distanceMeters = 0,
    this.type = '快餐/便餐',
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'distanceMeters': distanceMeters,
    'type': type,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
  };

  factory NearbyStore.fromJson(Map<String, dynamic> json) {
    return NearbyStore(
      name: (json['name'] as String?)?.trim() ?? '',
      address: (json['address'] as String?)?.trim() ?? '',
      distanceMeters: int.tryParse(json['distance']?.toString() ?? '') ??
          (json['distanceMeters'] as num?)?.toInt() ??
          0,
      type: (json['type'] as String?)?.trim() ?? '快餐/便餐',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  /// 格式化标签显示（如："老乡鸡 180m"）
  String get displayTag {
    if (distanceMeters > 0) {
      if (distanceMeters < 1000) {
        return '$name ${distanceMeters}m';
      } else {
        return '$name ${(distanceMeters / 1000.0).toStringAsFixed(1)}km';
      }
    }
    return name;
  }
}

class NearbyLocation {
  final double latitude;
  final double longitude;
  final String cityName;
  final String districtName;
  final String address;

  const NearbyLocation({
    required this.latitude,
    required this.longitude,
    this.cityName = '',
    this.districtName = '',
    this.address = '',
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'cityName': cityName,
    'districtName': districtName,
    'address': address,
  };

  factory NearbyLocation.fromJson(Map<String, dynamic> json) {
    return NearbyLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      cityName: json['cityName'] as String? ?? '',
      districtName: json['districtName'] as String? ?? '',
      address: json['address'] as String? ?? '',
    );
  }

  String get shortLabel {
    if (districtName.isNotEmpty) return '$cityName·$districtName';
    if (cityName.isNotEmpty) return cityName;
    return '已定位周边';
  }
}
