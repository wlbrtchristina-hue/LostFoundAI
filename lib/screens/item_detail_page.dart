import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../utils/constants.dart';
import '../utils/time_ago.dart';

/// 物品详情页：大图 + 完整信息 + 状态。
class ItemDetailPage extends StatelessWidget {
  const ItemDetailPage({super.key, required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('物品详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 大图
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: item.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image, size: 64),
                      ),
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported, size: 64),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          // 标签行
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag(item.typeLabel, item.type == ItemType.lost
                  ? AppColors.lost
                  : AppColors.found),
              _tag('${item.category} · ${item.color}', AppColors.primary),
              _tag(item.statusLabel, item.status == ItemStatus.matched
                  ? AppColors.matched
                  : AppColors.pending),
            ],
          ),
          const SizedBox(height: 16),
          // 特征属性（品牌/材质/特殊标记/数量，非空才展示）
          if (item.quantity > 1 || item.featureSummary.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.quantity > 1) _tag('数量 ${item.quantity}', Colors.indigo),
                if (item.brand.isNotEmpty) _tag('品牌 ${item.brand}', AppColors.primary),
                if (item.material.isNotEmpty) _tag('材质 ${item.material}', AppColors.primary),
                if (item.specialMark.isNotEmpty) _tag('标记 ${item.specialMark}', AppColors.primary),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // 地点 + 时间
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(item.location, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                '发布于 ${timeAgo(item.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 描述
          Text('物品描述', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            item.description.isEmpty ? '（无描述）' : item.description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}
