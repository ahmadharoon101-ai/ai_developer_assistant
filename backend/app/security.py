import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import settings


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        return False


def create_token(user_id: int, token_version: int = 0, extra: dict | None = None,
                 minutes: int | None = None) -> str:
    exp = datetime.now(timezone.utc) + timedelta(minutes=minutes or settings.jwt_expire_minutes)
    payload = {"sub": str(user_id), "tv": token_version, "exp": exp, **(extra or {})}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_payload(token: str) -> dict | None:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None


def decode_token(token: str) -> tuple[int, int] | None:
    """Returns (user_id, token_version) for a valid login token."""
    payload = decode_payload(token)
    if not payload or payload.get("purpose"):
        return None
    try:
        return int(payload["sub"]), int(payload.get("tv", 0))
    except (KeyError, ValueError):
        return None


class RateLimiter:
    """Small in-memory sliding-window limiter (fine for one server process)."""

    def __init__(self, limit: int, window_seconds: int):
        self.limit = limit
        self.window = window_seconds
        self.hits: dict[str, deque] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        q = self.hits[key]
        while q and now - q[0] > self.window:
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        return True
