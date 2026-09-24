from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import db
from .security import RateLimiter, decode_token

bearer = HTTPBearer(auto_error=False)
auth_limiter = RateLimiter(limit=10, window_seconds=60)
chat_limiter = RateLimiter(limit=20, window_seconds=60)
ai_limiter = RateLimiter(limit=15, window_seconds=60)


def user_from_token(token: str):
    decoded = decode_token(token)
    if not decoded:
        return None
    uid, tv = decoded
    user = db.get_user(uid)
    if not user or user["token_version"] != tv:
        return None
    return user


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if not creds:
        raise HTTPException(401, "Not signed in.")
    user = user_from_token(creds.credentials)
    if not user:
        raise HTTPException(401, "Your session expired. Sign in again.")
    return user


def limit_auth(request: Request) -> None:
    ip = request.client.host if request.client else "unknown"
    if not auth_limiter.allow(ip):
        raise HTTPException(429, "Too many attempts. Wait a minute and try again.")


def limit_ai(user=Depends(current_user)):
    if not ai_limiter.allow(str(user["id"])):
        raise HTTPException(429, "Too many AI requests. Wait a moment and try again.")
    return user
