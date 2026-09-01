import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../widgets/item_card.dart';
import 'item_detail_page.dart';

/// 浏览页：全部物品信息流 + 类型/品类筛选。
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => BrowsePageState();
}

/// 公开 State 供 HomePage 切 tab 时通过 GlobalKey 刷新。
class BrowsePageState extends State<BrowsePage> {
  int? _filterType; // null=全部
  String? _filterCategory; // null=全部品类

  late Future<List<ItemModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ItemModel>> _load() {
    return ApiService.instance.getItems(
      type: _filterType,
      category: _filterCategory,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 供 HomePage 切换 tab 时调用，触发重新加载。
  void reload() => _reload();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: FutureBuilder<List<ItemModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _buildError(snapshot.error.toString());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Center(child: Text('暂无物品，去发布一条吧'));
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ItemCard(
                      item: item,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ItemDetailPage(item: item),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 顶部筛选栏：类型 + 品类
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: _filterType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '类型',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部')),
                DropdownMenuItem(value: ItemType.lost, child: Text('失物')),
                DropdownMenuItem(value: ItemType.found, child: Text('招领')),
              ],
              onChanged: (v) {
                setState(() => _filterType = v);
                _reload();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _filterCategory,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '品类',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('全部品类')),
                ...kCategories.map(
                  (c) => DropdownMenuItem<String?>(value: c, child: Text(c)),
                ),
              ],
              onChanged: (v) {
                setState(() => _filterCategory = v);
                _reload();
              },
            ),
          ),
        ],
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
