# 校园失物招领AI助手 — Flutter 前端 + FastAPI 后端

跨平台移动端（Android / iOS）：登录注册 → 拍照发布失物/招领 → AI 一键识别（品类/颜色/数量/品牌/材质/特殊标记/描述）→ 浏览信息流 → 匹配结果 → **匹配双方站内聊天** → 确认归还。

`backend/` 为 FastAPI 后端（本轮已实现，数据层走 Supabase PostgREST + service_role）；若团队分工变化，后端也可由成员B维护。

## 环境准备

1. 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)（3.x，本仓库用 3.47.2 验证）
2. 安装 Android Studio（运行 Android 模拟器需要）；或使用 Chrome（`flutter run -d chrome` 仅验证 UI）
3. 国内网络建议配置镜像（加速下载与 pub 依赖）：
   ```bash
   setx FLUTTER_STORAGE_BASE_URL https://storage.flutter-io.cn
   setx PUB_HOSTED_URL https://pub.flutter-io.cn
   ```

## 快速开始

```bash
# 1. 首次：生成平台脚手架（不覆盖已有 lib/ 与 pubspec.yaml）
flutter create . --project-name lost_and_found --org com.campus

# 2. 安装依赖
flutter pub get

# 3. 配置环境变量：复制 .env.example 为 .env，填入真实值
cp .env.example .env

# 4. 运行（Android 模拟器 / 真机 / Chrome）
flutter run
```

## 项目结构

```
lib/
├── main.dart                     # 入口：Supabase 初始化 + 登录态路由
├── config/app_config.dart        # 读 .env：Supabase / 后端地址
├── models/
│   ├── item_model.dart           # 物品模型（失物/招领）
│   └── match_model.dart          # 匹配记录模型
├── services/
│   ├── supabase_service.dart     # Supabase 客户端单例
│   └── api_service.dart          # 后端 FastAPI 调用（Dio + Token）
├── utils/
│   ├── constants.dart            # 品类/颜色/类型/状态常量
│   ├── image_picker_helper.dart  # 拍照/选图 + 上传 Storage
│   └── time_ago.dart             # 中文相对时间
├── screens/
│   ├── auth/                     # 登录 / 注册
│   ├── home_page.dart            # 底部 4 Tab 框架
│   ├── publish_page.dart         # 发布（拍照上传 + AI 识别 + 提交）
│   ├── browse_page.dart          # 浏览信息流 + 筛选
│   ├── item_detail_page.dart     # 物品详情
│   ├── matches_page.dart         # 匹配列表（未读高亮）
│   ├── match_detail_page.dart    # 匹配详情 + 确认归还
│   └── profile_page.dart         # 我的（发布历史 + 状态）
└── widgets/item_card.dart        # 物品卡片（复用）
```

## Supabase 配置（一次性）

在 [app.supabase.com](https://app.supabase.com) 创建项目后：

1. **Auth → Authentication → Sign In / Up**：启用 Email 提供商；
   测试阶段建议关闭 "Confirm email"（否则注册后需点邮件链接）
2. **Storage → Create bucket**：桶名 `images`，勾选 **Public**（图片公开访问）
3. **Settings → API**：复制 Project URL 和 anon public key 到 `.env`；
   复制 service_role secret 到 `backend/.env` 的 `SERVICE_ROLE_KEY`
4. **SQL Editor → New query**：粘贴执行 `backend/schema.sql`（创建 `items`/`matches` 表）
5. **SQL Editor → New query**：再执行一次 `backend/storage_policies.sql`
   （给 `storage.objects` 加 RLS 策略，否则应用内图片上传会 403 "violates row level security policy"）
6. **SQL Editor → New query**：执行 `backend/chat_schema.sql`（聊天消息表 + RLS + Realtime 发布；
   聊天直连 Supabase，后端无需改动）

> 后端认证由 Supabase 管理，Flutter 通过 `supabase_flutter` 登录后拿到 JWT；
> 调用后端 API 时自动附加 `Authorization: Bearer <token>`，后端用 Supabase JWT 验证身份
> （GoTrue 新版签发 ES256 token，后端按 kid 匹配 JWKS 公钥验签）。

## 后端启动

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

`backend/.env` 需配置：`SUPABASE_URL`、`SERVICE_ROLE_KEY`、`DEEPSEEK_API_KEY`（/vision 用）、`VISION_MODEL`。
数据层走 Supabase PostgREST（service_role 绕过 RLS）；2026 新架构下 `db.<ref>.supabase.co` 直连主机已不存在。

## 后端 API 契约

所有接口需 `Authorization: Bearer <Supabase JWT>`，Base URL 见 `.env` 的 `API_BASE_URL`。

| 方法 | 路径 | 请求体 / 参数 | 成功响应 |
|------|------|--------------|----------|
| POST | `/items` | `{type: 0\|1, category, color, location, description, image_url, brand?, material?, special_mark?, quantity?}` | `{item: {...}}` |
| GET | `/items` | 可选 `type`、`category`、`user_id`（`me`=当前用户）、`status`（0=待匹配 1=已匹配） | `{items: [...]}` |
| DELETE | `/items/{id}` | —（仅物品发布者可删） | `{deleted: true}`（关联匹配级联删除） |
| PATCH | `/items/{id}/status` | `{status: 1}` | `{item: {...}}` |
| GET | `/matches/me` | — | `{matches: [...]}`（物品已删除的匹配自动跳过） |
| GET | `/matches/{id}` | — | `{match: {...}}`（查看即把请求方一侧 seen 置 true） |
| POST | `/vision` | `{image_url}` | `{category, color, quantity, brand, material, special_mark, description}` |

**物品 item 字段**：`id, user_id, type(0失物/1招领), category, color, quantity, brand, material, special_mark, location, description, image_url, status(0待匹配/1已匹配), created_at`

**匹配 match 字段**：`id, lost_item{item...}, found_item{item...}, similarity(0~1), seen_lost, seen_found, created_at`

**匹配算法 v1**：品类相同 +0.5、颜色相同 +0.3、品牌相同 +0.1、描述字符相似 +0.1，≥0.5 建匹配记录；
`items.embedding` 向量列已预留（DeepSeek 无 embedding 接口，后续可接入其他模型替换评分）。

> 前端对响应做了容错（兼容 `{item}` 与 `{data}` 包装、`lost_item` 与 `lost` 命名），后端按上表返回即可。
> `/vision` 未配置 Key 或失败时返回 503，前端降级为手动填写 + 重试，不影响发布主流程。

## 常见问题

- **登录/注册报错**：检查 `.env` 的 SUPABASE_URL / SUPABASE_ANON_KEY 是否填对，Auth 是否启用 Email 提供商
- **图片上传失败（403 "new row violates row level security policy"）**：桶已创建但 `storage.objects` 缺 RLS 策略，在 SQL Editor 执行一次 `backend/storage_policies.sql`
- **图片上传失败**：确认 Supabase Storage 已创建 **public** 桶 `images`
- **列表加载失败"无法连接服务器"**：后端未启动，或 Android 真机需把 `API_BASE_URL` 改为电脑局域网 IP；模拟器用 `10.0.2.2` 指向宿主机
- **AI 识别提示失败**：后端 `/vision` 尚未实现，属预期降级行为，可手动选择品类/颜色
- **Android 明文 HTTP**：本项目已在 Manifest 开启 `usesCleartextTraffic`，`http://10.0.2.2:8000` 可直接访问
