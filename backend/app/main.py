import asyncio
import re
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field, field_validator

from . import ai, db
from .config import settings
from .deps import chat_limiter, current_user, limit_auth, user_from_token
from .projects_service import all_files, build_context, project_row
from .routers import account, ai_tools, github, projects
from .security import create_token, hash_password, verify_password

MAX_MESSAGE_CHARS = 20_000


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_db()
    yield


app = FastAPI(title="AI Developer Assistant API", lifespan=lifespan)
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins or ["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(account.router)
app.include_router(projects.router)
app.include_router(ai_tools.router)
app.include_router(github.router)
app.include_router(github.root_router)


# ---- schemas ---------------------------------------------------------------
class RegisterIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=80)
    email: EmailStr
    password: str = Field(min_length=8, max_length=64)

    @field_validator("password")
    @classmethod
    def strong_enough(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
            raise ValueError("Password must include at least one letter and one number.")
        return v


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=64)


def _user_json(u) -> dict:
    return {"id": str(u["id"]), "name": u["name"], "email": u["email"]}


def _session(u) -> dict:
    return {"access_token": create_token(u["id"], u["token_version"]), "user": _user_json(u)}


# ---- auth ------------------------------------------------------------------
@app.post("/auth/register", status_code=201)
def register(body: RegisterIn, request: Request):
    limit_auth(request)
    email = body.email.lower()
    if db.get_user_by_email(email):
        raise HTTPException(409, "An account with this email already exists.")
    uid = db.create_user(body.full_name.strip(), email, hash_password(body.password))
    return _session(db.get_user(uid))


@app.post("/auth/login")
def login(body: LoginIn, request: Request):
    limit_auth(request)
    user = db.get_user_by_email(body.email.lower())
    if not user or not verify_password(body.password, user["password_hash"]):
        raise HTTPException(401, "Incorrect email or password.")
    return _session(user)


@app.get("/auth/me")
def me(user=Depends(current_user)):
    return _user_json(user)


# ---- conversations ---------------------------------------------------------
@app.get("/conversations")
def conversations(user=Depends(current_user)):
    return [dict(r) for r in db.list_conversations(user["id"])]


@app.get("/conversations/{conv_id}/messages")
def conversation_messages(conv_id: str, user=Depends(current_user)):
    if not db.get_conversation(conv_id, user["id"]):
        raise HTTPException(404, "Conversation not found.")
    return [dict(r) for r in db.get_messages(conv_id)]


@app.delete("/conversations/{conv_id}", status_code=204)
def delete_conversation(conv_id: str, user=Depends(current_user)):
    if not db.delete_conversation(conv_id, user["id"]):
        raise HTTPException(404, "Conversation not found.")


@app.get("/dashboard/stats")
def dashboard_stats(user=Depends(current_user)):
    with db.conn() as c:
        n_projects = c.execute("SELECT COUNT(*) AS n FROM projects WHERE user_id = ?", (user["id"],)).fetchone()["n"]
        runs = c.execute(
            "SELECT COALESCE(SUM(files),0) AS f, COALESCE(SUM(issues),0) AS i FROM analysis_runs WHERE user_id = ?",
            (user["id"],)).fetchone()
        recent_projects = c.execute(
            "SELECT p.*, (SELECT COUNT(*) FROM project_files f WHERE f.project_id = p.id) AS fc "
            "FROM projects p WHERE p.user_id = ? ORDER BY p.created_at DESC LIMIT 3", (user["id"],)).fetchall()
    from .projects_service import project_json
    return {
        "projects": n_projects,
        "conversations": db.conversation_count(user["id"]),
        "files_analyzed": runs["f"],
        "bugs_detected": runs["i"],
        "recent_conversations": [dict(r) for r in db.list_conversations(user["id"], limit=5)],
        "recent_projects": [project_json(r, r["fc"]) for r in recent_projects],
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "provider": settings.ai_provider,
        "model": settings.active_model,
        "api_key_configured": bool(settings.active_key),
        "github_oauth_configured": bool(settings.github_client_id and settings.github_client_secret),
    }


