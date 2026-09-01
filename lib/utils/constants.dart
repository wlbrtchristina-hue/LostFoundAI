import 'package:flutter/material.dart';

/// 全局常量：主题色、品类/颜色选项、类型与状态枚举。
class AppColors {
  AppColors._();

  /// 主题色（蓝色系）
  static const Color primary = Color(0xFF4F6BED);

  /// 失物相关色
  static const Color lost = Color(0xFFE57373);

  /// 招领相关色
  static const Color found = Color(0xFF81C784);

  /// 已匹配状态色
  static const Color matched = Color(0xFF4F6BED);

  /// 未匹配状态色
  static const Color pending = Color(0xFFFFB74D);
}

/// 物品类型：0 = 失物（丢了东西），1 = 招领（捡到东西）
class ItemType {
  ItemType._();

  static const int lost = 0;
  static const int found = 1;

  static String label(int type) => type == lost ? '失物' : '招领';
}

/// 物品状态：0 = 待匹配，1 = 已匹配
class ItemStatus {
  ItemStatus._();

  static const int pending = 0;
  static const int matched = 1;

  static String label(int status) => status == matched ? '已匹配' : '待匹配';
}

/// 物品品类下拉选项（AI 识别的结果也来自此集合）
const List<String> kCategories = [
  '背包',
  '耳机',
  '水杯',
  '雨伞',
  '书本',
  '眼镜',
  '钥匙',
  '充电宝',
  '校园卡',
  '钱包',
  '其他',
];

/// 物品颜色下拉选项（AI 识别的结果也来自此集合）
const List<String> kColors = [
  '黑色',
  '白色',
  '红色',
  '蓝色',
  '绿色',
  '黄色',
  '粉色',
  '灰色',
  '其他',
];

/// 应用名称
const String kAppName = '校园失物招领AI助手';
