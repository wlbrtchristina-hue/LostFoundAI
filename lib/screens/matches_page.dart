import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/match_model.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/time_ago.dart';
import 'match_detail_page.dart';

/// 匹配结果页：展示当前用户相关的所有匹配记录，未读高亮。
class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => MatchesPageState();
}

/// 公开 State 供 HomePage 切 tab 时通过 GlobalKey 刷新。
class MatchesPageState extends State<MatchesPage> {
  late Future<List<MatchModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.getMatches();
  }

  void _reload() {
    setState(() => _future = ApiService.instance.getMatches());
  }

  /// 供 HomePage 切换 tab 时调用，触发重新加载。
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MatchModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildError(snapshot.error.toString());
        }
        final matches = snapshot.data ?? [];
        if (matches.isEmpty) {
          return const Center(child: Text('暂无匹配结果，发布物品后会在这里看到配对'));
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              return _buildMatchCard(match);
            },
          ),
        );
      },
    );
  }

  Widget _buildMatchCard(MatchModel match) {
    final theme = Theme.of(context);
    final userId = SupabaseService.instance.currentUserId;
    final unread = match.isUnreadFor(userId);
    final counterpart = match.counterpartOf(userId);

    return Card(
      color: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MatchDetailPage(matchId: match.id),
            ),
          );
          _reload();
        },
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: counterpart.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: counterpart.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  )
                : Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child:
                        const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
          ),
        ),
        title: Row(
          children: [
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Text(
                '${counterpart.category} · ${counterpart.color}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('对方发布于 ${timeAgo(counterpart.createdAt)} · ${counterpart.location}'),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('匹配度', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  match.similarityPercent,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '加载失败：$message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _reload, child: const Text('重试')),
        ],
      ),
    );
  }
}
