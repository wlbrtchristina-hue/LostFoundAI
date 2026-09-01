import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Supabase 客户端单例。
///
/// 在 main() 中调用 [SupabaseService.initialize] 完成初始化，
/// 之后全局通过 `SupabaseService.instance` 获取客户端。
class SupabaseService {
  SupabaseService._();

  static SupabaseService? _instance;

  static SupabaseService get instance => _instance!;

  /// 初始化 Supabase（应用启动时调用一次）。
  static Future<void> initialize() async {
    if (_instance != null) return;
    await AppConfig.load();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    _instance = SupabaseService._();
  }

  SupabaseClient get client => Supabase.instance.client;

  /// 当前用户（未登录为 null）
  User? get currentUser => client.auth.currentUser;

  /// 当前用户 id
  String? get currentUserId => client.auth.currentUser?.id;

  /// 当前用户邮箱
  String? get currentUserEmail => client.auth.currentUser?.email;

  /// 当前 access_token（调用后端 API 时作为 Authorization）
  String? get accessToken => client.auth.currentSession?.accessToken;
}
