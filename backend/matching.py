"""匹配算法 v1：规则评分（无 embedding，DeepSeek 无向量接口）。

品类相同 +0.5、颜色相同 +0.3、品牌相同 +0.1、描述字符 Jaccard 相似 +0.1。
>= THRESHOLD 时建匹配记录。embedding 列已预留，后续接入向量模型可替换评分。
"""

from typing import Dict

SCORE_CATEGORY = 0.5
SCORE_COLOR = 0.3
SCORE_BRAND = 0.1
SCORE_DESCRIPTION = 0.1
THRESHOLD = 0.5


def score(a: Dict, b: Dict) -> float:
    """计算两条物品记录的匹配度（0~1）。"""
    s = 0.0

    def _eq(field: str, weight: float):
        nonlocal s
        va = (a.get(field) or "").strip()
        vb = (b.get(field) or "").strip()
        if va and vb and va == vb and va not in ("其他",):
            s += weight

    _eq("category", SCORE_CATEGORY)
    _eq("color", SCORE_COLOR)
    _eq("brand", SCORE_BRAND)

    # 描述相似度：字符集合 Jaccard（中文场景下比分词简单可靠）
    ka = {ch for ch in (a.get("description") or "") if ch.strip()}
    kb = {ch for ch in (b.get("description") or "") if ch.strip()}
    if ka and kb:
        s += SCORE_DESCRIPTION * len(ka & kb) / len(ka | kb)

    return round(min(s, 1.0), 3)


def find_matches(new_item: Dict, candidates: list[Dict]) -> list[Dict]:
    """对候选物品评分，返回达标记录：[{candidate, score}]。"""
    out = []
    for cand in candidates:
        s = score(new_item, cand)
        if s >= THRESHOLD:
            out.append({"candidate": cand, "score": s})
    out.sort(key=lambda x: x["score"], reverse=True)
    return out
