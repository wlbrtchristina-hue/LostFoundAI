import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/image_picker_helper.dart';

/// 发布页（核心页面，方案A：AI 优先）：
/// 选图上传 → 自动 AI 识别全字段（品类/颜色/数量/品牌/材质/特殊标记/描述）
/// → 结果作为可编辑草稿供用户校对 → 提交。
/// AI 识别失败时降级为纯手动填写，主流程不中断。
class PublishPage extends StatefulWidget {
  const PublishPage({super.key});

  @override
  State<PublishPage> createState() => _PublishPageState();
}

/// AI 识别状态
enum _AiStatus { idle, recognizing, success, failed }

class _PublishPageState extends State<PublishPage> {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _brandController = TextEditingController();
  final _materialController = TextEditingController();
  final _specialMarkController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  int _type = ItemType.lost; // 0=失物 1=招领
  String? _localImagePath; // 本地预览路径
  String? _imageUrl; // 上传成功后的 publicUrl
  bool _uploading = false;

  String? _selectedCategory;
  String? _selectedColor;
  bool _submitting = false;

  _AiStatus _aiStatus = _AiStatus.idle;
  String _aiMessage = '';

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _brandController.dispose();
    _materialController.dispose();
    _specialMarkController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // ---------- 图片选择 + 上传 ----------

  void _pickImage() {
    ImagePickerHelper.pickAndUpload(
      context: context,
      onImagePicked: (path) => setState(() => _localImagePath = path),
      onUploading: (uploading) => setState(() => _uploading = uploading),
      onUploaded: (url, error) {
        if (!mounted) return;
        if (error != null) {
          setState(() {
            _aiStatus = _AiStatus.idle;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red.shade400),
          );
          return;
        }
        setState(() => _imageUrl = url);
        // 上传成功 → 自动触发 AI 识别（方案A：拍照即识别）
        _autoRecognize();
      },
    );
  }

  // ---------- AI 识别（一次识别全部字段） ----------

  Future<void> _autoRecognize() async {
    final url = _imageUrl;
    if (url == null) return;
    setState(() {
      _aiStatus = _AiStatus.recognizing;
      _aiMessage = 'AI 正在识别图片…';
    });
    try {
      final result = await ApiService.instance.visionRecognize(url);
      if (!mounted) return;
      setState(() {
        _aiStatus = result.hasAny ? _AiStatus.success : _AiStatus.failed;
        _aiMessage = result.hasAny
            ? 'AI 识别完成，以下信息为草稿，请校对修改'
            : 'AI 未能识别出可用信息，请手动填写';
        _applyVisionResult(result);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _aiStatus = _AiStatus.failed;
        _aiMessage = 'AI 识别失败（${e.message}），可手动填写或重试';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiStatus = _AiStatus.failed;
        _aiMessage = 'AI 识别失败，可手动填写或重试';
      });
    }
  }

  /// 把识别结果回填到表单（仅回填非空且合法的值，不覆盖用户已填写内容）。
  void _applyVisionResult(VisionResult result) {
    if (result.category.isNotEmpty && kCategories.contains(result.category)) {
      _selectedCategory = result.category;
    }
    if (result.color.isNotEmpty && kColors.contains(result.color)) {
      _selectedColor = result.color;
    }
    if (result.quantity > 1) {
      _quantityController.text = '${result.quantity}';
    }
    if (result.brand.isNotEmpty) _brandController.text = result.brand;
    if (result.material.isNotEmpty) _materialController.text = result.material;
    if (result.specialMark.isNotEmpty) {
      _specialMarkController.text = result.specialMark;
    }
    if (result.description.isNotEmpty) {
      _descriptionController.text = result.description;
    }
  }

