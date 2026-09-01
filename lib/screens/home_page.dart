import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/constants.dart';
import 'browse_page.dart';
import 'matches_page.dart';
import 'profile_page.dart';
import 'publish_page.dart';

/// 主页：底部 4 Tab 导航（发布 / 浏览 / 匹配 / 我的）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  static const _titles = ['发布', '浏览', '匹配', '我的'];

  // IndexedStack 下各页常驻，切 tab 时手动触发刷新（否则看到旧数据）
  final _browseKey = GlobalKey<BrowsePageState>();
  final _matchesKey = GlobalKey<MatchesPageState>();

  @override
  Widget build(BuildContext context) {
    final pages = [
      PublishPage(onPublished: _goBrowse),
      BrowsePage(key: _browseKey),
      MatchesPage(key: _matchesKey),
      const ProfilePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0 ? kAppName : _titles[_currentIndex],
        ),
        actions: [
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          // 切到浏览/匹配时刷新（发布后立即可见新物品和匹配）
          if (index == 1) _browseKey.currentState?.reload();
          if (index == 2) _matchesKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: '发布',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '浏览',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: '匹配',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  /// 发布成功后跳到浏览 tab（列表已由 onDestinationSelected 刷新）。
  void _goBrowse() {
    setState(() => _currentIndex = 1);
    _browseKey.currentState?.reload();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await Supabase.instance.client.auth.signOut();
    // 登出后 AuthGate 的 StreamBuilder 会自动切回登录页
  }
}
