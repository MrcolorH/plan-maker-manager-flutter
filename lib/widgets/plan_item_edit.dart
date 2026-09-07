/// 计划条目标签全量编辑器（导入预览 / 详情页编辑共用）
/// 餐食：名称/类型/时间/热量 + 食材清单 details + 做法步骤 steps + 备注
/// 运动：名称/时间/时长/预计消耗 + 训练内容 content（环节名/具体内容/分钟）+ 备注
/// FR6.9：餐食「热量」/运动「预计消耗」旁 ✨ AI 估算按钮——按当前编辑内容整餐/整次估算，
/// 结果只回填输入框（可手改），点「保存」才落库；拆解/错误行内展示（弹层会遮挡 SnackBar）。
///
/// 只编辑传入对象的深拷贝：底部弹层（避免键盘遮挡，随键盘上移）；
/// 点「保存」→ pop 返回更新后的新对象；取消/点外部关闭 → 返回 null，不改任何数据。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plan_data.dart';
import '../providers/onboarding_provider.dart';
import '../providers/record_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/usage_provider.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import '../utils/calorie_utils.dart' show weightForDate;
import '../utils/date_utils.dart' show todayStr;
import '../utils/plan_utils.dart' show kTypeCn;
import 'ai_config_sheet.dart';

final RegExp _timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// 弹出餐食/运动完整编辑器，返回保存后的新对象（取消返回 null）
Future<Object?> showPlanItemEditor({
  required BuildContext context,
  MealItem? meal,
  ExerciseItem? exercise,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ItemEditSheet(
      meal: meal == null ? null : MealItem.fromJson(meal.toJson()),
      exercise: exercise == null ? null : ExerciseItem.fromJson(exercise.toJson()),
    ),
  );
}

/// 食材行输入组
class _DetC {
  final item = TextEditingController();
  final amount = TextEditingController();
  _DetC({String item = '', String amount = ''}) {
    this.item.text = item;
    this.amount.text = amount;
  }
  void dispose() {
    item.dispose();
    amount.dispose();
  }
}

/// 做法步骤行输入
class _StepC {
  final ctrl = TextEditingController();
  _StepC({String text = ''}) {
    ctrl.text = text;
  }
  void dispose() => ctrl.dispose();
}

/// 训练环节行输入组（环节名/具体内容/分钟）
class _ContentC {
  final item = TextEditingController();
  final detail = TextEditingController();
  final minutes = TextEditingController();
  _ContentC({String item = '', String detail = '', int minutes = 0}) {
    this.item.text = item;
    this.detail.text = detail;
    this.minutes.text = minutes > 0 ? '$minutes' : '';
  }
  void dispose() {
    item.dispose();
    detail.dispose();
    minutes.dispose();
  }
}

class _ItemEditSheet extends StatefulWidget {
  final MealItem? meal;
  final ExerciseItem? exercise;
  const _ItemEditSheet({this.meal, this.exercise});

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  bool get _isMeal => widget.meal != null;

  // FR6.9：AI 估算状态（行内拆解/错误提示，弹层内展示——SnackBar 会被 bottom sheet 遮挡）
  bool _aiLoading = false;
  String? _aiInfo;
  bool _aiIsError = false;

  late final TextEditingController _name;
  late final TextEditingController _time;
  late final TextEditingController _cal;
  late final TextEditingController _dur;
  late final TextEditingController _burn;
  late final TextEditingController _note;
  late String _type;

  final List<_DetC> _details = [];
  final List<_StepC> _steps = [];
  final List<_ContentC> _content = [];

