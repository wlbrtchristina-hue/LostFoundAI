"""认证层：校验 Supabase JWT。

Supabase 用户 token 由 GoTrue 签发，新版项目用 ES256（JWKS 中为 EC P-256
密钥，按 kid 匹配）。API key（RS256）也可用同一套逻辑兼容。
公钥缓存 1 小时。返回当前用户 uuid；无效凭证抛 401。
"""

import os
import time

import httpx
import jwt
from fastapi import Header, HTTPException

_CACHE: dict = {"fetched_at": 0.0, "keys": None}
_CACHE_TTL = 3600


def _jwks() -> dict[str, dict]:
    """按 kid 索引的 JWKS 密钥表（缓存 1 小时）。"""
    cached = _CACHE["keys"]
    if cached is not None and time.time() - _CACHE["fetched_at"] < _CACHE_TTL:
        return cached
    base = os.environ["SUPABASE_URL"].rstrip("/")
    resp = httpx.get(f"{base}/auth/v1/.well-known/jwks.json", timeout=10)
    resp.raise_for_status()
    keys = {k["kid"]: k for k in (resp.json().get("keys") or [])}
    if not keys:
        raise HTTPException(500, "无法获取 Supabase 签名公钥")
    _CACHE["fetched_at"] = time.time()
    _CACHE["keys"] = keys
    return keys


def get_current_user(authorization: str = Header(default="")) -> str:
    """FastAPI 依赖：从 Bearer token 解出用户 uuid。"""
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "未登录：缺少 Authorization 头")
    token = authorization[len("Bearer "):].strip()
    try:
        # 先读 token 头拿 kid/alg，再取对应公钥验签（ES256 / RS256 均可）
        header = jwt.get_unverified_header(token)
        jwk = _jwks().get(header.get("kid"))
        if jwk is None:
            raise jwt.InvalidTokenError("unknown kid")
        payload = jwt.decode(
            token,
            key=jwt.PyJWK(jwk, algorithm=header.get("alg")).key,
            algorithms=[header.get("alg")],
            audience="authenticated",
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(401, "登录凭证无效或已过期，请重新登录") from exc
    sub = payload.get("sub")
    if not sub:
        raise HTTPException(401, "登录凭证缺少用户信息")
    return sub
