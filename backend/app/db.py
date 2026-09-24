import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone

from .config import settings


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


@contextmanager
def conn():
    c = sqlite3.connect(settings.database_path)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys = ON")
    try:
        yield c
        c.commit()
    finally:
        c.close()


def init_db() -> None:
    with conn() as c:
        c.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                token_version INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL CHECK (role IN ('user','assistant')),
                content TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                language TEXT NOT NULL DEFAULT '',
                framework TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL DEFAULT 'empty',
                github_repo TEXT,
                created_at TEXT NOT NULL,
                last_analyzed TEXT,
                last_issue_count INTEGER
            );
            CREATE TABLE IF NOT EXISTS project_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                path TEXT NOT NULL,
                size INTEGER NOT NULL,
                language TEXT NOT NULL DEFAULT '',
                content TEXT NOT NULL,
                UNIQUE(project_id, path)
            );
            CREATE TABLE IF NOT EXISTS analysis_runs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                project_id TEXT,
                files INTEGER NOT NULL,
                issues INTEGER NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS saved_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS user_settings (
                user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                response_style TEXT NOT NULL DEFAULT 'balanced',
                temperature REAL NOT NULL DEFAULT 0.4,
                model TEXT NOT NULL DEFAULT '',
                history_messages INTEGER NOT NULL DEFAULT 30
            );
            CREATE TABLE IF NOT EXISTS github_tokens (
                user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                token_enc TEXT NOT NULL,
                login TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_proj_user ON projects(user_id, created_at);
            CREATE INDEX IF NOT EXISTS idx_conv_user ON conversations(user_id, updated_at);
            CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id, id);
            """
        )


# ---- users -----------------------------------------------------------------
def create_user(name: str, email: str, password_hash: str) -> int:
    with conn() as c:
        cur = c.execute(
            "INSERT INTO users (name, email, password_hash, created_at) VALUES (?,?,?,?)",
            (name, email, password_hash, now()),
        )
        return cur.lastrowid


def get_user_by_email(email: str):
    with conn() as c:
        return c.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()


def get_user(user_id: int):
    with conn() as c:
        return c.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


# ---- conversations ---------------------------------------------------------
def create_conversation(user_id: int, title: str) -> str:
    cid = uuid.uuid4().hex
    t = now()
    with conn() as c:
        c.execute(
            "INSERT INTO conversations (id, user_id, title, created_at, updated_at) VALUES (?,?,?,?,?)",
            (cid, user_id, title, t, t),
        )
    return cid


def get_conversation(conv_id: str, user_id: int):
    with conn() as c:
        return c.execute(
            "SELECT * FROM conversations WHERE id = ? AND user_id = ?", (conv_id, user_id)
        ).fetchone()


def list_conversations(user_id: int, limit: int = 100):
    with conn() as c:
        return c.execute(
            "SELECT id, title, updated_at FROM conversations WHERE user_id = ? "
            "ORDER BY updated_at DESC LIMIT ?",
            (user_id, limit),
        ).fetchall()


def delete_conversation(conv_id: str, user_id: int) -> bool:
    with conn() as c:
        cur = c.execute("DELETE FROM conversations WHERE id = ? AND user_id = ?", (conv_id, user_id))
        return cur.rowcount > 0


def touch_conversation(conv_id: str) -> None:
    with conn() as c:
        c.execute("UPDATE conversations SET updated_at = ? WHERE id = ?", (now(), conv_id))


# ---- messages --------------------------------------------------------------
def add_message(conv_id: str, role: str, content: str) -> int:
    with conn() as c:
        cur = c.execute(
            "INSERT INTO messages (conversation_id, role, content, created_at) VALUES (?,?,?,?)",
            (conv_id, role, content, now()),
        )
        return cur.lastrowid


def get_messages(conv_id: str, limit: int | None = None):
    with conn() as c:
        if limit:
            return c.execute(
                "SELECT * FROM (SELECT id, role, content FROM messages WHERE conversation_id = ? "
                "ORDER BY id DESC LIMIT ?) ORDER BY id",
                (conv_id, limit),
            ).fetchall()
        return c.execute(
            "SELECT id, role, content FROM messages WHERE conversation_id = ? ORDER BY id",
            (conv_id,),
        ).fetchall()


def delete_trailing_assistant(conv_id: str) -> None:
    """Remove assistant messages after the last user message (used by regenerate)."""
    with conn() as c:
        row = c.execute(
            "SELECT MAX(id) AS m FROM messages WHERE conversation_id = ? AND role = 'user'",
            (conv_id,),
        ).fetchone()
        last_user = row["m"] if row and row["m"] else 0
        c.execute(
            "DELETE FROM messages WHERE conversation_id = ? AND role = 'assistant' AND id > ?",
            (conv_id, last_user),
        )


def conversation_count(user_id: int) -> int:
    with conn() as c:
        return c.execute(
            "SELECT COUNT(*) AS n FROM conversations WHERE user_id = ?", (user_id,)
        ).fetchone()["n"]


# ---- extras ----------------------------------------------------------------
def bump_token_version(user_id: int) -> None:
    with conn() as c:
        c.execute("UPDATE users SET token_version = token_version + 1 WHERE id = ?", (user_id,))


def get_settings(user_id: int) -> dict:
    with conn() as c:
        row = c.execute("SELECT * FROM user_settings WHERE user_id = ?", (user_id,)).fetchone()
    if row:
        return {k: row[k] for k in ("response_style", "temperature", "model", "history_messages")}
    return {"response_style": "balanced", "temperature": 0.4, "model": "", "history_messages": 30}


def save_settings(user_id: int, s: dict) -> None:
    with conn() as c:
        c.execute(
            "INSERT INTO user_settings (user_id, response_style, temperature, model, history_messages) "
            "VALUES (?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET response_style=excluded.response_style, "
            "temperature=excluded.temperature, model=excluded.model, history_messages=excluded.history_messages",
            (user_id, s["response_style"], s["temperature"], s["model"], s["history_messages"]),
        )
