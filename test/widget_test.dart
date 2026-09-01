import 'package:flutter_test/flutter_test.dart';
import 'package:lost_and_found/models/item_model.dart';
import 'package:lost_and_found/utils/time_ago.dart';

void main() {
  group('ItemModel.fromJson', () {
    test('解析完整字段', () {
      final item = ItemModel.fromJson({
        'id': 'abc-123',
        'user_id': 'user-1',
        'type': 0,
        'category': '背包',
        'color': '黑色',
        'location': '图书馆三楼',
        'description': '黑色双肩背包',
        'image_url': 'https://example.com/a.jpg',
        'status': 1,
        'created_at': '2026-08-31T10:00:00Z',
      });
      expect(item.id, 'abc-123');
      expect(item.type, 0);
      expect(item.category, '背包');
      expect(item.status, 1);
      expect(item.typeLabel, '失物');
      expect(item.statusLabel, '已匹配');
    });

    test('缺失字段时使用安全默认值', () {
      final item = ItemModel.fromJson({'id': 'x'});
      expect(item.category, '其他');
      expect(item.status, 0);
      expect(item.imageUrl, '');
    });

    test('数字以字符串返回时也能解析', () {
      final item = ItemModel.fromJson({'type': '1', 'status': '0'});
      expect(item.type, 1);
      expect(item.status, 0);
      expect(item.typeLabel, '招领');
    });
  });

  group('timeAgo', () {
    final now = DateTime.parse('2026-08-31T12:00:00Z');

    test('一分钟内为"刚刚"', () {
      expect(
        timeAgo(now.subtract(const Duration(seconds: 30)), now: now),
        '刚刚',
      );
    });

    test('分钟/小时/天', () {
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5分钟前');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3小时前');
      expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2天前');
    });

    test('超过一个月显示日期', () {
      final old = now.subtract(const Duration(days: 60));
      expect(timeAgo(old, now: now), '2026-07-02');
    });
  });
}
