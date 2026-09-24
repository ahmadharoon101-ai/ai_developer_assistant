"""GitHub access happens only here. Tokens are stored encrypted and never sent to the app."""
import base64
import hashlib
import re

import httpx
from cryptography.fernet import Fernet, InvalidToken
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from .. import ai, db
from ..config import settings
from ..deps import current_user, limit_ai
from ..projects_service import MAX_ZIP_BYTES, create_project, ingest_zip, project_json, project_row
from ..security import create_token, decode_payload

router = APIRouter(prefix="/github", tags=["github"])
root_router = APIRouter(tags=["github"])

API = "https://api.github.com"
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$")
REF_RE = re.compile(r"^[A-Za-z0-9_./-]{1,120}$")


def _fernet() -> Fernet:
    key = base64.urlsafe_b64encode(hashlib.sha256(settings.jwt_secret.encode()).digest())
    return Fernet(key)


def _store_token(user_id: int, token: str, login: str) -> None:
    with db.conn() as c:
        c.execute(
            "INSERT INTO github_tokens (user_id, token_enc, login, created_at) VALUES (?,?,?,?) "
            "ON CONFLICT(user_id) DO UPDATE SET token_enc=excluded.token_enc, login=excluded.login, "
            "created_at=excluded.created_at",
            (user_id, _fernet().encrypt(token.encode()).decode(), login, db.now()),
        )


def _get_token(user_id: int) -> tuple[str, str] | None:
    with db.conn() as c:
        row = c.execute("SELECT token_enc, login FROM github_tokens WHERE user_id = ?", (user_id,)).fetchone()
    if not row:
        return None
    try:
        return _fernet().decrypt(row["token_enc"].encode()).decode(), row["login"]
    except InvalidToken:
        return None


def _headers(token: str, accept: str = "application/vnd.github+json") -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": accept,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ai-developer-assistant",
    }


def _require_token(user_id: int) -> str:
    t = _get_token(user_id)
    if not t:
        raise HTTPException(400, "Connect your GitHub account first.")
    return t[0]


def _gh_error(status: int) -> HTTPException:
    msg = {
        401: "GitHub rejected the saved token. Reconnect GitHub.",
        403: "GitHub denied access (permissions or rate limit).",
        404: "Repository or branch not found, or you do not have access.",
    }.get(status, f"GitHub returned an error ({status}).")
    return HTTPException(502 if status >= 500 else 400, msg)


async def _fetch_login(token: str) -> str:
    try:
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.get(f"{API}/user", headers=_headers(token))
    except httpx.HTTPError:
        raise HTTPException(502, "Could not reach GitHub from the server.")
    if r.status_code != 200:
        raise HTTPException(400, "GitHub did not accept that token.")
    return r.json()["login"]


class TokenIn(BaseModel):
    token: str = Field(min_length=10, max_length=300)


class ImportIn(BaseModel):
    repo: str
    ref: str = ""


class PrIn(BaseModel):
    repo: str
    base: str = Field(min_length=1, max_length=120)
    head: str = Field(min_length=1, max_length=120)


@router.get("/status")
def status(user=Depends(current_user)):
    t = _get_token(user["id"])
    return {
        "connected": bool(t),
        "login": t[1] if t else None,
        "oauth_available": bool(settings.github_client_id and settings.github_client_secret),
    }


@router.get("/oauth/start")
def oauth_start(user=Depends(current_user)):
    if not (settings.github_client_id and settings.github_client_secret):
        raise HTTPException(400, "GitHub OAuth is not configured on the server. Use a personal access token instead.")
    state = create_token(user["id"], user["token_version"], extra={"purpose": "gh_oauth"}, minutes=10)
    from urllib.parse import urlencode
    q = urlencode({"client_id": settings.github_client_id, "redirect_uri": settings.github_redirect_uri,
                   "scope": settings.github_scope, "state": state})
    return {"url": f"https://github.com/login/oauth/authorize?{q}"}


