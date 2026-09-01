import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/constants.dart';
import '../widgets/item_card.dart';

/// 我的页面：用户信息 + 我发布的失物/招领列表。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<ItemModel>> _lostFuture;
  late Future<List<ItemModel>> _foundFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _lostFuture = _load(ItemType.lost);
    _foundFuture = _load(ItemType.found);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<ItemModel>> _load(int type) {
    return ApiService.instance.getItems(userId: 'me', type: type);
  }

  void _reload() {
    setState(() {
      _lostFuture = _load(ItemType.lost);
      _foundFuture = _load(ItemType.found);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = SupabaseService.instance.currentUserEmail ?? '未登录';

    return Column(
      children: [
        // 用户信息头部
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary,
                child: const Icon(Icons.person, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我的账号',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Tab：我发布的失物 / 我发布的招领
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '我发布的失物'), Tab(text: '我发布的招领')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTab(_lostFuture),
              _buildTab(_foundFuture),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(Future<List<ItemModel>> future) {
    return FutureBuilder<List<ItemModel>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '加载失败：${snapshot.error}',
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
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(child: Text('这里还空空的，去发布一条吧'));
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ItemCard(item: item, showStatus: true);
            },
          ),
        );
      },
    );
  }
}
