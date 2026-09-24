"""Smoke tests. The AI provider is stubbed so no key or network is needed.
Run:  python -m tests.test_api
"""
import io
import os
import tempfile
import zipfile

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_PATH"] = os.path.join(_tmp, "test.db")
os.environ["JWT_SECRET"] = "test-secret"
os.environ["GEMINI_API_KEY"] = "test-key"

from fastapi.testclient import TestClient  # noqa: E402

from app import ai  # noqa: E402
from app.deps import auth_limiter  # noqa: E402
from app.main import app  # noqa: E402

# The test suite fires many auth requests back-to-back; raise the cap here only
# so the real, unmodified per-IP limit still protects the running server.
auth_limiter.limit = 1000


async def fake_stream(history, **kw):
    for part in ["Hello ", "from ", f"reply {len(history)}"]:
        yield part


async def fake_complete_json(system, prompt, **kw):
    if "Diagnose" in prompt:
        return {"problem": "p", "cause": "c", "solution": "```bash\npip install fastapi\n```",
                "explanation": "e", "fix_code": "pip install fastapi", "fix_language": "bash"}
    if "execution plan" in prompt:
        return {"summary": "s", "steps": [{"stage": "analysis", "title": "Look", "detail": "d", "files": ["a.py"]}],
                "risks": ["r"]}
    return {"summary": "ok", "complexity": "low", "issues": [
        {"title": "Bare except", "severity": "HIGH", "category": "bug", "location": "a.py:3",
         "explanation": "x", "suggested_fix": "y"}, "junk"]}


async def fake_complete(system, prompt, **kw):
    return "```python\nprint('hi')\n```\n### Notes\n- ok"


ai.stream_reply = fake_stream
ai.complete_json = fake_complete_json
ai.complete = fake_complete


def make_zip() -> bytes:
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("proj/requirements.txt", "fastapi\n")
        z.writestr("proj/app/main.py", "def f():\n    try:\n        pass\n    except:\n        pass\n")
        z.writestr("proj/node_modules/x.js", "skip me")
        z.writestr("proj/logo.png", b"\x89PNG\x00\x00binary")
        z.writestr("proj/../evil.py", "x=1")
    return b.getvalue()