@router.get("/oauth/callback", response_class=HTMLResponse)
async def oauth_callback(code: str = Query(...), state: str = Query(...)):
    payload = decode_payload(state)
    if not payload or payload.get("purpose") != "gh_oauth":
        return HTMLResponse("<h3>Invalid or expired link. Close this tab and try again.</h3>", status_code=400)
    try:
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.post(
                "https://github.com/login/oauth/access_token",
                json={"client_id": settings.github_client_id, "client_secret": settings.github_client_secret,
                      "code": code, "redirect_uri": settings.github_redirect_uri},
                headers={"Accept": "application/json"},
            )
        token = r.json().get("access_token")
        if not token:
            raise ValueError
        login = await _fetch_login(token)
    except Exception:
        return HTMLResponse("<h3>GitHub sign-in failed. Close this tab and try again.</h3>", status_code=400)
    _store_token(int(payload["sub"]), token, login)
    return HTMLResponse(f"<h3>GitHub connected as {login}. You can close this tab and return to the app.</h3>")


@router.post("/token")
async def connect_with_token(body: TokenIn, user=Depends(current_user)):
    token = body.token.strip()
    login = await _fetch_login(token)
    _store_token(user["id"], token, login)
    return {"connected": True, "login": login}


@router.delete("/connection", status_code=204)
def disconnect(user=Depends(current_user)):
    with db.conn() as c:
        c.execute("DELETE FROM github_tokens WHERE user_id = ?", (user["id"],))


@router.get("/repositories")
async def repositories(user=Depends(current_user)):
    token = _require_token(user["id"])
    try:
        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.get(f"{API}/user/repos", headers=_headers(token),
                            params={"per_page": 100, "sort": "updated", "affiliation": "owner,collaborator,organization_member"})
    except httpx.HTTPError:
        raise HTTPException(502, "Could not reach GitHub from the server.")
    if r.status_code != 200:
        raise _gh_error(r.status_code)
    return [
        {"full_name": x["full_name"], "description": x.get("description") or "", "language": x.get("language") or "",
         "private": x["private"], "updated_at": x["updated_at"], "default_branch": x["default_branch"],
         "stars": x.get("stargazers_count", 0)}
        for x in r.json()
    ]


@root_router.post("/projects/import-github", status_code=201)
async def import_github(body: ImportIn, user=Depends(current_user)):
    if not REPO_RE.match(body.repo):
        raise HTTPException(400, "Repository must look like owner/name.")
    if body.ref and not REF_RE.match(body.ref):
        raise HTTPException(400, "Invalid branch or tag name.")
    token = _require_token(user["id"])
    url = f"{API}/repos/{body.repo}/zipball" + (f"/{body.ref}" if body.ref else "")
    buf = bytearray()
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(120, connect=15), follow_redirects=True) as c:
            async with c.stream("GET", url, headers=_headers(token)) as r:
                if r.status_code != 200:
                    raise _gh_error(r.status_code)
                async for chunk in r.aiter_bytes():
                    buf.extend(chunk)
                    if len(buf) > MAX_ZIP_BYTES:
                        raise HTTPException(413, "Repository is too large to import (max 30 MB).")
    except httpx.HTTPError:
        raise HTTPException(502, "Could not download the repository from GitHub.")
    files = ingest_zip(bytes(buf))
    pid = create_project(user["id"], body.repo.split("/")[1], "github", files, github_repo=body.repo)
    return project_json(project_row(pid, user["id"]), len(files))


@router.post("/pr-description")
async def pr_description(body: PrIn, user=Depends(limit_ai)):
    if not REPO_RE.match(body.repo) or not REF_RE.match(body.base) or not REF_RE.match(body.head):
        raise HTTPException(400, "Invalid repository or branch name.")
    token = _require_token(user["id"])
    try:
        async with httpx.AsyncClient(timeout=40) as c:
            r = await c.get(f"{API}/repos/{body.repo}/compare/{body.base}...{body.head}",
                            headers=_headers(token, "application/vnd.github.diff"))
    except httpx.HTTPError:
        raise HTTPException(502, "Could not reach GitHub from the server.")
    if r.status_code != 200:
        raise _gh_error(r.status_code)
    diff = r.text
    if not diff.strip():
        raise HTTPException(400, "There are no differences between those branches.")
    prompt = (f"Write a pull request description for merging `{body.head}` into `{body.base}` in {body.repo}.\n"
              "Sections: ### Summary, ### Changes (bullets), ### Testing, ### Risks. Base it only on the diff.\n\n"
              f"```diff\n{diff[:45_000]}\n```")
    try:
        text = await ai.complete("You write clear, honest pull request descriptions.", prompt, temperature=0.3)
    except ai.AIError as e:
        raise HTTPException(502, str(e))
    return {"content": text}