  @override
  void initState() {
    super.initState();
    if (_isMeal) {
      final m = widget.meal!;
      _name = TextEditingController(text: m.name);
      _time = TextEditingController(text: m.time);
      _cal = TextEditingController(text: m.calories != null ? '${m.calories}' : '');
      _dur = TextEditingController();
      _burn = TextEditingController();
      _type = kTypeCn.containsKey(m.type) ? m.type : 'lunch';
      _details.addAll(m.details.map((d) => _DetC(item: d.item, amount: d.amount)));
      _steps.addAll(m.steps.map((s) => _StepC(text: s)));
      if (m.steps.isEmpty && m.details.isEmpty) {
        // 无内容时预置一行，降低「不知道点哪里添加」的困惑
        _details.add(_DetC());
        _steps.add(_StepC());
      }
    } else {
      final e = widget.exercise!;
      _name = TextEditingController(text: e.name);
      _time = TextEditingController(text: e.time);
      _cal = TextEditingController();
      _dur = TextEditingController(text: '${e.duration}');
      _burn = TextEditingController(text: '${e.caloriesBurned}');
      _type = 'exercise';
      _content.addAll(e.content.map((c) => _ContentC(item: c.item, detail: c.detail, minutes: c.minutes)));
      if (e.content.isEmpty) _content.add(_ContentC());
    }
    _note = TextEditingController(text: (_isMeal ? widget.meal!.note : widget.exercise!.note));
  }

