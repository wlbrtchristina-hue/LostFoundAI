"""校园失物招领AI助手 — FastAPI 后端。

数据层走 Supabase PostgREST（service_role），表结构见 backend/schema.sql
（需在控制台 SQL Editor 执行一次）。接口契约见前端 README「后端 API 契约」。
运行：cd backend && uvicorn main:app --host 0.0.0.0 --port 8000
"""

import os
from pathlib import Path

import httpx
import uvicorn
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from auth import get_current_user
from db import DB
from matching import find_matches
from vision import VisionUnavailable, recognize

load_dotenv(Path(__file__).resolve().parent / ".env")

db = DB(os.environ["SUPABASE_URL"], os.environ["SERVICE_ROLE_KEY"])

app = FastAPI(title="校园失物招领AI助手")

# 数据库（PostgREST）错误转友好提示
@app.exception_handler(httpx.HTTPStatusError)
async def _db_error_handler(_: object, exc: httpx.HTTPStatusError):
    status = exc.response.status_code
    if status == 404 and "PGRST205" in exc.response.text:
        return JSONResponse(
            status_code=500,
            content={"detail": "数据库未初始化：请在 Supabase 控制台 SQL Editor 执行 backend/schema.sql"},
        )
    return JSONResponse(
        status_code=502,
        content={"detail": f"数据库服务错误（{status}），请稍后重试"},
    )

# 开发期全开 CORS（Flutter web 调试跨端口访问）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------- 数据模型 ----------

class ItemIn(BaseModel):
    type: int = Field(ge=0, le=1, description="0=失物 1=招领")
    category: str = Field(min_length=1, max_length=30)
    color: str = Field(min_length=1, max_length=20)
    location: str = Field(min_length=1, max_length=100)
    description: str = ""
    image_url: str = ""
    brand: str = Field(default="", max_length=30)
    material: str = Field(default="", max_length=20)
    special_mark: str = ""
    quantity: int = Field(default=1, ge=1, le=999)


class StatusIn(BaseModel):
    status: int = Field(ge=0, le=1)


class VisionIn(BaseModel):
    image_url: str = Field(min_length=1)


# ---------- 序列化 ----------

def _iso(value) -> str:
    """created_at：REST 返回已是 ISO 字符串，直连返回 datetime，统一成字符串。"""
    if isinstance(value, str):
        return value
    return value.isoformat()


def item_to_dict(row: dict) -> dict:
    return {
        "id": str(row["id"]),
        "user_id": str(row["user_id"]),
        "type": row["type"],
        "category": row["category"],
        "color": row["color"],
        "quantity": row["quantity"],
        "brand": row["brand"] or "",
        "material": row["material"] or "",
        "special_mark": row["special_mark"] or "",
        "location": row["location"],
        "description": row["description"],
        "image_url": row["image_url"],
        "status": row["status"],
        "created_at": _iso(row["created_at"]),
    }


def match_to_dict(m: dict, lost: dict, found: dict) -> dict:
    return {
        "id": str(m["id"]),
        "similarity": m["similarity"],
        "seen_lost": m["seen_lost"],
        "seen_found": m["seen_found"],
        "created_at": _iso(m["created_at"]),
        "lost_item": item_to_dict(lost),
        "found_item": item_to_dict(found),
    }


# ---------- 物品 ----------

@app.post("/items")
def create_item(body: ItemIn, user_id: str = Depends(get_current_user)):
    item = db.insert_item({
        "user_id": user_id,
        "type": body.type,
        "category": body.category,
        "color": body.color,
        "quantity": body.quantity,
        "brand": body.brand,
        "material": body.material,
        "special_mark": body.special_mark,
        "location": body.location,
        "description": body.description,
        "image_url": body.image_url,
    })

    # 发布后自动匹配：与反类型、待匹配、他人的物品配对
    candidates = db.list_items(
        type=1 - body.type, status=0, exclude_user_id=user_id
    )
    for hit in find_matches(item, candidates):
        cand, s = hit["candidate"], hit["score"]
        lost_id = item["id"] if item["type"] == 0 else cand["id"]
        found_id = item["id"] if item["type"] == 1 else cand["id"]
        db.insert_match(lost_id, found_id, s)

    return {"item": item_to_dict(item)}


@app.get("/items")
def list_items(
    type: int | None = Query(default=None, ge=0, le=1),
    category: str | None = None,
    user_id: str | None = None,
    auth_user: str = Depends(get_current_user),
):
    if user_id == "me":
        user_id = auth_user
    rows = db.list_items(type=type, category=category, user_id=user_id)
    return {"items": [item_to_dict(r) for r in rows]}


@app.patch("/items/{item_id}/status")
def update_item_status(item_id: str, body: StatusIn,
                       user_id: str = Depends(get_current_user)):
    item = db.get_item(item_id)
    if not item:
        raise HTTPException(404, "物品不存在")
    if str(item["user_id"]) != user_id:
        raise HTTPException(403, "只能操作自己发布的物品")
    updated = db.update_item(item_id, {"status": body.status})
    return {"item": item_to_dict(updated)}


# ---------- 匹配 ----------

@app.get("/matches/me")
def list_my_matches(user_id: str = Depends(get_current_user)):
    my_items = db.list_items(user_id=user_id, select="id")
    ids = [r["id"] for r in my_items]
    if not ids:
        return {"matches": []}
    matches = db.list_matches_for(ids)
    item_map = db.items_by_ids(
        list({m["lost_item_id"] for m in matches} | {m["found_item_id"] for m in matches})
    )
    return {
        "matches": [
            match_to_dict(m, item_map[m["lost_item_id"]], item_map[m["found_item_id"]])
            for m in matches
        ]
    }


@app.get("/matches/{match_id}")
def get_match(match_id: str, user_id: str = Depends(get_current_user)):
    m = db.get_match(match_id)
    if not m:
        raise HTTPException(404, "匹配记录不存在")
    items = db.items_by_ids([m["lost_item_id"], m["found_item_id"]])
    lost, found = items.get(m["lost_item_id"]), items.get(m["found_item_id"])
    if lost is None or found is None:
        raise HTTPException(404, "匹配记录不完整")
    if str(lost["user_id"]) != user_id and str(found["user_id"]) != user_id:
        raise HTTPException(403, "无权查看该匹配")
    # 查看即标记已读（请求方那一侧），并同步到响应
    if str(lost["user_id"]) == user_id:
        db.mark_match_seen(match_id, "seen_lost")
        m["seen_lost"] = True
    else:
        db.mark_match_seen(match_id, "seen_found")
        m["seen_found"] = True
    return {"match": match_to_dict(m, lost, found)}


# ---------- 图像识别 ----------

@app.post("/vision")
def vision(body: VisionIn):
    try:
        result = recognize(body.image_url)
    except VisionUnavailable as exc:
        raise HTTPException(503, str(exc))
    return result


# ---------- 健康检查 ----------

@app.get("/")
def health():
    return {"status": "ok", "service": "lost-and-found-backend"}


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000)