# ---- streaming chat --------------------------------------------------------
def _title(text: str) -> str:
    line = text.strip().splitlines()[0] if text.strip() else "New chat"
    return line[:40] + ("…" if len(line) > 40 else "")


async def _safe_send(ws: WebSocket, payload: dict) -> None:
    try:
        await ws.send_json(payload)
    except Exception:
        pass


async def _handle_message(ws: WebSocket, user, msg: dict) -> None:
    content = (msg.get("content") or "").strip()
    regenerate = bool(msg.get("regenerate"))
    conv_id = msg.get("conversation_id")
    project_id = msg.get("project_id")
    images = msg.get("images") or []

    if not regenerate and not content and not images:
        return await _safe_send(ws, {"type": "error", "content": "Message is empty."})
    try:
        images = ai.validate_images(images)
    except ai.AIError as e:
        return await _safe_send(ws, {"type": "error", "content": str(e)})
    if len(content) > MAX_MESSAGE_CHARS:
        return await _safe_send(
            ws, {"type": "error", "content": f"Message is too long (max {MAX_MESSAGE_CHARS} characters)."})
    if not chat_limiter.allow(str(user["id"])):
        return await _safe_send(ws, {"type": "error", "content": "You are sending messages too fast. Wait a moment."})

    if conv_id:
        if not db.get_conversation(conv_id, user["id"]):
            return await _safe_send(ws, {"type": "error", "content": "Conversation not found."})
    else:
        if regenerate:
            return await _safe_send(ws, {"type": "error", "content": "Nothing to regenerate."})
        title = _title(content or ("Image" if images else "New chat"))
        conv_id = db.create_conversation(user["id"], title)
        await ws.send_json({"type": "conversation", "id": conv_id, "title": title})

    if regenerate:
        db.delete_trailing_assistant(conv_id)
    else:
        # Images are sent to the model for this turn only; they are not stored, so a
        # reloaded conversation shows the note below instead of the picture itself.
        stored = content or ""
        if images:
            stored = (stored + "\n\n" if stored else "") + f"_[{len(images)} image(s) attached]_"
        db.add_message(conv_id, "user", stored)

    prefs = db.get_settings(user["id"])
    history = [dict(r) for r in db.get_messages(conv_id, prefs["history_messages"])]

    project_context = ""
    if project_id:
        if not project_row(project_id, user["id"]):
            return await _safe_send(ws, {"type": "error", "content": "The selected project no longer exists."})
        files = all_files(project_id)
        if files:
            project_context, _ = build_context(files, budget=30_000, per_file=5_000)

    model = prefs["model"] if prefs["model"] in settings.available_models else None
    await ws.send_json({"type": "status", "content": f"Asking {ai.provider_label(model)}"})
    if project_context:
        await ws.send_json({"type": "status", "content": "Using your project as context"})

    parts: list[str] = []
    completed = False
    text = ""
    try:
        async for chunk in ai.stream_reply(
            history, system=ai.chat_system(prefs["response_style"], project_context), model=model,
            temperature=prefs["temperature"], images=images if not regenerate else None,
        ):
            parts.append(chunk)
            await ws.send_json({"type": "token", "content": chunk})
        completed = True
    except ai.AIError as e:
        await _safe_send(ws, {"type": "error", "content": str(e)})
    finally:
        text = "".join(parts).strip()
        if text:  # also keeps partial answers when the user presses Stop
            db.add_message(conv_id, "assistant", text)
        db.touch_conversation(conv_id)

    if completed:
        if text:
            await ws.send_json({"type": "done"})
        else:
            await _safe_send(ws, {"type": "error", "content": "The model returned an empty response."})


@app.websocket("/ws/chat")
async def ws_chat(ws: WebSocket):
    await ws.accept()
    try:
        first = await asyncio.wait_for(ws.receive_json(), timeout=10)
        user = user_from_token(first.get("token", "")) if first.get("type") == "auth" else None
        if not user:
            await ws.close(code=4401)
            return
        while True:
            msg = await ws.receive_json()
            if msg.get("type") == "message":
                await _handle_message(ws, user, msg)
    except (WebSocketDisconnect, asyncio.TimeoutError, ValueError, RuntimeError):
        return
