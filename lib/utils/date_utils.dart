/// 日期工具：统一使用本地时区 YYYY-MM-DD 字符串（与旧版 uni-app 完全一致）
library;

String _pad2(int n) => n < 10 ? '0$n' : '$n';

/// DateTime → 'YYYY-MM-DD'
String fmtDate(DateTime d) => '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

/// 今天 'YYYY-MM-DD'
String todayStr() => fmtDate(DateTime.now());

/// 'YYYY-MM-DD' → 解析结果；weekday: 1=周一 … 7=周日
class DateParts {
  final int y, m, d;
  final DateTime date;
  final int weekday;
  const DateParts(this.y, this.m, this.d, this.date, this.weekday);
}

DateParts parseDate(String str) {
  final parts = str.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1], parts[2]);
  final wd = date.weekday; // 1=周一 … 7=周日（Dart 与 JS getDay 的 0=周日 不同）
  return DateParts(parts[0], parts[1], parts[2], date, wd == 7 ? 7 : wd);
}

String addDays(String str, int n) {
  final p = parseDate(str);
  final date = DateTime(p.y, p.m, p.d).add(Duration(days: n));
  return fmtDate(date);
}

const List<String> _weekCn = ['', '一', '二', '三', '四', '五', '六', '七'];

String weekCn(int weekday) => (weekday >= 1 && weekday <= 7) ? _weekCn[weekday] : '';

/// days 数组 → '一三五' / '每天'
String daysCn(List<int>? days) {
  if (days == null || days.isEmpty) return '每天';
  final list = [...days]..sort();
  return list.map((d) => _weekCn[d]).join();
}

/// ['2026-09-05','2026-09-19'] → '9/5、9/19'；超过 max 个截断加"等N天"
String datesCn(List<String> dates, [int max = 2]) {
  if (dates.isEmpty) return '';
  String fmt(String d) {
    final parts = d.split('-');
    return '${int.parse(parts[1])}/${int.parse(parts[2])}';
  }
  final head = dates.take(max).map(fmt).join('、');
  return dates.length > max ? '$head 等${dates.length}天' : head;
}

/// '2026-08-27' → '8月27日 周四'
String dateCn(String str) {
  final p = parseDate(str);
  return '${p.m}月${p.d}日 周${_weekCn[p.weekday]}';
}

String nowTimeStr() {
  final d = DateTime.now();
  return '${_pad2(d.hour)}:${_pad2(d.minute)}';
}

/// 合法 'YYYY-MM-DD' 校验（拒绝 2026-02-30 这类进位日期）
bool isValidDateStr(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final parts = s.split('-').map(int.parse).toList();
  final y = parts[0], m = parts[1], d = parts[2];
  final date = DateTime(y, m, d);
  return date.year == y && date.month == m && date.day == d;
}

/// 'HH:mm' 的分钟数（用于排序/计算），非法返回 -1
int timeToMin(String? t) {
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(t ?? '');
  return m != null ? int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!) : -1;
}
