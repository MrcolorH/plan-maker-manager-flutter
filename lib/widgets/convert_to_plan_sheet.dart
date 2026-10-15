/// 转为日常计划弹窗组件
/// 选定执行周期（工作日/周末/每天/自定义）、处理计划冲突与覆盖提示、无缝升级当日快照
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/records.dart';
import '../providers/plan_provider.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/plan_utils.dart';

const Map<String, String> _typeEmoji = {
  'breakfast': '🥣',
  'lunch': '🍚',
  'dinner': '🍽',
  'snack': '☕',
};

class ConvertToPlanSheet extends StatefulWidget {
  final String date;
  final DayEntry entry;
  final VoidCallback? onCompleted;

  const ConvertToPlanSheet({
    super.key,
    required this.date,
    required this.entry,
    this.onCompleted,
  });

  @override
  State<ConvertToPlanSheet> createState() => _ConvertToPlanSheetState();
}

class _ConvertToPlanSheetState extends State<ConvertToPlanSheet> {
  late final TextEditingController _timeCtrl;
  late final Set<int> _selectedDays;
  bool _reminder = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _timeCtrl = TextEditingController(
      text: widget.entry.time.isNotEmpty ? widget.entry.time : '08:00',
    );
    // 默认选中工作日（周一至周五）
    _selectedDays = {1, 2, 3, 4, 5};
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    super.dispose();
  }

  bool _isEqualDays(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _applyPreset(Set<int> days) {
    setState(() {
      _selectedDays.clear();
      _selectedDays.addAll(days);
    });
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  Future<void> _pickTime() async {
    final cur = _timeCtrl.text.split(':');
    final initial = (cur.length == 2 && int.tryParse(cur[0]) != null && int.tryParse(cur[1]) != null)
        ? TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1]))
        : const TimeOfDay(hour: 8, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final h = picked.hour < 10 ? '0${picked.hour}' : '${picked.hour}';
      final m = picked.minute < 10 ? '0${picked.minute}' : '${picked.minute}';
      setState(() => _timeCtrl.text = '$h:$m');
    }
  }

  Future<void> _submit() async {
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一天执行该计划')),
      );
      return;
    }

    final planProvider = context.read<PlanProvider>();
    final targetSlot = widget.entry.slot.isNotEmpty ? widget.entry.slot : 'lunch';
    final daysList = _selectedDays.toList()..sort();

    // 检查冲突
    final conflicts = planProvider.checkMealConflicts(
      type: targetSlot,
      days: daysList,
    );

    if (conflicts.isNotEmpty) {
      final confirmed = await _showConflictDialog(conflicts);
      if (confirmed != true) return;
    }

    await _executeSave(daysList);
  }

  Future<bool?> _showConflictDialog(List<MealPlanConflict> conflicts) {
    final slotName = kTypeCn[widget.entry.slot] ?? widget.entry.slot;
    final buffer = StringBuffer();
    for (final c in conflicts) {
      final dayNames = daysCn(c.conflictDays);
      buffer.writeln('• $dayNames：【${c.existingMeal.name}】(${c.existingMeal.calories ?? 0} kcal)');
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('覆盖已有计划？', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('检测到以下执行日的 $slotName 已存在计划：', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF4ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                buffer.toString().trim(),
                style: const TextStyle(fontSize: 13, color: AppColors.orange, height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '转为新计划后，旧计划的对应天数将被新方案覆盖替换。是否确认覆盖？',
              style: TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认覆盖'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeSave(List<int> daysList) async {
    setState(() => _saving = true);
    try {
      final planProvider = context.read<PlanProvider>();
      final oldEntry = widget.entry;
      final targetSlot = oldEntry.slot.isNotEmpty ? oldEntry.slot : 'lunch';

      // 1. 转为长期日常计划并原子升级当天快照（含旧冲突裁剪、当天快照就地升级、打卡平滑迁移、防重）
      await planProvider.convertSnapshotToPlan(
        type: targetSlot,
        name: oldEntry.content,
        time: _timeCtrl.text.trim().isNotEmpty ? _timeCtrl.text.trim() : '12:00',
        calories: oldEntry.calories,
        protein: oldEntry.protein,
        carbs: oldEntry.carbs,
        fat: oldEntry.fat,
        days: daysList,
        reminder: _reminder,
        note: oldEntry.note,
        sourceSnapshotDate: widget.date,
        sourceSnapshotEntryId: oldEntry.id,
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onCompleted?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已成功转为日常${kTypeCn[targetSlot] ?? '餐食'}计划！')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转计划失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final slotName = kTypeCn[entry.slot] ?? '餐食';
    final isAllWeek = _isEqualDays(_selectedDays, {1, 2, 3, 4, 5, 6, 7});
    final isWorkdays = _isEqualDays(_selectedDays, {1, 2, 3, 4, 5});
    final isWeekends = _isEqualDays(_selectedDays, {6, 7});

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('设为日常$slotName计划', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSub),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 预览条目卡片
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD2E8D2)),
            ),
            child: Row(
              children: [
                Text(_typeEmoji[entry.slot] ?? '🍽', style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.content,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.calories != null ? '${entry.calories} kcal' : '自由餐'}${_macroText()}',
                        style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 用餐时间选择
          Row(
            children: [
              const Text('用餐时间', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.chartGray),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: AppColors.orange),
                      const SizedBox(width: 6),
                      Text(_timeCtrl.text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 28),

          // 执行周期
          const Text('每周执行哪几天？', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          // 快捷选项
          Row(
            children: [
              _presetChip('工作日', isWorkdays, () => _applyPreset({1, 2, 3, 4, 5})),
              const SizedBox(width: 8),
              _presetChip('周末', isWeekends, () => _applyPreset({6, 7})),
              const SizedBox(width: 8),
              _presetChip('每天', isAllWeek, () => _applyPreset({1, 2, 3, 4, 5, 6, 7})),
            ],
          ),
          const SizedBox(height: 14),

          // 7 天圆形选择器
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= 7; i++)
                _dayCircle(i, _selectedDays.contains(i)),
            ],
          ),
          const SizedBox(height: 16),

          // 提醒开关
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开启用餐提醒', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: const Text('到点本地闹钟提醒（无需网络）', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            value: _reminder,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primaryDisabled,
            onChanged: (val) => setState(() => _reminder = val),
          ),
          const SizedBox(height: 18),

          // 确认保存按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('保存为日常计划', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSub,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _dayCircle(int day, bool selected) {
    final names = ['', '一', '二', '三', '四', '五', '六', '日'];
    return GestureDetector(
      onTap: () => _toggleDay(day),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.primary : Colors.grey.shade100,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          names[day],
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : AppColors.text,
          ),
        ),
      ),
    );
  }

  String _macroText() {
    final p = widget.entry.protein;
    final c = widget.entry.carbs;
    final f = widget.entry.fat;
    if (p == null && c == null && f == null) return '';
    final parts = <String>[];
    if (p != null) parts.add('P ${p}g');
    if (c != null) parts.add('C ${c}g');
    if (f != null) parts.add('F ${f}g');
    return ' · ${parts.join(' · ')}';
  }
}
