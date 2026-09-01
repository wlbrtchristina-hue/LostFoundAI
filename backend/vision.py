"""图像识别：调 DeepSeek 视觉模型（deepseek-v4-flash-vision-exp），返回严格 JSON。

未配置 API Key 或识别失败时抛 VisionUnavailable（main.py 转 502/503，
前端收到错误后降级为手动选择，不影响发布主流程）。
"""

import json
import os
import re

import httpx

CATEGORIES = ["背包", "耳机", "水杯", "雨伞", "书本", "眼镜", "钥匙",
              "充电宝", "校园卡", "钱包", "其他"]
COLORS = ["黑色", "白色", "红色", "蓝色", "绿色", "黄色", "粉色", "灰色", "其他"]

SYSTEM_PROMPT = """你是校园失物招领系统的物品识别助手。请识别图片中的物品，只返回一个 JSON 对象，不要输出任何其他文字或解释。

JSON 字段：
- category: 物品品类，必须从以下列表中选一个：{categories}
- color: 物品主色调，必须从以下列表中选一个：{colors}
- quantity: 物品数量（正整数，如 1、2；一串钥匙填 1）
- brand: 品牌或物品上的文字标识（如 Sony、小米、湖大校徽），没有则为空字符串
- material: 主要材质（如 皮质、塑料、金属、布料、硅胶），不确定则为空字符串
- special_mark: 特殊标记（划痕、贴纸、挂件等），没有则为空字符串
- description: 用通顺的中文把以上信息组成一段 2~4 句的物品描述（第一人称省略，直接描述物品）

示例输出：{{"category":"耳机","color":"黑色","quantity":1,"brand":"Sony","material":"塑料","special_mark":"左耳外壳有轻微划痕","description":"黑色 Sony 降噪耳机，左耳外壳有轻微划痕，配充电盒。"}}"""


class VisionUnavailable(Exception):
    """识别不可用（未配置 / 调用失败 / 返回无法解析）。"""


def _extract_json(text: str) -> dict:
    text = text.strip()
    # 去掉可能的 ```json ... ``` 围栏
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # 兜底：截取第一个 { 到最后一个 }
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            return json.loads(text[start:end + 1])
        raise


def recognize(image_url: str) -> dict:
    """识别图片，返回 {category, color, quantity, brand, material, special_mark, description}。"""
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        raise VisionUnavailable("后端未配置 DEEPSEEK_API_KEY，无法进行 AI 识别")

    model = os.environ.get("VISION_MODEL", "deepseek-v4-flash-vision-exp").strip()
    body = {
        "model": model,
        "temperature": 0.1,
        "max_tokens": 512,
        "response_format": {"type": "json_object"},
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": SYSTEM_PROMPT.format(
                    categories="、".join(CATEGORIES), colors="、".join(COLORS))},
                {"type": "image_url", "image_url": {"url": image_url}},
            ],
        }],
    }
    try:
        resp = httpx.post(
            "https://api.deepseek.com/chat/completions",
            json=body,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=60,
        )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
    except httpx.HTTPStatusError as exc:
        raise VisionUnavailable(f"AI 识别服务返回错误（{exc.response.status_code}）") from exc
    except (httpx.RequestError, KeyError, IndexError) as exc:
        raise VisionUnavailable("AI 识别服务调用失败") from exc

    try:
        result = _extract_json(content)
    except (json.JSONDecodeError, ValueError) as exc:
        raise VisionUnavailable("AI 识别结果无法解析，请稍后重试") from exc

    # 字段兜底：缺啥给啥，前端全部可空
    return {
        "category": str(result.get("category") or "").strip(),
        "color": str(result.get("color") or "").strip(),
        "quantity": _to_int(result.get("quantity"), 1),
        "brand": str(result.get("brand") or "").strip(),
        "material": str(result.get("material") or "").strip(),
        "special_mark": str(result.get("special_mark") or "").strip(),
        "description": str(result.get("description") or "").strip(),
    }


def _to_int(value, default: int) -> int:
    try:
        return max(1, int(value))
    except (TypeError, ValueError):
        return default
