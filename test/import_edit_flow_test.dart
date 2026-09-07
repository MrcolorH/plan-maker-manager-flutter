/// 导入预览编辑流程核心逻辑测试（issue：AI 生成后看不到/改不了训练内容与食材做法）
/// 覆盖「预览编辑 → 确认导入」链路：import_page 现在用预览数据 toJson 导入
/// （而非原始 raw），保证训练内容 content / 食材 details / 做法 steps / 备注不丢、
/// 预览中的修改与删除真正生效。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/utils/plan_utils.dart';

/// 模拟导入页预览流：raw → normalizePlan（预览）→ 用户编辑 → preview.toJson()（确认导入）→ provider 再 normalize
PlanData previewThenImport(Map<String, dynamic> raw, void Function(PlanData preview) edit) {
  final preview = normalizePlan(raw);
  edit(preview);
  return normalizePlan(preview.toJson());
}

Map<String, dynamic> rawPlan() => {
      'version': '1.0',
      'meta': {'planName': '我的计划'},
      'meals': [
        {
          'id': 'm1',
          'type': 'lunch',
          'name': '荞麦面',
          'time': '12:00',
          'calories': 450,
          'details': [
            {'item': '荞麦面', 'amount': '100g'},
            {'item': '虾仁', 'amount': '80g'},
          ],
          'steps': ['煮面', '炒虾仁浇上'],
          'note': '先吃菜后吃面',
        }
      ],
      'exercises': [
        {
          'id': 'e1',
          'name': '下肢力量',
          'time': '18:30',
          'duration': 45,
          'caloriesBurned': 300,
          'content': [
            {'item': '热身', 'detail': '开合跳3组×20次', 'minutes': 5},
            {'item': '深蹲', 'detail': '徒手深蹲 3组×15次', 'minutes': 15},
          ],
          'note': '膝盖不适减组数',
        }
      ],
    };

void main() {
  group('导入预览编辑 → 确认导入（preview.toJson 链路）', () {
    test('不做修改直接导入：content/details/steps/note 全部保留', () {
      final imported = previewThenImport(rawPlan(), (_) {});
      final m = imported.meals.first;
      expect(m.details.length, 2);
      expect(m.details.first.item, '荞麦面');
      expect(m.details.first.amount, '100g');
      expect(m.steps, ['煮面', '炒虾仁浇上']);
      expect(m.note, '先吃菜后吃面');
      final e = imported.exercises.first;
      expect(e.content.length, 2);
      expect(e.content.first.item, '热身');
      expect(e.content.first.detail, '开合跳3组×20次');
      expect(e.content.first.minutes, 5);
      expect(e.content.last.minutes, 15);
      expect(e.note, '膝盖不适减组数');
    });

    test('预览中编辑训练内容/食材/做法/基础字段后导入：新内容生效、id 不变', () {
      final imported = previewThenImport(rawPlan(), (p) {
        final e = p.exercises.first;
        e.name = '晨跑';
        e.caloriesBurned = 320;
        e.content[0] = ContentItem(item: '慢跑', detail: '配速6min/km', minutes: 30);
        e.content.add(ContentItem(item: '拉伸', detail: '全身放松', minutes: 5));
        e.note = '';
        final m = p.meals.first;
        m.name = '虾仁荞麦面（减量）';
        m.details[0].amount = '80g';
        m.steps.add('少放酱油');
      });
      final e = imported.exercises.first;
      expect(e.id, 'e1');
      expect(e.name, '晨跑');
      expect(e.caloriesBurned, 320);
      expect(e.content.first.item, '慢跑');
      expect(e.content.first.detail, '配速6min/km');
      expect(e.content.first.minutes, 30);
      expect(e.content.length, 3); // 替换第1条 + 原有第2条 + 新增1条
      expect(e.content[1].item, '深蹲');
      expect(e.content.last.item, '拉伸');
      expect(e.note, '');
      final m = imported.meals.first;
      expect(m.name, '虾仁荞麦面（减量）');
      expect(m.details.first.amount, '80g');
      expect(m.steps.last, '少放酱油');
    });

    test('预览中删除某条后导入：该项不再出现，其余保留', () {
      final imported = previewThenImport(rawPlan(), (p) {
        p.meals.removeWhere((x) => x.id == 'm1'); // 预览行 ✕ 删除
      });
      expect(imported.meals, isEmpty);
      expect(imported.exercises.length, 1);
      expect(imported.exercises.first.id, 'e1');
    });
  });
}
