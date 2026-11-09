import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/nearby_store.dart';
import 'package:jianfei_dazi/services/nearby_service.dart';

void main() {
  group('周边实体餐饮店铺模型与检索测试', () {
    test('NearbyStore 数据解析与距离格式化准确', () {
      const store1 = NearbyStore(
        name: '老乡鸡(科兴店)',
        address: '高新南一道10号',
        distanceMeters: 180,
        type: '快餐',
      );
      expect(store1.displayTag, '老乡鸡(科兴店) 180m');

      const store2 = NearbyStore(
        name: '麦当劳(科技园店)',
        distanceMeters: 1250,
      );
      expect(store2.displayTag, '麦当劳(科技园店) 1.3km');

      final json = {
        'name': '黄焖鸡米饭',
        'address': '美食街101号',
        'distance': '350',
        'type': '地方小吃',
      };
      final parsed = NearbyStore.fromJson(json);
      expect(parsed.name, '黄焖鸡米饭');
      expect(parsed.distanceMeters, 350);
      expect(parsed.displayTag, '黄焖鸡米饭 350m');
    });

    test('NearbyLocation 能够正确生成简短区域标签', () {
      const loc1 = NearbyLocation(
        latitude: 22.54,
        longitude: 113.93,
        cityName: '深圳市',
        districtName: '南山区',
      );
      expect(loc1.shortLabel, '深圳市·南山区');

      const loc2 = NearbyLocation(
        latitude: 39.90,
        longitude: 116.40,
        cityName: '北京市',
      );
      expect(loc2.shortLabel, '北京市');
    });

    test('NearbyService mockHandler 注入测试', () async {
      NearbyService.instance.mockLocationHandler = () async {
        return const NearbyLocation(
          latitude: 22.5431,
          longitude: 113.9388,
          cityName: '深圳市',
          districtName: '粤海街道',
        );
      };

      NearbyService.instance.mockRestaurantsHandler = (lat, lon, kw) async {
        return const [
          NearbyStore(name: '老乡鸡', distanceMeters: 150),
          NearbyStore(name: '肯德基', distanceMeters: 280),
          NearbyStore(name: '黄焖鸡米饭', distanceMeters: 420),
        ];
      };

      final loc = await NearbyService.instance.getCurrentLocation();
      expect(loc, isNotNull);
      expect(loc!.cityName, '深圳市');
      expect(loc.districtName, '粤海街道');

      final stores = await NearbyService.instance.searchNearbyRestaurants();
      expect(stores.length, 3);
      expect(stores[0].name, '老乡鸡');
      expect(stores[0].distanceMeters, 150);
      expect(stores[1].name, '肯德基');

      // 清理 mock
      NearbyService.instance.mockLocationHandler = null;
      NearbyService.instance.mockRestaurantsHandler = null;
    });

    test('NearbyService 默认兜底店铺列表完整且有距离', () async {
      final stores = await NearbyService.instance.searchNearbyRestaurants();
      expect(stores.isNotEmpty, isTrue);
      expect(stores.any((s) => s.name.contains('肯德基')), isTrue);
      expect(stores.any((s) => s.name.contains('黄焖鸡')), isTrue);
      expect(stores.every((s) => s.distanceMeters > 0), isTrue);
    });
  });
}