  @override
  void dispose() {
    _name.dispose();
    _time.dispose();
    _cal.dispose();
    _dur.dispose();
    _burn.dispose();
    _note.dispose();
    for (final d in _details) {
      d.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    for (final c in _content) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- 组装 ----------

  Object _collect() {
    if (_isMeal) {
      final m = widget.meal!;
      final name = _name.text.trim();
      m.name = name.isEmpty ? '未命名' : name;
      m.type = _type;
      final t = _time.text.trim();
      if (_timeRe.hasMatch(t)) m.time = t;
      final cal = int.tryParse(_cal.text.trim());
      m.calories = (cal != null && cal >= 0) ? cal : null;
      m.note = _note.text.trim();
      m.details = _details
          .map((d) => DetailItem(item: d.item.text.trim(), amount: d.amount.text.trim()))
          .where((d) => d.item.isNotEmpty)
          .toList();
      m.steps = _steps.map((s) => s.ctrl.text.trim()).where((s) => s.isNotEmpty).toList();
      return m;
    }
    final e = widget.exercise!;
    final name = _name.text.trim();
    e.name = name.isEmpty ? '未命名' : name;
    final t = _time.text.trim();
    if (_timeRe.hasMatch(t)) e.time = t;
    final dur = int.tryParse(_dur.text.trim());
    if (dur != null && dur > 0 && dur <= 600) e.duration = dur;
    final burn = int.tryParse(_burn.text.trim());
    if (burn != null && burn >= 0) e.caloriesBurned = burn;
    e.note = _note.text.trim();
    e.content = _content
        .map((c) => ContentItem(
              item: c.item.text.trim(),
              detail: c.detail.text.trim(),
              minutes: _minutesOf(c.minutes.text),
            ))
        .where((c) => c.item.isNotEmpty)
        .toList();
    return e;
  }

  int _minutesOf(String raw) {
    final n = int.tryParse(raw.trim());
    return (n != null && n > 0) ? n : 0;
  }

  // ---------- FR6.9：AI 估算 ----------

  /// 把当前编辑中的餐食拼装为估算描述；无任何有效内容返回 null
  String? _mealDesc() {
    final lines = <String>[];
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      final typeCn = kTypeCn[_type] ?? '';
      lines.add('餐名：$name${typeCn.isEmpty ? '' : '（$typeCn）'}');
    }
    final dets = _details
        .map((d) {
          final item = d.item.text.trim();
          if (item.isEmpty) return '';
          final amount = d.amount.text.trim();
          return amount.isEmpty ? '- $item' : '- $item $amount';
        })
        .where((s) => s.isNotEmpty)
        .toList();
    if (dets.isNotEmpty) {
      lines.add('食材清单：');
      lines.addAll(dets);
    }
    final steps = _steps.map((s) => s.ctrl.text.trim()).where((s) => s.isNotEmpty).toList();
    if (steps.isNotEmpty) {
      lines.add('做法步骤：');
      for (var i = 0; i < steps.length; i++) {
        lines.add('${i + 1}. ${steps[i]}');
      }
    }
    final note = _note.text.trim();
    if (note.isNotEmpty) lines.add('备注：$note');
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// 把当前编辑中的运动拼装为估算描述；无任何有效内容返回 null
  String? _exDesc() {
    final lines = <String>[];
    final name = _name.text.trim();
    final dur = int.tryParse(_dur.text.trim());
    if (name.isNotEmpty) {
      lines.add('训练名：$name${(dur != null && dur > 0) ? '（总时长 $dur 分钟）' : ''}');
    }
    final cs = _content
        .map((c) {
          final item = c.item.text.trim();
          if (item.isEmpty) return '';
          final min = _minutesOf(c.minutes.text);
          final detail = c.detail.text.trim();
          final head = min > 0 ? '- $item（$min分钟）' : '- $item';
          return detail.isEmpty ? head : '$head：$detail';
        })
        .where((s) => s.isNotEmpty)
        .toList();
    if (cs.isNotEmpty) {
      lines.add('训练内容：');
      lines.addAll(cs);
    }
    final note = _note.text.trim();
    if (note.isNotEmpty) lines.add('注意事项：$note');
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// AI 估算 → 回填热量/消耗输入框（可手改，点「保存」才落库）；
  /// 拆解明细与错误均行内展示；未配置 Key 先弹配置层，配好后继续本次估算
  Future<void> _aiEstimate() async {
    final desc = _isMeal ? _mealDesc() : _exDesc();
    if (desc == null) {
      setState(() {
        _aiInfo = _isMeal ? '请先填写餐名/食材或步骤' : '请先填写训练名或训练内容';
        _aiIsError = true;
      });
      return;
    }
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 估算需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    setState(() {
      _aiLoading = true;
      _aiInfo = null;
    });
    try {
      final Map<String, dynamic> r;
      if (_isMeal) {
        r = await AiService.instance.estimateItemMeal(settings.ai, desc, onUsage: usage.addUsage);
      } else {
        // F10.6 口径：当天生效体重优先，回落引导 profile；资料完整才传性别/年龄/身高
        final p = context.read<OnboardingProvider>().state.profile;
        final wd = weightForDate(context.read<RecordProvider>().store, todayStr());
        r = await AiService.instance.estimateBurn(
          settings.ai,
          desc,
          weight: wd ?? p.weight,
          gender: p.complete ? p.gender : null,
          age: p.complete ? p.age : null,
          height: p.complete ? p.height : null,
          onUsage: usage.addUsage,
        );
      }
      if (!mounted) return;
      setState(() {
        if (_isMeal) {
          _cal.text = '${r['calories']}';
        } else {
          _burn.text = '${r['calories']}';
        }
        final detail = (r['detail'] as String?)?.trim() ?? '';
        _aiInfo = detail.isEmpty ? '估算完成' : detail;
        _aiIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiInfo = e.toString().replaceFirst('Exception: ', '');
        _aiIsError = true;
      });
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  void _save() => Navigator.pop(context, _collect());

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final title = _isMeal ? '编辑餐食' : '编辑运动';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.chartGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: AppColors.textSub),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isMeal) ...[
              _card([
                _label('餐食类型'),
                _typeChips(),
                const SizedBox(height: 10),
                _in(_name, '名称'),
                const SizedBox(height: 8),
                _in(_time, '时间 HH:mm'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _in(_cal, '热量 kcal（留空=自由餐）', kb: TextInputType.number)),
                    const SizedBox(width: 8),
                    _aiBtn('AI 测算'),
                  ],
                ),
                if (_aiInfo != null) _aiInfoText(),
              ]),
              _card([
                _label('食材清单'),
                for (var i = 0; i < _details.length; i++) _detRow(i),
                _addBtn('＋ 添加食材', () => setState(() => _details.add(_DetC()))),
              ]),
              _card([
                _label('做法步骤'),
                for (var i = 0; i < _steps.length; i++) _stepRow(i),
                _addBtn('＋ 添加步骤', () => setState(() => _steps.add(_StepC()))),
              ]),
            ] else ...[
              _card([
                _in(_name, '名称'),
                const SizedBox(height: 8),
                _in(_time, '时间 HH:mm'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _in(_dur, '时长（分钟）', kb: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _in(_burn, '预计消耗 kcal', kb: TextInputType.number)),
                    const SizedBox(width: 8),
                    _aiBtn('AI 算'),
                  ],
                ),
                if (_aiInfo != null) _aiInfoText(),
              ]),
              _card([
                _label('训练内容（每个动作/环节一行）'),
                for (var i = 0; i < _content.length; i++) _contentRow(i),
                _addBtn('＋ 添加环节', () => setState(() => _content.add(_ContentC()))),
              ]),
            ],
            const SizedBox(height: 10),
            _card([_in(_note, _isMeal ? '备注（如进食顺序/替代食材）' : '注意事项', lines: 2)]),
            const SizedBox(height: 14),
            PrimaryButton('保存', onPressed: _save),
          ],
        ),
      ),
    );
  }

  /// 白底分组卡
  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w600)),
    );
  }

  Widget _typeChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kTypeCn.entries.map((e) {
        final selected = _type == e.key;
        return GestureDetector(
          onTap: () => setState(() => _type = e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryBg : AppColors.tagBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(e.value,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.primary : AppColors.textSub,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                )),
          ),
        );
      }).toList(),
    );
  }

  /// 单输入框
  Widget _in(TextEditingController c, String hint, {TextInputType? kb, int lines = 1}) {
    return TextField(
      controller: c,
      keyboardType: kb,
      maxLines: lines,
      minLines: 1,
      style: const TextStyle(fontSize: 13, color: AppColors.text),
      decoration: _dec(hint),
    );
  }

  /// FR6.9：AI 估算紧凑按钮（Loading 转圈禁用，样式与今日页 ✨ 按钮同族）
  Widget _aiBtn(String label) {
    return OutlinedButton.icon(
      onPressed: _aiLoading ? null : _aiEstimate,
      icon: _aiLoading
          ? const SizedBox(
              width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('✨', style: TextStyle(fontSize: 12)),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orange,
        side: const BorderSide(color: AppColors.orange, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// FR6.9：估算拆解/错误行内小字（替代 SnackBar——弹层会遮挡底层 Scaffold 的 SnackBar）
  Widget _aiInfoText() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _aiInfo!,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: _aiIsError ? AppColors.orange : AppColors.textSub,
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textFaint),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFECECE7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
      ),
    );
  }

  Widget _delBtn(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.close, size: 16, color: AppColors.textFaint),
      ),
    );
  }

  Widget _addBtn(String text, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.primary)),
        ),
      ),
    );
  }

  Widget _detRow(int i) {
    final d = _details[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: _in(d.item, '食材名')),
          const SizedBox(width: 8),
          Expanded(child: _in(d.amount, '用量（如 150g/1个）')),
          _delBtn(() => setState(() {
            _details.removeAt(i).dispose();
          })),
        ],
      ),
    );
  }

  Widget _stepRow(int i) {
    final s = _steps[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: _in(s.ctrl, '步骤 ${i + 1}（如：冷水下锅焯水2分钟）')),
          _delBtn(() => setState(() {
            _steps.removeAt(i).dispose();
          })),
        ],
      ),
    );
  }

  Widget _contentRow(int i) {
    final c = _content[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _in(c.item, '环节名（如 热身/有氧/力量）')),
              const SizedBox(width: 8),
              SizedBox(width: 92, child: _in(c.minutes, '分钟', kb: TextInputType.number)),
              _delBtn(() => setState(() {
                _content.removeAt(i).dispose();
              })),
            ],
          ),
          const SizedBox(height: 6),
          _in(c.detail, '具体内容（如：3组×15次 / 慢跑5公里）', lines: 2),
        ],
      ),
    );
  }
}
