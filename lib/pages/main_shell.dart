/// 主壳：4 个 Tab 容器 + 底部导航 + 首启引导拦截
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/onboarding_provider.dart';
import '../theme/app_theme.dart';
import 'onboarding/onboarding_page.dart';
import 'plan/plan_page.dart';
import 'settings/settings_page.dart';
import 'stats/stats_page.dart';
import 'today/today_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    // 首启判断：老用户升级不弹引导
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ob = context.read<OnboardingProvider>();
      if (ob.shouldOnboard()) {
        _openOnboarding();
      }
    });
  }

  void _openOnboarding() {
    Navigator.of(context).push(AppRoutes.fade<void>(const OnboardingPage()));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex(app.activeTab),
        children: const [
          TodayPage(),
          PlanPage(),
          StatsPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: _TabBarView(
        active: app.activeTab,
        onTap: (tab) {
          context.read<AppProvider>().setActiveTab(tab);
        },
      ),
    );
  }

  int _tabIndex(String tab) {
    switch (tab) {
      case 'today':
        return 0;
      case 'plan':
        return 1;
      case 'stats':
        return 2;
      default:
        return 3;
    }
  }
}

/// 底部导航（对应 tab-bar.vue）
class _TabBarView extends StatelessWidget {
  final String active;
  final ValueChanged<String> onTap;
  const _TabBarView({required this.active, required this.onTap});

  static const _items = [
    (tab: 'today', icon: '🏠', label: '今日'),
    (tab: 'plan', icon: '📋', label: '计划'),
    (tab: 'stats', icon: '📊', label: '统计'),
    (tab: 'settings', icon: '⚙️', label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    // Material 提供 InkWell 水波承载层：白底 Container 会盖住无 Material 祖先时的涟漪
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEEF0F4))),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: _items.map((item) {
              final selected = item.tab == active;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(item.tab),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? AppColors.primary : AppColors.textSub,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
