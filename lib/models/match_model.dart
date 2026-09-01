import 'item_model.dart';

/// 匹配记录数据模型。
///
/// 对应后端 FastAPI `GET /matches/me`、`GET /matches/{id}` 返回的结构：
/// 一条匹配 = 一件失物 + 一件招领 + 相似度得分。
class MatchModel {
  final String id;
  final ItemModel lostItem; // 失物侧物品
  final ItemModel foundItem; // 招领侧物品
  final double similarity; // 0.0 ~ 1.0
  final bool seenLost; // 失物发布者是否已查看
  final bool seenFound; // 招领发布者是否已查看
  final DateTime createdAt;

  const MatchModel({
    required this.id,
    required this.lostItem,
    required this.foundItem,
    required this.similarity,
    required this.seenLost,
    required this.seenFound,
    required this.createdAt,
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    return MatchModel(
      id: json['id']?.toString() ?? '',
      lostItem: ItemModel.fromJson(
        (json['lost_item'] ?? json['lost']) as Map<String, dynamic>? ?? {},
      ),
      foundItem: ItemModel.fromJson(
        (json['found_item'] ?? json['found']) as Map<String, dynamic>? ?? {},
      ),
      similarity: _toDouble(json['similarity']) ?? 0.0,
      seenLost: json['seen_lost'] == true,
      seenFound: json['seen_found'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// 当前用户（按 userId 区分）视角下的"我的物品"。
  ItemModel itemOf(String? userId) {
    if (lostItem.userId == userId) return lostItem;
    return foundItem;
  }

  /// 当前用户视角下的"对方物品"。
  ItemModel counterpartOf(String? userId) {
    if (lostItem.userId == userId) return foundItem;
    return lostItem;
  }

  /// 当前用户视角下是否未读（用于列表高亮）。
  bool isUnreadFor(String? userId) {
    if (lostItem.userId == userId) return !seenLost;
    if (foundItem.userId == userId) return !seenFound;
    return false;
  }

  /// 双方是否都已确认（lost 和 found 物品状态均为 1=已匹配）。
  /// 已完成的匹配从匹配列表隐藏，仅在双方确认后生效。
  bool get isResolved => lostItem.status == 1 && foundItem.status == 1;

  /// 相似度百分比显示，如 85%。
  String get similarityPercent => '${(similarity * 100).round()}%';

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
