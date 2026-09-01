import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 全局配置：从 .env 文件读取。
///
/// 使用前需在 main() 中先调用 [AppConfig.load]（内部会加载 .env）。
/// .env 模板见项目根目录的 .env.example。
class AppConfig {
  AppConfig._();

  static bool _loaded = false;

  /// 加载 .env 文件（应用启动时调用一次）。
  static Future<void> load() async {
    if (_loaded) return;
    await dotenv.load(fileName: '.env');
    _loaded = true;
  }

  /// Supabase 项目 URL，必填（来自 Supabase 控制台 → Settings → API）。
  static String get supabaseUrl => _required('SUPABASE_URL');

  /// Supabase anon public key，必填。
  static String get supabaseAnonKey => _required('SUPABASE_ANON_KEY');

  /// 后端 FastAPI 服务地址。
  /// Android 模拟器访问宿主机 localhost 用 10.0.2.2；
  /// Windows 桌面 / Chrome 调试改为 http://localhost:8000；
  /// 真机调试改为局域网 IP，如 http://192.168.1.100:8000。
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  /// Supabase 图片存储桶名（需在 Supabase Storage 中创建并设为 public）。
  static const String storageBucket = 'images';

  static String _required(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        '缺少环境变量 $key：请在项目根目录创建 .env 文件'
        '（参考 .env.example），并填入真实配置后重启应用。',
      );
    }
    return value;
  }
}
