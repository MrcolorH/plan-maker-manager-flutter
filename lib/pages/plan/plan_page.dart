/// 计划页（对应 tabs/plan.vue）
/// 计划信息卡 + 餐食/运动分栏 + 长按多选删除
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../providers/plan_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/meal_card.dart';
import '../import/import_page.dart';
import '../item/item_detail_page.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  String _section = 'meal'; // meal | exercise
  bool _selectMode = false;
  final Set<String> _selected = {};

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected(String type) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final planP = context.read<PlanProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('删除选中的 ${ids.length} 项计划？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await planP.removeItems(type, ids);
    }
    _exitSelectMode();
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const AppPageTitle(),
            Expanded(child: _body(context, plan)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PlanData plan) {
    if (!plan.hasPlan) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 96),
        children: [
          const EmptyState(icon: '📋', text: '还没有计划', subText: '导入或创建计划后，这里会展示全部条目'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: PrimaryButton('＋ 导入计划', onPressed: () => _openImport(context)),
          ),
        ],
      );
    }

    final list = _section == 'meal' ? plan.meals : plan.exercises;

    return Column(
      children: [
        // 分段控件
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tagBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                _segment('餐食 ${plan.meals.length}', 'meal'),
                _segment('运动 ${plan.exercises.length}', 'exercise'),
              ],
            ),
          ),
        ),
        if (_selectMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Text('已选 ${_selected.length} 项',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                const Spacer(),
                TextButton(
                  onPressed: _exitSelectMode,
                  child: const Text('取消', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                ),
                TextButton(
                  onPressed: _selected.isEmpty ? null : () => _deleteSelected(_section),
                  child: const Text('删除选中', style: TextStyle(fontSize: 13, color: AppColors.danger)),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (_section == 'meal' && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('还没有餐食计划，点下方导入', style: TextStyle(fontSize: 13, color: AppColors.textSub))),
                )
              else if (_section == 'exercise' && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('还没有运动计划，点下方导入', style: TextStyle(fontSize: 13, color: AppColors.textSub))),
                ),
              if (_section == 'meal')
                ...plan.meals.map((m) => _mealRow(context, plan, m))
              else
                ...plan.exercises.map((e) => _exerciseRow(context, plan, e)),
              const SizedBox(height: 8),
              DashedAddButton(
                '＋ 导入计划',
                margin: const EdgeInsets.symmetric(horizontal: 16),
                onTap: () => _openImport(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segment(String label, String section) {
    final selected = _section == section;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _section = section;
          _exitSelectMode();
        }),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            border: selected ? Border.all(color: const Color(0xFFECECE7)) : null,
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.text : AppColors.textSub,
              )),
        ),
      ),
    );
  }

  /// 列表行通用骨架（长按多选 + 点击详情）
  Widget _listRow({
    required String name,
    required Widget subRow,
    required String id,
    required String type,
    required bool selected,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBg : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () {
            if (_selectMode) {
              setState(() {
                if (!_selected.remove(id) && _selected.isEmpty) _selectMode = false;
              });
            } else {
              Navigator.of(context).push(AppRoutes.fade<void>(
                  ItemDetailPage(type: type, itemId: id)));
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (_selectMode) ...[
                  CheckCircle(checked: selected, size: 24, onTap: () => setState(() {
                    if (!_selected.remove(id) && _selected.isEmpty) _selectMode = false;
                  })),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      subRow,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20, color: AppColors.textSub),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mealRow(BuildContext context, PlanData plan, MealItem m) {
    final selected = _selected.contains(m.id);
    final sub = Row(
      children: [
        if (m.dates.isNotEmpty)
          Tag(datesCn(m.dates), color: 'green')
        else
          Tag(daysCn(m.days), color: 'green'),
        const SizedBox(width: 2),
        Text(m.time, style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        const SizedBox(width: 8),
        if (m.calories != null)
          Text('${m.calories} kcal', style: const TextStyle(fontSize: 12, color: AppColors.orange))
        else
          const Text('自由餐', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
      ],
    );
    return _listRow(
      id: m.id,
      type: 'meal',
      name: m.name,
      selected: selected,
      subRow: sub,
      onLongPress: () => setState(() {
        _selectMode = true;
        _selected.add(m.id);
      }),
    );
  }

  Widget _exerciseRow(BuildContext context, PlanData plan, ExerciseItem e) {
    final selected = _selected.contains(e.id);
    final sub = Row(
      children: [
        if (e.dates.isNotEmpty)
          Tag(datesCn(e.dates), color: 'green')
        else
          Tag(daysCn(e.days), color: 'green'),
        const SizedBox(width: 2),
        Text(e.time, style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        const SizedBox(width: 8),
        Text('${e.duration}min', style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        if (e.startDate.isNotEmpty && e.endDate.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_shortDate(e.startDate)}~${_shortDate(e.endDate)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textSub),
            ),
          ),
        ],
      ],
    );
    return _listRow(
      id: e.id,
      type: 'exercise',
      name: e.name,
      selected: selected,
      subRow: sub,
      onLongPress: () => setState(() {
        _selectMode = true;
        _selected.add(e.id);
      }),
    );
  }

  String _shortDate(String d) {
    final p = d.split('-');
    return p.length == 3 ? '${p[1]}-${p[2]}' : d;
  }

  void _openImport(BuildContext context) {
    Navigator.of(context).push(
      AppRoutes.fade<void>(const ImportPage()),
    );
  }
}
