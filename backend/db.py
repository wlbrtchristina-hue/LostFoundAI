"""数据层：通过 Supabase PostgREST（REST API）访问，使用 service_role 密钥。

背景：2026 新架构下 `db.<ref>.supabase.co` 直连主机已不存在，改用 REST 是
官方推荐方式；表结构需先在控制台 SQL Editor 执行一次 `backend/schema.sql`。
service_role 绕过 RLS，可全量读写。
"""

import httpx


class DB:
    def __init__(self, url: str, service_role_key: str):
        self._client = httpx.Client(
            base_url=url.rstrip("/") + "/rest/v1",
            headers={
                "apikey": service_role_key,
                "Authorization": f"Bearer {service_role_key}",
                "Content-Type": "application/json",
            },
            timeout=20,
        )

    # ---------- items ----------

    def insert_item(self, data: dict) -> dict:
        resp = self._client.post(
            "/items",
            json=data,
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return resp.json()[0]

    def get_item(self, item_id: str) -> dict | None:
        resp = self._client.get("/items", params={"select": "*", "id": f"eq.{item_id}"})
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    def list_items(
        self,
        type: int | None = None,
        category: str | None = None,
        user_id: str | None = None,
        exclude_user_id: str | None = None,
        status: int | None = None,
        select: str = "*",
    ) -> list[dict]:
        params = {"select": select, "order": "created_at.desc"}
        if type is not None:
            params["type"] = f"eq.{type}"
        if category:
            params["category"] = f"eq.{category}"
        if user_id:
            params["user_id"] = f"eq.{user_id}"
        if exclude_user_id:
            params["user_id"] = f"neq.{exclude_user_id}"
        if status is not None:
            params["status"] = f"eq.{status}"
        resp = self._client.get("/items", params=params)
        resp.raise_for_status()
        return resp.json()

    def update_item(self, item_id: str, data: dict) -> dict:
        resp = self._client.patch(
            f"/items?id=eq.{item_id}",
            json=data,
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return resp.json()[0]

    def delete_item(self, item_id: str) -> bool:
        """删除物品，返回是否真的删掉了（False=不存在）。关联 matches 由外键级联删除。"""
        resp = self._client.delete(
            f"/items?id=eq.{item_id}",
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return len(resp.json()) > 0

    # ---------- matches ----------

    def insert_match(self, lost_item_id: str, found_item_id: str, similarity: float) -> None:
        # 去重（等价 ON CONFLICT DO NOTHING）：已存在则跳过
        dup = self._client.get(
            "/matches",
            params={
                "select": "id",
                "lost_item_id": f"eq.{lost_item_id}",
                "found_item_id": f"eq.{found_item_id}",
            },
        )
        dup.raise_for_status()
        if dup.json():
            return
        resp = self._client.post(
            "/matches",
            json={
                "lost_item_id": lost_item_id,
                "found_item_id": found_item_id,
                "similarity": similarity,
            },
        )
        resp.raise_for_status()

    def list_matches_for(self, item_ids: list[str]) -> list[dict]:
        """查询涉及这些物品的所有匹配（按时间倒序）。"""
        ids = ",".join(item_ids)
        resp = self._client.get(
            "/matches",
            params={
                "select": "*",
                "or": f"(lost_item_id.in.({ids}),found_item_id.in.({ids}))",
                "order": "created_at.desc",
            },
        )
        resp.raise_for_status()
        return resp.json()

    def get_match(self, match_id: str) -> dict | None:
        resp = self._client.get(
            "/matches", params={"select": "*", "id": f"eq.{match_id}"}
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    def mark_match_seen(self, match_id: str, field: str) -> None:
        resp = self._client.patch(f"/matches?id=eq.{match_id}", json={field: True})
        resp.raise_for_status()

    def items_by_ids(self, ids: list[str]) -> dict[str, dict]:
        """批量取物品，返回 {id: row}。"""
        if not ids:
            return {}
        resp = self._client.get(
            "/items", params={"select": "*", "id": f"in.({','.join(ids)})"}
        )
        resp.raise_for_status()
        return {r["id"]: r for r in resp.json()}
