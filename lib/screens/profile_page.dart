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
  int? _lostStatus; // null=全部（状态筛选）
  int? _foundStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _lostFuture = _load(ItemType.lost, _lostStatus);
    _foundFuture = _load(ItemType.found, _foundStatus);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<ItemModel>> _load(int type, int? status) {
    return ApiService.instance.getItems(userId: 'me', type: type, status: status);
  }

  void _reload() {
    setState(() {
      _lostFuture = _load(ItemType.lost, _lostStatus);
      _foundFuture = _load(ItemType.found, _foundStatus);
    });
  }

  void _setStatusFilter(int type, int? status) {
    setState(() {
      if (type == ItemType.lost) {
        _lostStatus = status;
        _lostFuture = _load(type, status);
      } else {
        _foundStatus = status;
        _foundFuture = _load(type, status);
      }
    });
  }

  /// 状态筛选栏：全部 / 待匹配 / 已匹配
  Widget _buildStatusFilter(int type) {
    final current = type == ItemType.lost ? _lostStatus : _foundStatus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _statusChip(type, '全部', null, current),
          const SizedBox(width: 8),
          _statusChip(type, '待匹配', ItemStatus.pending, current),
          const SizedBox(width: 8),
          _statusChip(type, '已匹配', ItemStatus.matched, current),
        ],
      ),
    );
  }

  Widget _statusChip(int type, String label, int? value, int? current) {
    return ChoiceChip(
      label: Text(label),
      selected: current == value,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => _setStatusFilter(type, value),
    );
  }

  Future<void> _confirmDelete(ItemModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除${item.typeLabel}'),
        content: const Text('删除后不可恢复，相关的匹配记录也会一并删除。确定删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.instance.deleteItem(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除'), backgroundColor: Colors.green),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${e.message}'), backgroundColor: Colors.red.shade400),
      );
    }
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
              _buildTab(_lostFuture, type: ItemType.lost),
              _buildTab(_foundFuture, type: ItemType.found),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(Future<List<ItemModel>> future, {required int type}) {
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
        return Column(
          children: [
            _buildStatusFilter(type),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('这里还空空的，去发布一条吧'))
                  : RefreshIndicator(
                      onRefresh: () async => _reload(),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ItemCard(
                            item: item,
                            showStatus: true,
                            onDelete: () => _confirmDelete(item),
                          );
                        },
                      ),
                    ),
              ),
          ],
        );
      },
    );
  }
}