  // ---------- 提交 ----------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageUrl == null) {
      _showSnack('请先拍照或选择图片');
      return;
    }
    if (_selectedCategory == null) {
      _showSnack('请选择品类');
      return;
    }
    if (_selectedColor == null) {
      _showSnack('请选择颜色');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.instance.postItem(
        type: _type,
        category: _selectedCategory!,
        color: _selectedColor!,
        location: _locationController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: _imageUrl!,
        brand: _brandController.text.trim(),
        material: _materialController.text.trim(),
        specialMark: _specialMarkController.text.trim(),
        quantity: int.tryParse(_quantityController.text.trim()) ?? 1,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('发布成功！'),
          backgroundColor: Colors.green,
        ),
      );
      _resetForm();
    } on ApiException catch (e) {
      _showSnack('发布失败：${e.message}');
    } catch (e) {
      _showSnack('发布失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _locationController.clear();
    _descriptionController.clear();
    _brandController.clear();
    _materialController.clear();
    _specialMarkController.clear();
    _quantityController.text = '1';
    setState(() {
      _type = ItemType.lost;
      _localImagePath = null;
      _imageUrl = null;
      _selectedCategory = null;
      _selectedColor = null;
      _aiStatus = _AiStatus.idle;
      _aiMessage = '';
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTypeSwitcher(),
            const SizedBox(height: 16),
            _buildImagePicker(),
            const SizedBox(height: 12),
            _buildAiStatusBar(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildCategoryField()),
                const SizedBox(width: 12),
                Expanded(child: _buildColorField()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildQuantityField()),
                const SizedBox(width: 12),
                Expanded(child: _buildBrandField()),
              ],
            ),
            const SizedBox(height: 16),
            _buildMaterialField(),
            const SizedBox(height: 16),
            _buildSpecialMarkField(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: '地点 *',
                hintText: '如：图书馆三楼、第二食堂',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写地点' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '描述（选填，AI 已生成草稿可修改）',
                hintText: '补充物品特征、时间等细节，便于匹配',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _submitting ? '提交中…' : '发布${ItemType.label(_type)}信息',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 失物 / 招领切换
  Widget _buildTypeSwitcher() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: ItemType.lost,
          label: Text('发布失物'),
          icon: Icon(Icons.search_off),
        ),
        ButtonSegment(
          value: ItemType.found,
          label: Text('发布招领'),
          icon: Icon(Icons.favorite_outline),
        ),
      ],
      selected: {_type},
      onSelectionChanged: (selection) =>
          setState(() => _type = selection.first),
    );
  }

  /// 图片选择 + 上传 + 预览
  Widget _buildImagePicker() {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _uploading ? null : _pickImage,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_localImagePath != null)
              Image.file(
                File(_localImagePath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image, size: 48)),
              )
            else
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('拍照 / 从相册选择', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 4),
                  Text(
                    '选择图片后 AI 自动识别，拍照即发布',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            if (_uploading)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 8),
                      Text('图片上传中…', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            if (_imageUrl != null && !_uploading)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '已上传',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// AI 识别状态条：识别中 / 成功（提示校对）/ 失败（可重试）
  Widget _buildAiStatusBar() {
    final theme = Theme.of(context);
    final Widget content;
    switch (_aiStatus) {
      case _AiStatus.recognizing:
        content = const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 8),
            Expanded(child: Text('AI 识别中…', style: TextStyle(color: Colors.white))),
          ],
        );
      case _AiStatus.success:
        content = Text(
          '✓ $_aiMessage',
          style: const TextStyle(color: Color(0xFF1B5E20)),
        );
      case _AiStatus.failed:
        content = Row(
          children: [
            Expanded(
              child: Text(
                '⚠ $_aiMessage',
                style: const TextStyle(color: Color(0xFF8D4E00)),
              ),
            ),
            TextButton(
              onPressed: _uploading ? null : _autoRecognize,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8D4E00),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('重试'),
            ),
          ],
        );
      case _AiStatus.idle:
        return const SizedBox.shrink();
    }

    final color = switch (_aiStatus) {
      _AiStatus.recognizing => theme.colorScheme.primary,
      _AiStatus.success => const Color(0xFFDCEDC8),
      _AiStatus.failed => const Color(0xFFFFF3E0),
      _AiStatus.idle => theme.colorScheme.surfaceContainerHighest,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }

  /// 品类下拉
  Widget _buildCategoryField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('category-$_selectedCategory'),
      initialValue: _selectedCategory,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '品类 *',
        prefixIcon: Icon(Icons.category_outlined),
        border: OutlineInputBorder(),
      ),
      items: kCategories
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: (v) => setState(() => _selectedCategory = v),
      validator: (v) => v == null ? '请选择品类' : null,
    );
  }

  /// 颜色下拉
  Widget _buildColorField() {
    return DropdownButtonFormField<String>(
      key: ValueKey('color-$_selectedColor'),
      initialValue: _selectedColor,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '颜色 *',
        prefixIcon: Icon(Icons.palette_outlined),
        border: OutlineInputBorder(),
      ),
      items: kColors
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: (v) => setState(() => _selectedColor = v),
      validator: (v) => v == null ? '请选择颜色' : null,
    );
  }

  /// 数量
  Widget _buildQuantityField() {
    return TextFormField(
      controller: _quantityController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '数量',
        prefixIcon: Icon(Icons.numbers),
        border: OutlineInputBorder(),
      ),
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n == null || n < 1) return '请输入 ≥1 的整数';
        return null;
      },
    );
  }

  /// 品牌 / 标识（AI 预填，可改）
  Widget _buildBrandField() {
    return TextFormField(
      controller: _brandController,
      maxLength: 30,
      decoration: const InputDecoration(
        labelText: '品牌 / 标识（选填）',
        hintText: '如：Sony、小米、湖大校徽',
        prefixIcon: Icon(Icons.branding_watermark_outlined),
        counterText: '',
        border: OutlineInputBorder(),
      ),
    );
  }

  /// 材质
  Widget _buildMaterialField() {
    return TextFormField(
      controller: _materialController,
      maxLength: 20,
      decoration: const InputDecoration(
        labelText: '材质（选填）',
        hintText: '如：皮质、塑料、金属',
        prefixIcon: Icon(Icons.auto_awesome_outlined),
        counterText: '',
        border: OutlineInputBorder(),
      ),
    );
  }

  /// 特殊标记
  Widget _buildSpecialMarkField() {
    return TextFormField(
      controller: _specialMarkController,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: '特殊标记（选填）',
        hintText: '如：左下有划痕、挂着小熊挂件',
        prefixIcon: Icon(Icons.star_outline),
        border: OutlineInputBorder(),
      ),
    );
  }
}
