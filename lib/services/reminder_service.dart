/// 本地提醒调度（flutter_local_notifications 替代旧版 plus.push）
/// 相比旧版优势：zonedSchedule 注册到系统 AlarmManager，重启后调度自动恢复（无需手动打开 App）
library;

import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/plan_data.dart';
import '../models/settings.dart';
import '../utils/date_utils.dart';
import '../utils/plan_utils.dart';

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// 已调度 key 集合（`date|time|advance|type|id`，用于增量跳过）
  final Set<String> _scheduledKeys = {};

  static const int _mealNotifId = 1000;
  static const int _exerciseNotifId = 2000;

  Future<void> init() async {
    if (_inited) return;
    tz.initializeTimeZones();
    // 使用本地时区（默认 Asia/Shanghai 由系统本地化决定；这里用 tz.local）
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (response) {
        // 通知点击定位：payload 形如 '{"focus":"meal:xxx"}'
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final p = _decodePayload(payload);
            if (p != null && p['focus'] != null) {
              NotificationTapBus.instance.focus = p['focus'];
            }
          } catch (_) {}
        }
      },
    );
    _inited = true;
  }

  Map<String, dynamic>? _decodePayload(String s) {
    try {
      final v = jsonDecode(s);
      return (v is Map) ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  /// 计算触发时间（本地时间 - 提前分钟数）
  DateTime _fireTime(String dateStr, String timeStr, int advanceMin) {
    final parts = timeStr.split(':').map(int.parse).toList();
    final p = parseDate(dateStr);
    return DateTime(p.y, p.m, p.d, parts[0], parts[1]).subtract(Duration(minutes: advanceMin));
  }

  /// 增量调度：今天+明天，跳过已调度 key；上限 30 条保护
  Future<void> ensureScheduled(PlanData plan, AppSettings settings) async {
    if (!settings.reminderEnabled) return;
    if (!_inited) await init();
    final today = todayStr();
    final newKeys = <String>{};
    final results = <Future<void>>[];
    for (final date in [today, addDays(today, 1)]) {
      final tasks = getTasksForDate(plan, date);
      final items = <({String type, dynamic item})>[
        ...tasks.meals.where((t) => t.reminder).map((t) => (type: 'meal', item: t)),
        ...tasks.exercises.where((t) => t.reminder).map((t) => (type: 'exercise', item: t)),
      ];
      var count = 0;
      for (final entry in items) {
        if (count >= 30) break; // 上限保护
        final item = entry.item;
        final time = item is MealItem ? item.time : (item as ExerciseItem).time;
        final id = item.id;
        final name = item.name;
        final note = item is MealItem ? item.note : (item as ExerciseItem).note;
        final fire = _fireTime(date, time, settings.reminderAdvance);
        if (fire.isBefore(DateTime.now())) continue; // 已过期不调度
        final key = '$date|$time|${settings.reminderAdvance}|${entry.type}|$id';
        newKeys.add(key);
        if (_scheduledKeys.contains(key)) continue; // 本进程已调度过
        _scheduledKeys.add(key);
        results.add(_scheduleOne(
          date: date,
          type: entry.type,
          id: id,
          title: entry.type == 'meal' ? '用餐提醒 · 减肥搭子' : '运动提醒 · 减肥搭子',
          body: name + (note.isNotEmpty ? '｜${note.length > 20 ? note.substring(0, 20) : note}' : ''),
          fireAt: fire,
          payload: '{"focus":"${entry.type}:$id"}',
        ));
        count++;
      }
    }
    // 清除本次未涉及的 key（防膨胀）
    _scheduledKeys.removeWhere((k) => !newKeys.contains(k) && !_isFutureKey(k, today));
    await Future.wait(results);
  }

  bool _isFutureKey(String key, String today) {
    // 保留明天及以后日期的 key（今天重算时可能暂时未纳入）
    final parts = key.split('|');
    if (parts.isEmpty) return false;
    return parts[0].compareTo(today) > 0;
  }

  Future<void> _scheduleOne({
    required String date,
    required String type,
    required String id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String payload,
  }) async {
    final notifId = (type == 'meal' ? _mealNotifId : _exerciseNotifId) +
        _stableId(date, id);
    const androidDetails = AndroidNotificationDetails(
      'jianfei_dazi_reminder',
      '计划提醒',
      channelDescription: '到点提醒用餐与运动',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBanner: true,
    );
    try {
      await _plugin.zonedSchedule(
        notifId,
        title,
        body,
        tz.TZDateTime.from(fireAt, tz.local),
        const NotificationDetails(android: androidDetails, iOS: darwinDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      // 精确闹钟权限未授权时降级为 inexact（仍能提醒，时间可能偏差数分钟）
      try {
        await _plugin.zonedSchedule(
          notifId,
          title,
          body,
          tz.TZDateTime.from(fireAt, tz.local),
          const NotificationDetails(android: androidDetails, iOS: darwinDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      } catch (_) {}
    }
  }

  /// 稳定通知 id：date + id 哈希 → 0-999（避免重复调度覆盖）
  int _stableId(String date, String id) {
    final h = (date + id).codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return h % 1000;
  }

  /// 全量重排：取消全部 + 清 keys + 重新调度（导入计划/修改提醒设置时用）
  Future<void> fullReschedule(PlanData plan, AppSettings settings) async {
    if (!_inited) await init();
    await _plugin.cancelAll();
    _scheduledKeys.clear();
    if (settings.reminderEnabled) {
      await ensureScheduled(plan, settings);
    }
  }

  /// 应用启动时调用：恢复调度（重启后系统级调度自动恢复，这里做兜底重算）
  Future<void> onLaunch(PlanData plan, AppSettings settings) async {
    await init();
    await ensureScheduled(plan, settings);
  }

  /// Android 13+ 通知权限申请；返回是否已授权
  Future<bool> requestNotifPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// 查询通知权限是否已授予（Android 13+）
  Future<bool> checkNotifPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? true;
  }
}

/// 通知点击定位总线：记录点击的通知 focus 键（如 'meal:xxx'）
class NotificationTapBus {
  NotificationTapBus._();
  static final NotificationTapBus instance = NotificationTapBus._();
  String focus = '';
}
