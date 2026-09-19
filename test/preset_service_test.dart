import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jianfei_dazi/services/preset_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';

void main() {
  late PresetService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    service = PresetService(StorageService.instance);
  });

  test('PresetService saves and sorts presets by useCount and recency', () async {
    expect(service.getPresets(), isEmpty);

    final p1 = await service.savePreset(name: '水煮蛋2个', calories: 140, protein: 12, carbs: 1, fat: 10);
    final p2 = await service.savePreset(name: '鸡胸肉燕麦碗', calories: 420, protein: 40, carbs: 50, fat: 6);

    expect(service.getPresets().length, 2);
    expect(p2.name, '鸡胸肉燕麦碗');

    // 模拟使用 p1
    await service.recordPresetUsed(p1.id);

    final list = service.getPresets();
    expect(list.first.name, '水煮蛋2个');
    expect(list.first.useCount, 2);
    expect(list.first.protein, 12);
  });

  test('PresetService normalizes key and caches AI estimate results', () async {
    final rawDesc = '  香煎鸡胸肉一份，加糙米饭（无糖）  ';
    expect(service.getCachedAiEstimate(rawDesc), isNull);

    final aiResult = {
      'name': '香煎鸡胸肉佐糙米饭',
      'calories': 480,
      'protein': 42,
      'carbs': 52,
      'fat': 8,
      'detail': '鸡胸肉200g≈260, 糙米饭150g≈175, 橄榄油5g≈45',
    };

    await service.setCachedAiEstimate(rawDesc, aiResult);

    // 使用同义无标点描述读取
    final hit = service.getCachedAiEstimate('香煎鸡胸肉一份加糙米饭无糖');
    expect(hit, isNotNull);
    expect(hit!['calories'], 480);
    expect(hit['protein'], 42);
  });
}
