import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../models/match_model.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';

/// 匹配详情页：上下分屏展示"我的物品"和"对方物品"，
/// 底部按钮确认归还 / 认领（物品状态置为已匹配）。
class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.matchId});

  final String matchId;

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  late Future<MatchModel> _future;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.getMatchDetail(widget.matchId);
  }

  Future<void> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认归还'),
        content: const Text('确认双方已线下完成归还/认领？物品状态将标记为已匹配。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _confirming = true);
    try {
      // 确认时把"我的物品"标记为已匹配
      final userId = SupabaseService.instance.currentUserId;
      final match = await _future;
      final myItem = match.itemOf(userId);
      await ApiService.instance.confirmReturn(myItem.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已确认，状态更新为已匹配'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // 返回匹配列表
    } on ApiException catch (e) {
      _showSnack('操作失败：${e.message}');
    } catch (e) {
      _showSnack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('匹配详情')),
      body: FutureBuilder<MatchModel>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          final match = snapshot.data!;
          final userId = SupabaseService.instance.currentUserId;
          final myItem = match.itemOf(userId);
          final counterpart = match.counterpartOf(userId);

          return Column(
            children: [
              // 顶部匹配度
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '匹配度 ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      match.similarityPercent,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              // 上下分屏：我的 / 对方
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildItemSection('我的物品', myItem, isMine: true),
                    const SizedBox(height: 16),
                    _buildItemSection('对方物品（可联系详情见描述）', counterpart),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _confirming ? null : _confirm,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _confirming
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(
              _confirming ? '提交中…' : '确认已归还 / 认领',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemSection(String title, ItemModel item, {bool isMine = false}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isMine ? Icons.person : Icons.person_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: item.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image, size: 48),
                            ),
                          )
                        : Container(
                            color:
                                theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported,
                                size: 48),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${item.typeLabel} · ${item.category} · ${item.color}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text(item.location)),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item.description, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
