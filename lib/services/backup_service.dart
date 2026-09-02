/// 历史数据备份：导出 / 解析 / 增量合并 / 覆盖替换
/// 设计依据：spec/backup-design.md v1.0（F9）—— 与旧版 backup.js 格式兼容
/// 备份文件：.txt 纯文本（内容为 JSON），保存到手机存储根目录的 Download 目录
/// 导出 = 8 项全量快照；增量导入不触碰 settings/onboardingState/apiUsage；
/// 覆盖导入 = 全量替换（含 AI 配置，弹窗需强确认）
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/onboarding.dart';
import '../models/plan_data.dart';
import '../models/settings.dart';

/// 备份数据快照（8 项）
class BackupData {
  final PlanData planData;
  final Map<String, dynamic> checkRecords;
  final Map<String, dynamic> mealAdjust;
  final Map<String, dynamic> tempTasks;
  final Map<String, dynamic> extraFoods;
  final AppSettings settings;
  final OnboardingState onboardingState;
  final ApiUsage apiUsage;

  const BackupData({
    required this.planData,
    required this.checkRecords,
    required this.mealAdjust,
    required this.tempTasks,
    required this.extraFoods,
    required this.settings,
    required this.onboardingState,
    required this.apiUsage,
  });

  Map<String, dynamic> toJson() => {
        'planData': planData.toJson(),
        'checkRecords': checkRecords,
        'mealAdjust': mealAdjust,
        'tempTasks': tempTasks,
        'extraFoods': extraFoods,
        'settings': settings.toJson(),
        'onboardingState': onboardingState.toJson(),
        'apiUsage': apiUsage.toJson(),
      };
}

/// 解析结果
class ParseResult {
  final bool ok;
  final BackupData? data;
  final String? error;
  final String? exportedAt;
  const ParseResult.ok(this.data, {this.exportedAt}) : ok = true, error = null;
  const ParseResult.fail(this.error) : ok = false, data = null, exportedAt = null;
}

/// 导入概要（弹层展示）
class BackupSummary {
  final int meals;
  final int exercises;
  final int checkDays;
  final int checkCount;
  final int tempCount;
  final bool hasAiKey;
  const BackupSummary({
    required this.meals,
    required this.exercises,
    required this.checkDays,
    required this.checkCount,
    required this.tempCount,
    required this.hasAiKey,
  });
}

/// 导出结果
/// [path] 给分享组件用的 file:// 路径；[savedPath] 给用户看的真实存储路径
class ExportResult {
  final String path;
  final String fileName;
  final String savedPath;

  /// true = 未能写入公共 Download 目录，已降级保存到应用私有目录
  final bool fallback;

  const ExportResult(
    this.path,
    this.fileName, {
    required this.savedPath,
    this.fallback = false,
  });
}

/// 备份文件名时间戳：YYYYMMDD-HHmmss
String backupStamp([DateTime? now]) {
  final d = now ?? DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${p(d.month)}${p(d.day)}-${p(d.hour)}${p(d.minute)}${p(d.second)}';
}

/// 备份文件名：ASCII（zhiqing = 「知轻」拼音 + 时间戳），中文名在传输端易截断/乱码；扩展名 .txt
String backupFileName([DateTime? now]) => 'zhiqing-backup-${backupStamp(now)}.txt';

/// 备份文件正文（JSON，缩进 2 空格）
/// 公开以便单元测试直接校验格式，与旧版 backup.js 兼容
String encodeBackup(BackupData data, {DateTime? now}) =>
    const JsonEncoder.withIndent('  ').convert({
      'app': 'jianfeidazi',
      'type': 'backup',
      'formatVersion': 1,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'appVersion': '1.0.0',
      'data': data.toJson(),
    });

