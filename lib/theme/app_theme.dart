/// 应用主题：复刻旧版 uni-app 配色规范（柔和绿 + 米白背景 + 橙色数字点缀）
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppColors {
  // 主色（柔和灰绿）
  static const Color primary = Color(0xFF5BA47C); // 主绿
  static const Color primaryDisabled = Color(0xFFC9DFD3);
  static const Color primaryBg = Color(0xFFE9F3ED); // 浅绿底（chips/完成态卡片）
  static const Color orange = Color(0xFFDB9558); // 柔和橙（时间/kcal/警示数字）
  static const Color orangeBg = Color(0xFFFAF1E7);
  static const Color danger = Color(0xFFE25C50); // 红
  static const Color dangerBg = Color(0xFFFCEEEC);

  // 中性
  static const Color bg = Color(0xFFF6F6F3); // 页面背景（米白）
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF3C3C3E);
  static const Color textSub = Color(0xFFA6A6AA);
  static const Color textFaint = Color(0xFFC6C6C4); // 更弱的说明文字
  static const Color tagBg = Color(0xFFF1F1EE);

  // 图表
  static const Color chartGreen = primary;
  static const Color chartOrange = orange;
  static const Color chartGray = Color(0xFFD8DAD6);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: false,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.card,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: null, // 使用系统字体（iOS: PingFang SC）
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w600),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFEFEFEA), thickness: 0.5),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      // ---- 降低动画强度：去掉水波纹扩散，只留一次性淡灰高亮作为点击反馈 ----
      // 列表里的 InkWell 在滚动时会持续计算 splash 动画，是低端机掉帧的常见来源
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: const Color(0x143C3C3E),
      hoverColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FastPageTransitionsBuilder(),
          TargetPlatform.iOS: FastPageTransitionsBuilder(),
          TargetPlatform.macOS: FastPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// 轻量页面转场：只做淡入，不再叠加默认 300ms 的位移+缩放
/// 实际时长由 [AppRoutes] 的 transitionDuration 控制（默认 160ms）
class FastPageTransitionsBuilder extends PageTransitionsBuilder {
  const FastPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    );
  }
}

/// 统一页面路由：160ms 淡入
/// MaterialPageRoute 默认 300ms 位移动画，在这类轻量内容页上观感偏"重"
class AppRoutes {
  AppRoutes._();

  static const Duration duration = Duration(milliseconds: 160);

  static Route<T> fade<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
  }

  /// 推送页面（淡入）
  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(fade<T>(page));
  }
}

/// 页面顶部居中标题（对应旧版每页的「减肥搭子」标题栏）
class AppPageTitle extends StatelessWidget {
  final String title;
  const AppPageTitle({super.key, this.title = '减肥搭子'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Center(
        child: Text(title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
      ),
    );
  }
}

/// 虚线描边容器（对应旧版 .dashed-btn 的虚线边框效果）
class DashedBorderContainer extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const DashedBorderContainer({
    super.key,
    required this.child,
    this.color = AppColors.primary,
    this.radius = 20,
    this.strokeWidth = 1.2,
    this.dash = 4,
    this.gap = 3,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
        dash: dash,
        gap: gap,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  _DashedRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final len = math.min(dash, metric.length - dist);
        canvas.drawPath(metric.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// 虚线胶囊添加按钮（＋ 今日加餐 / ＋ 导入计划 等，对应旧版 .dashed-btn）
class DashedAddButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final double height;
  final EdgeInsetsGeometry margin;

  const DashedAddButton(
    this.text, {
    super.key,
    this.onTap,
    this.height = 40,
    this.margin = const EdgeInsets.fromLTRB(16, 2, 16, 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(height / 2),
        child: DashedBorderContainer(
          radius: height / 2,
          child: Container(
            height: height,
            alignment: Alignment.center,
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: AppColors.primary)),
          ),
        ),
      ),
    );
  }
}

/// 通用卡片容器（对应 .card）
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.margin, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
    final withMargin = Container(margin: margin ?? const EdgeInsets.only(left: 16, right: 16, bottom: 10), child: content);
    if (onTap == null) return withMargin;
    return GestureDetector(onTap: onTap, child: withMargin);
  }
}

/// 区块标题（对应 .section-title）
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
          ?trailing,
        ],
      ),
    );
  }
}

/// 标签（对应 .tag / .tag-green / .tag-orange / .tag-red）
class Tag extends StatelessWidget {
  final String text;
  final String color; // default | green | orange | red
  const Tag(this.text, {super.key, this.color = 'default'});

  @override
  Widget build(BuildContext context) {
    Color fg, bg;
    switch (color) {
      case 'green':
        fg = AppColors.primary;
        bg = AppColors.primaryBg;
        break;
      case 'orange':
        fg = AppColors.orange;
        bg = AppColors.orangeBg;
        break;
      case 'red':
        fg = AppColors.danger;
        bg = AppColors.dangerBg;
        break;
      default:
        fg = AppColors.textSub;
        bg = AppColors.tagBg;
    }
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}

/// 主按钮（对应 .btn-primary）
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool disabled;
  final double height;
  const PrimaryButton(this.text, {super.key, this.onPressed, this.disabled = false, this.height = 44});

  @override
  Widget build(BuildContext context) {
    final effective = disabled ? null : onPressed;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: effective,
        style: ElevatedButton.styleFrom(
          backgroundColor: disabled ? AppColors.primaryDisabled : AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        child: Text(text),
      ),
    );
  }
}

/// 描边按钮（对应 .btn-plain）
class PlainButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double height;
  const PlainButton(this.text, {super.key, this.onPressed, this.height = 42});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15),
        ),
        child: Text(text),
      ),
    );
  }
}

/// 危险描边按钮（对应 .btn-danger）
class DangerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double height;
  const DangerButton(this.text, {super.key, this.onPressed, this.height = 42});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15),
        ),
        child: Text(text),
      ),
    );
  }
}

/// 空状态（对应 empty-state.vue）
class EmptyState extends StatelessWidget {
  final String icon;
  final String text;
  final String? subText;
  const EmptyState({super.key, this.icon = '📭', required this.text, this.subText});

  @override
  Widget build(BuildContext context) {
    // Center 使整页空态垂直居中（无计划/无数据时内容不再挤在屏幕上方）
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textSub)),
            if (subText != null) ...[
              const SizedBox(height: 4),
              Text(subText!, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
            ],
          ],
        ),
      ),
    );
  }
}
