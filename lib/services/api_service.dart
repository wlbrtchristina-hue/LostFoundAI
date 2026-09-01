import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/item_model.dart';
import '../models/match_model.dart';
import 'supabase_service.dart';

/// 后端 API 调用统一异常（页面展示 message 即可）。
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// AI 识别结果（后端 /vision 返回，字段全部可选，缺失给默认值）。
class VisionResult {
  final String category;
  final String color;
  final int quantity;
  final String brand;
  final String material;
  final String specialMark;
  final String description;

  const VisionResult({
    this.category = '',
    this.color = '',
    this.quantity = 1,
    this.brand = '',
    this.material = '',
    this.specialMark = '',
    this.description = '',
  });

  factory VisionResult.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v?.toString() ?? '';
    return VisionResult(
      category: s(json['category']),
      color: s(json['color']),
      quantity: int.tryParse(s(json['quantity'])) ?? 1,
      brand: s(json['brand']),
      material: s(json['material']),
      specialMark: s(json['special_mark']),
      description: s(json['description']),
    );
  }

  /// 是否识别出了可用信息（全空视为识别失败）。
  bool get hasAny => category.isNotEmpty ||
      color.isNotEmpty ||
      brand.isNotEmpty ||
      material.isNotEmpty ||
      specialMark.isNotEmpty ||
      description.isNotEmpty;
}

/// 后端 FastAPI 服务封装（单例）。
///
/// 自动从 Supabase 会话中取 access_token 附加到 Authorization 请求头。
/// 所有方法在失败时抛出 [ApiException]，由页面统一展示。
class ApiService {
  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = SupabaseService.instance.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  static ApiService? _instance;
  late final Dio _dio;

  static ApiService get instance => _instance ??= ApiService._internal();

  /// 发布物品（失物 / 招领）。brand/material/specialMark/quantity 为可选扩展字段。
  Future<ItemModel> postItem({
    required int type,
    required String category,
    required String color,
    required String location,
    required String description,
    required String imageUrl,
    String brand = '',
    String material = '',
    String specialMark = '',
    int quantity = 1,
  }) async {
    final data = await _request(
      () => _dio.post(
        '/items',
        data: {
          'type': type,
          'category': category,
          'color': color,
          'location': location,
          'description': description,
          'image_url': imageUrl,
          'brand': brand,
          'material': material,
          'special_mark': specialMark,
          'quantity': quantity,
        },
      ),
    );
    return ItemModel.fromJson(_pickMap(data, ['item', 'data']) ?? {});
  }

  /// 获取物品列表（支持按类型 / 品类 / 用户筛选）。
  Future<List<ItemModel>> getItems({
    int? type,
    String? category,
    String? userId,
  }) async {
    final data = await _request(
      () => _dio.get(
        '/items',
        queryParameters: {
          if (type != null) 'type': type,
          if (category != null && category.isNotEmpty) 'category': category,
          if (userId != null && userId.isNotEmpty) 'user_id': userId,
        },
      ),
    );
    final list = _pickList(data, ['items', 'data']) ?? [];
    return list
        .map((e) => ItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取当前用户相关的全部匹配记录。
  Future<List<MatchModel>> getMatches() async {
    final data = await _request(() => _dio.get('/matches/me'));
    final list = _pickList(data, ['matches', 'data']) ?? [];
    return list
        .map((e) => MatchModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取单条匹配详情。
  Future<MatchModel> getMatchDetail(String matchId) async {
    final data = await _request(() => _dio.get('/matches/$matchId'));
    return MatchModel.fromJson(_pickMap(data, ['match', 'data']) ?? {});
  }

  /// 确认归还 / 认领：将物品状态置为"已匹配"。
  Future<ItemModel> confirmReturn(String itemId) async {
    final data = await _request(
      () => _dio.patch(
        '/items/$itemId/status',
        data: {'status': 1},
      ),
    );
    return ItemModel.fromJson(_pickMap(data, ['item', 'data']) ?? {});
  }

  /// 图像识别：返回全字段 [VisionResult]（后端 /vision 接口，可能未就绪）。
  Future<VisionResult> visionRecognize(String imageUrl) async {
    final data = await _request(
      () => _dio.post(
        '/vision',
        data: {'image_url': imageUrl},
      ),
    );
    return VisionResult.fromJson(data);
  }

  /// 统一请求入口：把 Dio 异常转换为 [ApiException]。
  Future<Map<String, dynamic>> _request(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final resp = await send();
      if (resp.data is Map<String, dynamic>) {
        return resp.data as Map<String, dynamic>;
      }
      return {'data': resp.data};
    } on DioException catch (e) {
      final msg = _errorMessage(e);
      throw ApiException(msg);
    } catch (e) {
      throw ApiException('网络请求失败：$e');
    }
  }

  static String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return '无法连接服务器，请检查后端是否已启动';
      case DioExceptionType.badResponse:
        return '服务器错误（${e.response?.statusCode}）';
      default:
        return '请求失败：${e.message ?? '未知错误'}';
    }
  }

  /// 在响应 JSON 中按 key 依次查找对象（兼容不同后端包装格式）。
  static Map<String, dynamic>? _pickMap(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final v = json[key];
      if (v is Map<String, dynamic>) return v;
    }
    return null;
  }

  /// 在响应 JSON 中按 key 依次查找列表。
  static List<dynamic>? _pickList(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final v = json[key];
      if (v is List) return v;
    }
    return null;
  }
}