Map<String, dynamic> _objOf(dynamic v) =>
    (v is Map && v is! List) ? Map<String, dynamic>.from(v) : {};

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Android 原生通道：写入公共 Download 目录
  static const MethodChannel _channel = MethodChannel('com.colorh.jianfei_dazi/backup');

  static const _errPermission = 'PERMISSION_DENIED';

  /// 备份文本内容（JSON，缩进 2 空格）
  String _backupText(BackupData data) => encodeBackup(data);

  /// 备份文件名：ASCII（拼音+时间戳），中文名在传输端易截断/乱码；扩展名 .txt
  String _backupFileName() => backupFileName();

  /// 公共 Download 目录路径（仅 Android 有意义），取不到返回 null
  Future<String?> downloadsPath() async {
    if (!Platform.isAndroid) return null;
    try {
      final p = await _channel.invokeMethod<String>('downloadsPath');
      return (p == null || p.isEmpty) ? null : p;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 导出：聚合 8 项全量快照 → 写 .txt 到手机存储根目录的 Download 目录
  /// Android 10+ 走 MediaStore（免权限）；写入失败或用户拒权时降级到应用文档目录
  Future<ExportResult> exportBackup(BackupData data) async {
    final text = _backupText(data);
    final fileName = _backupFileName();

    if (Platform.isAndroid) {
      try {
        final saved = await _channel.invokeMethod<String>(
          'saveToDownloads',
          {'fileName': fileName, 'content': text},
        );
        if (saved == null || saved.isEmpty) throw Exception('未返回保存路径');
        return ExportResult('file://$saved', fileName, savedPath: saved);
      } on PlatformException catch (e) {
        // 用户拒绝存储权限：直接向上抛，由 UI 明确提示，不做静默降级
        if (e.code == _errPermission) {
          throw Exception('未授予存储权限，无法保存到 Download 目录，请在系统弹窗中允许后重试');
        }
        // 其他写入失败：降级到应用文档目录，仍可分享出去
      } on MissingPluginException {
        // 通道不存在（极少见）：走降级
      }
    }

    // 非 Android 或降级路径：写应用文档目录
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(text, flush: true);
    return ExportResult('file://${file.path}', fileName,
        savedPath: file.path, fallback: true);
  }

  /// 系统分享文件
  Future<void> shareBackup(String path) async {
    final localPath = path.replaceFirst(RegExp(r'^file://'), '');
    await Share.shareXFiles([XFile(localPath, mimeType: 'text/plain')],
        text: '知轻数据备份');
  }

  /// 选择并读取备份文件文本（默认落在 Download 目录，找不到时由系统兜底）
  Future<String> pickBackupFile() async {
    String? initialDir;
    if (Platform.isAndroid) initialDir = await downloadsPath();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'dat', 'json'],
      dialogTitle: '选择备份文件（Download 目录）',
      initialDirectory: initialDir,
    );
    if (result == null || result.files.isEmpty) throw Exception('未选择文件');
    final path = result.files.single.path;
    if (path == null) throw Exception('无法读取所选文件，请从「文件」应用的 Download 目录中选择');
    return File(path).readAsString();
  }

  /// 解析 + 结构校验 + 容错归一
  ParseResult parseBackupText(String text) {
    if (text.trim().isEmpty) return const ParseResult.fail('文件内容为空');
    Object? obj;
    try {
      obj = jsonDecode(text.trim());
    } catch (_) {
      return const ParseResult.fail('备份文件格式错误（不是有效的 JSON），请确认选择了正确的备份文件');
    }
    if (obj is! Map) return const ParseResult.fail('备份文件格式错误：根节点必须是对象');
    if (obj['app'] != 'jianfeidazi' || obj['type'] != 'backup') {
      return const ParseResult.fail('这不是「知轻」的备份文件，请重新选择');
    }
    if (obj['formatVersion'] != 1) {
      return const ParseResult.fail('备份版本不支持：formatVersion 必须为 1');
    }
    if (obj['data'] is! Map) return const ParseResult.fail('备份文件缺少 data 数据段');
    final d = Map<String, dynamic>.from(obj['data'] as Map);
    return ParseResult.ok(_normalizeBackup(d), exportedAt: obj['exportedAt']?.toString());
  }

  /// 容错归一：防御老版本/手工编辑导致的缺字段
  BackupData _normalizeBackup(Map<String, dynamic> d) {
    final planData = _objOf(d['planData']);
    final pMeta = _objOf(planData['meta']);
    return BackupData(
      planData: PlanData(
        version: planData['version'] is String ? planData['version'] as String : '1.0',
        meta: PlanMeta.fromJson({
          'planName': pMeta['planName'],
          'startDate': pMeta['startDate'],
          'endDate': pMeta['endDate'],
          'startedAt': pMeta['startedAt'],
          'baseWeight': pMeta['baseWeight'],
          'targetWeight': pMeta['targetWeight'],
          'dailyCalorieTarget': pMeta['dailyCalorieTarget'],
          'tdee': pMeta['tdee'],
        }),
        meals: (planData['meals'] is List)
            ? (planData['meals'] as List)
                .whereType<Map>()
                .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        exercises: (planData['exercises'] is List)
            ? (planData['exercises'] as List)
                .whereType<Map>()
                .map((e) => ExerciseItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        deletedIds: (planData['deletedIds'] is List)
            ? (planData['deletedIds'] as List).whereType<String>().toList()
            : [],
      ),
      checkRecords: _objOf(d['checkRecords']),
      mealAdjust: _objOf(d['mealAdjust']),
      tempTasks: _objOf(d['tempTasks']),
      extraFoods: _objOf(d['extraFoods']),
      settings: AppSettings.fromJson(_objOf(d['settings'])),
      onboardingState: OnboardingState.fromJson(_objOf(d['onboardingState'])),
      apiUsage: ApiUsage.fromJson(_objOf(d['apiUsage'])),
    );
  }

  /// 导入前概要（弹层展示）
  BackupSummary buildBackupSummary(BackupData data) {
    var checkCount = 0;
    data.checkRecords.forEach((date, m) {
      if (m is Map) checkCount += m.keys.length;
    });
    var tempCount = 0;
    data.tempTasks.forEach((date, list) {
      if (list is List) tempCount += list.length;
    });
    return BackupSummary(
      meals: data.planData.meals.length,
      exercises: data.planData.exercises.length,
      checkDays: data.checkRecords.keys.length,
      checkCount: checkCount,
      tempCount: tempCount,
      hasAiKey: data.settings.ai.apiKey.isNotEmpty,
    );
  }

  /// 格式化备份导出时间 'YYYY-MM-DD HH:mm'
  String fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}
