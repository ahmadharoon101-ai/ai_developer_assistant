import json
import re
import secrets
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr, Field, field_validator

from .. import db, mail
from ..config import settings
from ..deps import current_user, limit_auth
from ..security import create_token, hash_password, verify_password

router = APIRouter(tags=["account"])


class ProfileIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)


class PasswordIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=64)
    new_password: str = Field(min_length=8, max_length=64)

    @field_validator("new_password")
    @classmethod
    def strong(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
            raise ValueError("Password must include at least one letter and one number.")
        return v


class SettingsIn(BaseModel):
    response_style: str = "balanced"
    temperature: float = Field(default=0.4, ge=0.0, le=1.0)
    model: str = ""
    history_messages: int = Field(default=30, ge=4, le=60)


class SavedIn(BaseModel):
    kind: str = Field(pattern="^(debug|generator|tests|docs)$")
    title: str = Field(min_length=1, max_length=120)
    payload: dict


class ForgotPasswordIn(BaseModel):
    email: EmailStr


class ResetPasswordIn(BaseModel):
    code: str = Field(min_length=6, max_length=12)
    new_password: str = Field(min_length=8, max_length=64)

    @field_validator("new_password")
    @classmethod
    def strong(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
            raise ValueError("Password must include at least one letter and one number.")
        return v


_RESET_TTL = 30 * 60  # seconds
_reset_codes: dict[str, dict] = {}  # code -> {"user_id": int, "created": ts}


def _new_reset_code(user_id: int) -> str:
    now = time.time()
    for k, v in list(_reset_codes.items()):  # opportunistic cleanup
        if now - v["created"] > _RESET_TTL:
            _reset_codes.pop(k, None)
    code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(8))
    _reset_codes[code] = {"user_id": user_id, "created": now}
    return code


@router.post("/auth/forgot-password")
async def forgot_password(body: ForgotPasswordIn, request: Request):
    limit_auth(request)
    # Always the same response whether or not the account exists, so this
    # endpoint can't be used to check which emails are registered.
    generic = {"sent": True, "message": "If that email has an account, a reset code was sent to it."}
    user = db.get_user_by_email(body.email.lower())
    if not user:
        return generic
    code = _new_reset_code(user["id"])
    emailed = await mail.send_reset_code(user["email"], code)
    if emailed:
        return generic
    # No SMTP configured on this server: hand the code back directly so the
    # feature is still usable in local/dev setups. Never silent about it.
    return {
        "sent": False,
        "message": "Email sending isn't configured on this server (no SMTP in backend/.env). "
                    "Use this code directly instead:",
        "dev_code": code,
    }


@router.post("/auth/reset-password")
def reset_password(body: ResetPasswordIn, request: Request):
    limit_auth(request)
    entry = _reset_codes.get(body.code.upper())
    if not entry or time.time() - entry["created"] > _RESET_TTL:
        _reset_codes.pop(body.code.upper(), None)
        raise HTTPException(400, "That reset code is invalid or has expired.")
    with db.conn() as c:
        c.execute(
            "UPDATE users SET password_hash = ?, token_version = token_version + 1 WHERE id = ?",
            (hash_password(body.new_password), entry["user_id"]),
        )
    _reset_codes.pop(body.code.upper(), None)
    return {"ok": True}


@router.put("/auth/profile")
def update_profile(body: ProfileIn, user=Depends(current_user)):
    with db.conn() as c:
        c.execute("UPDATE users SET name = ? WHERE id = ?", (body.name.strip(), user["id"]))
    return {"id": str(user["id"]), "name": body.name.strip(), "email": user["email"]}


@router.post("/auth/password")
def change_password(body: PasswordIn, user=Depends(current_user)):
    if not verify_password(body.current_password, user["password_hash"]):
        raise HTTPException(400, "Current password is incorrect.")
    with db.conn() as c:
        c.execute(
            "UPDATE users SET password_hash = ?, token_version = token_version + 1 WHERE id = ?",
            (hash_password(body.new_password), user["id"]),
        )
    fresh = db.get_user(user["id"])
    # Other sessions are signed out; return a fresh token so this device stays signed in.
    return {"access_token": create_token(fresh["id"], fresh["token_version"])}


@router.post("/auth/logout-all")
def logout_all(user=Depends(current_user)):
    db.bump_token_version(user["id"])
    return {"ok": True}


@router.get("/settings")
def get_settings(user=Depends(current_user)):
    s = db.get_settings(user["id"])
    return {
        **s,
        "provider": settings.ai_provider,
        "default_model": settings.active_model,
        "available_models": settings.available_models,
    }


@router.put("/settings")
def put_settings(body: SettingsIn, user=Depends(current_user)):
    if body.response_style not in ("concise", "balanced", "detailed"):
        raise HTTPException(400, "Unknown response style.")
    if body.model and body.model not in settings.available_models:
        raise HTTPException(400, "That model is not enabled on this server.")
    db.save_settings(user["id"], body.model_dump())
    return get_settings(user)


@router.get("/saved")
def list_saved(kind: str, user=Depends(current_user)):
    with db.conn() as c:
        rows = c.execute(
            "SELECT id, kind, title, payload, created_at FROM saved_items WHERE user_id = ? AND kind = ? "
            "ORDER BY id DESC LIMIT 50", (user["id"], kind)).fetchall()
    return [{"id": r["id"], "kind": r["kind"], "title": r["title"], "created_at": r["created_at"],
             "payload": json.loads(r["payload"])} for r in rows]


@router.post("/saved", status_code=201)
def save_item(body: SavedIn, user=Depends(current_user)):
    payload = json.dumps(body.payload)
    if len(payload) > 200_000:
        raise HTTPException(413, "That item is too large to save.")
    with db.conn() as c:
        cur = c.execute(
            "INSERT INTO saved_items (user_id, kind, title, payload, created_at) VALUES (?,?,?,?,?)",
            (user["id"], body.kind, body.title.strip(), payload, db.now()))
    return {"id": cur.lastrowid}


@router.delete("/saved/{item_id}", status_code=204)
def delete_saved(item_id: int, user=Depends(current_user)):
    with db.conn() as c:
        c.execute("DELETE FROM saved_items WHERE id = ? AND user_id = ?", (item_id, user["id"]))
