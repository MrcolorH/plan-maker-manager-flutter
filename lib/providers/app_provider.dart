/// 全局 UI 状态：当前 tab / 今日日期键（跨天刷新）/ 通知定位键
library;

import 'package:flutter/foundation.dart';

import '../utils/date_utils.dart';

class AppProvider extends ChangeNotifier {
  String activeTab = 'today'; // today | plan | stats | settings
  String todayKey = todayStr();
  String focusKey = ''; // 通知点击定位，如 'meal:xxx'

  /// 切换底部 Tab（赋值后必须通知，否则 UI 不会重建）
  void setActiveTab(String tab) {
    if (activeTab == tab) return;
    activeTab = tab;
    notifyListeners();
  }

  /// 刷新今日日期键（today 页用它做跨天响应）；返回是否跨天
  bool refreshToday() {
    final t = todayStr();
    if (todayKey != t) {
      todayKey = t;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// 通知点击定位到今日页对应卡片
  void onNotificationTap(String focus) {
    focusKey = focus;
    setActiveTab('today');
  }
}
