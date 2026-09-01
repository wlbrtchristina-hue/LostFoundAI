import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../services/supabase_service.dart';

/// 拍照 / 相册选图 + 上传到 Supabase Storage。
///
/// 上传成功后返回可公开访问的图片 URL（publicUrl）。
/// 用法示例（发布页）：
/// ```dart
/// await ImagePickerHelper.pickAndUpload(
///   context: context,
///   onImagePicked: (path) => setState(() => _localImagePath = path),
///   onUploading: (u) => setState(() => _uploading = u),
///   onUploaded: (url, error) {
///     if (error != null) { 提示错误 } else { _imageUrl = url; }
///   },
/// );
/// ```
class ImagePickerHelper {
  ImagePickerHelper._();

  static final ImagePicker _picker = ImagePicker();

  static Future<void> pickAndUpload({
    required BuildContext context,
    required void Function(String? imagePath) onImagePicked,
    required void Function(bool uploading) onUploading,
    required void Function(String? publicUrl, String? error) onUploaded,
  }) async {
    // 1. 选择图片来源（拍照 / 相册）
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // 2. 选择图片（压缩到 1280 以内，质量 85%）
    XFile? image;
    try {
      image = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
    } catch (e) {
      onUploaded(null, '打开相机/相册失败：$e');
      return;
    }
    if (image == null) return;

    // 3. 先让页面显示本地缩略图
    onImagePicked(image.path);
    onUploading(true);

    // 4. 上传到 Supabase Storage 桶「images」（需在控制台创建并设为 public）
    try {
      final userId = SupabaseService.instance.currentUserId ?? 'anonymous';
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await image.readAsBytes();
      await SupabaseService.instance.client.storage
          .from(AppConfig.storageBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      final publicUrl = SupabaseService.instance.client.storage
          .from(AppConfig.storageBucket)
          .getPublicUrl(path);
      onUploaded(publicUrl, null);
    } catch (e) {
      onUploaded(
        null,
        '图片上传失败，请检查 Supabase Storage 是否已创建 public 桶「images」：$e',
      );
    } finally {
      onUploading(false);
    }
  }
}
