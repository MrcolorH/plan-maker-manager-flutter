/// 月历格子显示状态分类测试：与 stats.vue calClass 1:1 对照
/// 覆盖：未来/今天已排计划未打卡 → planned（空心圈待开始）
///       全部完成 → complete / 部分完成 → partial
///       未来无计划、开始前、无数据、过去未完成 → none（灰字，不标未完成）
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:jianfei_dazi/pages/stats/stats_page.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';

MonthCell _cell({
  String date = '2026-09-02',
  int day = 2,
  int total = 0,
  int done = 0,
  bool complete = false,
  bool future = false,
  bool beforeStart = false,
  bool isStart = false,
}) {
  return MonthCell(
    date: date,
    day: day,
    total: total,
    done: done,
    rate: total != 0 ? done / total : 0,
    complete: complete,
    future: future,
    beforeStart: beforeStart,
    isStart: isStart,
  );
}

void main() {
  const today = '2026-09-02'; // 固定「今天」便于断言

  group('monthCellKind（对照 stats.vue calClass）', () {
    test('未来已排计划未打卡 → planned（空心绿圈待开始）', () {
      expect(
        monthCellKind(_cell(date: '2026-09-10', total: 3, done: 0, future: true), today: today),
        MonthCellKind.planned,
      );
    });

    test('今天已排计划未打卡 → planned', () {
      expect(
        monthCellKind(_cell(date: today, total: 3, done: 0), today: today),
        MonthCellKind.planned,
      );
    });

    test('未来无计划 → none（灰字）', () {
      expect(
        monthCellKind(_cell(date: '2026-09-10', total: 0, future: true), today: today),
        MonthCellKind.none,
      );
    });

    test('全部完成 → complete', () {
      expect(
        monthCellKind(_cell(date: '2026-09-01', total: 3, done: 3, complete: true), today: today),
        MonthCellKind.complete,
      );
    });

    test('部分完成（done>0 未全）→ partial', () {
      expect(
        monthCellKind(_cell(date: '2026-09-01', total: 3, done: 2, complete: false), today: today),
        MonthCellKind.partial,
      );
    });

    test('过去有计划但未打卡 → none（不标未完成）', () {
      expect(
        monthCellKind(_cell(date: '2026-09-01', total: 3, done: 0), today: today),
        MonthCellKind.none,
      );
    });

    test('开始前（有计划也不计）→ none', () {
      expect(
        monthCellKind(_cell(date: '2026-08-20', total: 2, done: 0, beforeStart: true), today: today),
        MonthCellKind.none,
      );
    });

    test('无任务 → none', () {
      expect(
        monthCellKind(_cell(date: '2026-09-01', total: 0, done: 0), today: today),
        MonthCellKind.none,
      );
    });

    test('今天有计划未完成 + done>0 → 按 complete/partial 处理，不回退 planned', () {
      expect(
        monthCellKind(_cell(date: today, total: 3, done: 2, complete: false), today: today),
        MonthCellKind.partial,
      );
    });
  });
}