def main():
    with TestClient(app) as c:
        assert c.get("/health").json()["api_key_configured"] is True
        r = c.post("/auth/register", json={"full_name": "Test User", "email": "t@example.com", "password": "password1"})
        assert r.status_code == 201, r.text
        H = {"Authorization": "Bearer " + r.json()["access_token"]}
        assert c.post("/auth/register", json={"full_name": "Test User", "email": "t@example.com", "password": "password1"}).status_code == 409
        assert c.post("/auth/login", json={"email": "t@example.com", "password": "nope1234"}).status_code == 401
        assert c.get("/auth/me", headers=H).json()["email"] == "t@example.com"
        assert c.get("/projects").status_code == 401

        # projects
        up = c.post("/projects/upload", headers=H, files={"file": ("proj.zip", make_zip(), "application/zip")})
        assert up.status_code == 201, up.text
        p = up.json()
        assert p["language"] == "Python" and p["framework"] == "FastAPI", p
        files = c.get(f"/projects/{p['id']}/files", headers=H).json()
        paths = [f["path"] for f in files]
        assert paths == ["app/main.py", "requirements.txt"], paths
        got = c.get(f"/projects/{p['id']}/files/content", params={"path": "app/main.py"}, headers=H).json()
        assert "except" in got["content"]
        assert c.put(f"/projects/{p['id']}/files/content", headers=H, json={"path": "../x.py", "content": "1"}).status_code == 400
        assert c.put(f"/projects/{p['id']}/files/content", headers=H, json={"path": "tests/test_a.py", "content": "x"}).status_code == 200
        assert c.post("/projects/upload", headers=H, files={"file": ("a.txt", b"x")}).status_code == 400

        # ai tools
        an = c.post("/ai/analyze", headers=H, json={"project_id": p["id"], "path": "app/main.py"}).json()
        assert an["issues"][0]["severity"] == "high" and len(an["issues"]) == 1, an
        assert c.get(f"/projects/{p['id']}", headers=H).json()["status"] == "Needs review"
        assert c.post("/ai/analyze", headers=H, json={}).status_code == 400
        dbg = c.post("/ai/debug", headers=H, json={"error": "ModuleNotFoundError"}).json()
        assert dbg["problem"] == "p" and dbg["fix_language"] == "bash"
        gen = c.post("/ai/generate", headers=H, json={"language": "Python", "prompt": "hello"}).json()
        assert "print" in gen["content"]
        assert c.post("/ai/tests", headers=H, json={"project_id": p["id"], "path": "app/main.py"}).status_code == 200
        assert c.post("/ai/documentation", headers=H, json={"project_id": p["id"], "doc_type": "readme"}).status_code == 200
        plan = c.post("/ai/agent/plan", headers=H, json={"project_id": p["id"], "request": "add logging"}).json()
        assert plan["steps"][0]["files"] == ["a.py"]

        # saved + settings
        assert c.post("/saved", headers=H, json={"kind": "debug", "title": "t", "payload": {"a": 1}}).status_code == 201
        assert c.get("/saved", params={"kind": "debug"}, headers=H).json()[0]["payload"] == {"a": 1}
        st = c.put("/settings", headers=H, json={"response_style": "detailed", "temperature": 0.2, "model": "", "history_messages": 20})
        assert st.status_code == 200 and st.json()["response_style"] == "detailed"
        assert c.put("/settings", headers=H, json={"response_style": "x", "temperature": 0.2, "model": "", "history_messages": 20}).status_code == 400

        # websocket chat (with project context) + history
        with c.websocket_connect("/ws/chat") as ws:
            ws.send_json({"type": "auth", "token": H["Authorization"][7:]})
            ws.send_json({"type": "message", "conversation_id": None, "content": "hello", "project_id": p["id"]})
            events = []
            while True:
                ev = ws.receive_json()
                events.append(ev)
                if ev["type"] in ("done", "error"):
                    break
        types = [e["type"] for e in events]
        assert types[0] == "conversation" and types[-1] == "done" and "token" in types, events
        conv_id = events[0]["id"]
        msgs = c.get(f"/conversations/{conv_id}/messages", headers=H).json()
        assert [m["role"] for m in msgs] == ["user", "assistant"]
        with c.websocket_connect("/ws/chat") as ws:
            ws.send_json({"type": "auth", "token": H["Authorization"][7:]})
            ws.send_json({"type": "message", "conversation_id": conv_id, "regenerate": True})
            while ws.receive_json()["type"] not in ("done", "error"):
                pass
        assert len(c.get(f"/conversations/{conv_id}/messages", headers=H).json()) == 2
        with c.websocket_connect("/ws/chat") as ws:
            ws.send_json({"type": "auth", "token": "bad"})
            try:
                ws.receive_json()
                raise AssertionError("bad token should close the socket")
            except Exception as e:
                assert "AssertionError" not in type(e).__name__

        stats = c.get("/dashboard/stats", headers=H).json()
        assert stats["projects"] == 1 and stats["conversations"] == 1 and stats["files_analyzed"] >= 1, stats

        # isolation between users
        r2 = c.post("/auth/register", json={"full_name": "Other", "email": "o@example.com", "password": "password2"})
        H2 = {"Authorization": "Bearer " + r2.json()["access_token"]}
        assert c.get(f"/projects/{p['id']}", headers=H2).status_code == 404
        assert c.get(f"/conversations/{conv_id}/messages", headers=H2).status_code == 404

        # logout-all invalidates tokens; password change keeps this device signed in
        assert c.post("/auth/logout-all", headers=H2).status_code == 200
        assert c.get("/auth/me", headers=H2).status_code == 401
        assert c.get("/github/status", headers=H).json()["connected"] is False

        assert c.delete(f"/projects/{p['id']}", headers=H).status_code == 204

        # image validation
        from app import ai as ai_mod
        assert ai_mod.validate_images(None) == []
        try:
            ai_mod.validate_images([{"mime": "image/tiff", "data": "x"}])
            raise AssertionError("bad mime should be rejected")
        except ai_mod.AIError:
            pass
        ok_img = [{"mime": "image/png", "data": "aGVsbG8="}]
        assert ai_mod.validate_images(ok_img) == ok_img
        with c.websocket_connect("/ws/chat") as ws:
            ws.send_json({"type": "auth", "token": H["Authorization"][7:]})
            ws.send_json({"type": "message", "conversation_id": None, "content": "look at this",
                          "images": [{"mime": "image/tiff", "data": "x"}]})
            ev = ws.receive_json()
            assert ev["type"] == "error" and "Unsupported image" in ev["content"], ev

        # forgot / reset password (no SMTP configured in tests -> dev_code returned)
        fp = c.post("/auth/forgot-password", json={"email": "t@example.com"}).json()
        assert fp["sent"] is False and "dev_code" in fp, fp
        code = fp["dev_code"]
        # unknown email gives the same generic shape, no dev_code, no account leak
        fp2 = c.post("/auth/forgot-password", json={"email": "nobody@example.com"}).json()
        assert fp2["sent"] is True and "dev_code" not in fp2
        assert c.post("/auth/reset-password", json={"code": "WRONGCODE", "new_password": "whatever1"}).status_code == 400
        assert c.post("/auth/reset-password", json={"code": code.lower(), "new_password": "newpass1"}).status_code == 200
        assert c.post("/auth/login", json={"email": "t@example.com", "password": "password1"}).status_code == 401
        r3 = c.post("/auth/login", json={"email": "t@example.com", "password": "newpass1"})
        assert r3.status_code == 200
        # code is one-time use
        assert c.post("/auth/reset-password", json={"code": code, "new_password": "another1"}).status_code == 400
    print("ALL BACKEND TESTS PASSED")


if __name__ == "__main__":
    main()
