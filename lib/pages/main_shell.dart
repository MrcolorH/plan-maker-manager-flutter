/// 主壳：4 个 Tab 容器 + 底部导航 + 首启引导拦截
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';
import 'onboarding/onboarding_page.dart';
import 'plan/plan_page.dart';
import 'settings/settings_page.dart';
import 'stats/stats_page.dart';
import 'today/today_page.dart';

class MainShell extends StatefulWidget {
  final ui.Image? overrideBgImage;
  const MainShell({super.key, this.overrideBgImage});

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
      } else {
        _checkUpdateSilently();
      }
    });
  }

  Future<void> _checkUpdateSilently() async {
    try {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final info = await AppUpdateService.instance.checkUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        await UpdateDialog.show(context, info);
      }
    } catch (_) {
      // 启动静默检查失败（无网或无更新），不打扰用户
    }
  }

  void _openOnboarding() {
    Navigator.of(context).push(AppRoutes.fade<void>(const OnboardingPage()));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return ThemedBackgroundContainer(
      overrideBgImage: widget.overrideBgImage,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
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

/// 底部导航：毛玻璃高透质感，与整体二次元背景无缝融合
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
    final theme = context.themeConfig;
    final primaryColor = theme.primaryColor;
    final hasBg = (theme.customBgPath != null && theme.customBgPath!.isNotEmpty) ||
        (theme.assetBgPath != null && theme.assetBgPath!.isNotEmpty);
    final isDark = theme.pageBgColor.computeLuminance() < 0.5;

    // 底部栏与整屏背景保持一致、通透无断裂感：
    // 当存在壁纸时采用高透毛玻璃融合；未设壁纸时采用柔和的主题色微透
    final barBgColor = hasBg
        ? (isDark
            ? theme.pageBgColor.withValues(alpha: 0.65)
            : theme.pageBgColor.withValues(alpha: 0.45))
        : (isDark
            ? theme.pageBgColor.withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.88));

    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : AppColors.textSub;

    final borderTopColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : (hasBg ? Colors.white.withValues(alpha: 0.40) : Colors.black.withValues(alpha: 0.05));

    return Material(
      color: Colors.transparent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: barBgColor,
              border: Border(
                top: BorderSide(
                  color: borderTopColor,
                  width: 0.8,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: _items.map((item) {
                  final selected = item.tab == active;
                  return Expanded(
                    child: InkWell(
                      onTap: () => onTap(item.tab),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
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
                                color: selected ? primaryColor : unselectedColor,
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
        ),
      ),
    );
  }
}
