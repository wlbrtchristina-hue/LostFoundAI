/// 物品数据模型（失物 / 招领）。
///
/// 对应后端 FastAPI `GET/POST /items` 接口返回的 JSON 结构。
/// 字段全部宽容解析：后端缺字段时给安全默认值（向后兼容旧后端）。
class ItemModel {
  final String id;
  final String userId;
  final int type; // 0=失物, 1=招领（见 utils/constants.dart）
  final String category;
  final String color;
  final int quantity; // 物品数量，默认 1
  final String brand; // 品牌/标识（可选）
  final String material; // 材质（可选）
  final String specialMark; // 特殊标记（可选）
  final String location;
  final String description;
  final String imageUrl;
  final int status; // 0=待匹配, 1=已匹配
  final DateTime createdAt;

  const ItemModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.category,
    required this.color,
    this.quantity = 1,
    this.brand = '',
    this.material = '',
    this.specialMark = '',
    required this.location,
    required this.description,
    required this.imageUrl,
    required this.status,
    required this.createdAt,
  });

  /// 从后端 JSON 解析（容忍字段缺失，缺失时给安全默认值）。
  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      type: _toInt(json['type']) ?? 0,
      category: json['category']?.toString() ?? '其他',
      color: json['color']?.toString() ?? '其他',
      quantity: _toInt(json['quantity']) ?? 1,
      brand: json['brand']?.toString() ?? '',
      material: json['material']?.toString() ?? '',
      specialMark: json['special_mark']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      status: _toInt(json['status']) ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// 类型中文标签（失物 / 招领）
  String get typeLabel => type == 1 ? '招领' : '失物';

  /// 状态中文标签（待匹配 / 已匹配）
  String get statusLabel => status == 1 ? '已匹配' : '待匹配';

  /// 有特征属性时的摘要（用于详情页标签行）
  String get featureSummary => [
        if (brand.isNotEmpty) brand,
        if (material.isNotEmpty) material,
        if (specialMark.isNotEmpty) specialMark,
      ].join(' · ');

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
