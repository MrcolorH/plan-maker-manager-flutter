/// 使用指引（对应 guide/guide.vue）
/// 8 篇文章列表 → 文章详情（步骤图文说明）
library;

import 'package:flutter/material.dart';

import '../../data/guide_articles.dart';
import '../../theme/app_theme.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用指引')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: kGuideArticles.map((a) => _articleCard(context, a)).toList(),
      ),
    );
  }

  Widget _articleCard(BuildContext context, GuideArticle a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          AppRoutes.fade<void>(GuideArticlePage(article: a)),
        ),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(a.icon, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(a.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textSub),
            ],
          ),
        ),
      ),
    );
  }
}

/// 文章详情
class GuideArticlePage extends StatelessWidget {
  final GuideArticle article;
  const GuideArticlePage({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(article.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(article.icon, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(article.summary,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...article.steps.asMap().entries.map((e) {
            final i = e.key;
            final step = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(step.text,
                        style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.text)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}