"""Safe, in-memory project ingestion. Uploaded code is only ever stored as text; it is never executed."""
import io
import json
import posixpath
import uuid
import zipfile
from collections import Counter

from fastapi import HTTPException

from . import db

MAX_ZIP_BYTES = 30 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 150 * 1024 * 1024
MAX_FILES = 3000
MAX_FILE_BYTES = 400_000

SKIP_DIRS = {
    ".git", "node_modules", "build", "dist", "__pycache__", ".dart_tool", "venv", ".venv", "env",
    ".idea", ".vscode", "target", ".gradle", "Pods", ".next", ".pytest_cache", "coverage", ".mypy_cache",
}
SKIP_FILES = {"package-lock.json", "yarn.lock", "pnpm-lock.yaml", "pubspec.lock", "poetry.lock", ".DS_Store"}

EXT_LANG = {
    ".py": "Python", ".dart": "Dart", ".js": "JavaScript", ".jsx": "JavaScript", ".mjs": "JavaScript",
    ".ts": "TypeScript", ".tsx": "TypeScript", ".java": "Java", ".cs": "C#", ".cpp": "C++", ".cc": "C++",
    ".c": "C", ".h": "C", ".hpp": "C++", ".go": "Go", ".rs": "Rust", ".kt": "Kotlin", ".swift": "Swift",
    ".php": "PHP", ".rb": "Ruby", ".html": "HTML", ".css": "CSS", ".scss": "CSS", ".json": "JSON",
    ".yaml": "YAML", ".yml": "YAML", ".md": "Markdown", ".sql": "SQL", ".sh": "Shell", ".toml": "TOML",
    ".xml": "XML", ".gradle": "Gradle", ".txt": "Text",
}
NON_PROGRAMMING = {"JSON", "YAML", "Markdown", "HTML", "CSS", "TOML", "XML", "Text", "Gradle", "Shell"}


def language_of(path: str) -> str:
    return EXT_LANG.get(posixpath.splitext(path.lower())[1], "")


def clean_path(raw: str) -> str | None:
    p = raw.replace("\\", "/").strip("/")
    if not p or p.startswith("/") or ":" in p.split("/")[0]:
        return None
    parts = p.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    if any(part in SKIP_DIRS for part in parts[:-1]) or parts[-1] in SKIP_FILES:
        return None
    return "/".join(parts)


def ingest_zip(data: bytes) -> list[dict]:
    if len(data) > MAX_ZIP_BYTES:
        raise HTTPException(413, f"ZIP is too large (max {MAX_ZIP_BYTES // (1024 * 1024)} MB).")
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise HTTPException(400, "That file is not a valid ZIP archive.")
    infos = [i for i in zf.infolist() if not i.is_dir()]
    if sum(i.file_size for i in infos) > MAX_UNCOMPRESSED_BYTES:
        raise HTTPException(413, "The archive expands to too much data.")
    if len(infos) > 20000:
        raise HTTPException(413, "The archive contains too many files.")

    names = [i.filename.replace("\\", "/") for i in infos]
    # Strip a single shared top-level folder (GitHub zipballs, "project.zip" -> project/...).
    prefix = ""
    tops = {n.split("/")[0] for n in names if "/" in n}
    if len(tops) == 1 and all("/" in n for n in names):
        prefix = tops.pop() + "/"

    files: list[dict] = []
    for info in infos:
        name = info.filename.replace("\\", "/")
        if prefix and name.startswith(prefix):
            name = name[len(prefix):]
        path = clean_path(name)
        if not path or info.file_size > MAX_FILE_BYTES:
            continue
        raw = zf.open(info).read(MAX_FILE_BYTES + 1)
        if len(raw) > MAX_FILE_BYTES or b"\x00" in raw[:4096]:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        files.append({"path": path, "size": len(raw), "language": language_of(path), "content": text})
        if len(files) >= MAX_FILES:
            break
    if not files:
        raise HTTPException(400, "No readable source files were found in the archive.")
    return files


def detect_language(files: list[dict]) -> str:
    counts = Counter(f["language"] for f in files if f["language"] and f["language"] not in NON_PROGRAMMING)
    if not counts:
        counts = Counter(f["language"] for f in files if f["language"])
    return counts.most_common(1)[0][0] if counts else ""


def detect_framework(files: list[dict]) -> str:
    by_name = {f["path"].split("/")[-1]: f["content"] for f in files if f["path"].count("/") <= 1}
    if "pubspec.yaml" in by_name and "flutter" in by_name["pubspec.yaml"].lower():
        return "Flutter"
    if "package.json" in by_name:
        try:
            pkg = json.loads(by_name["package.json"])
            deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
            for key, name in (("next", "Next.js"), ("react", "React"), ("vue", "Vue"), ("express", "Express"),
                              ("@angular/core", "Angular"), ("svelte", "Svelte")):
                if key in deps:
                    return name
        except ValueError:
            pass
        return "Node.js"
    text = (by_name.get("requirements.txt", "") + by_name.get("pyproject.toml", "")).lower()
    for key, name in (("fastapi", "FastAPI"), ("django", "Django"), ("flask", "Flask")):
        if key in text:
            return name
    if "go.mod" in by_name:
        return "Go modules"
    if "Cargo.toml" in by_name:
        return "Cargo"
    if "pom.xml" in by_name or "build.gradle" in by_name:
        return "Spring" if "spring" in (by_name.get("pom.xml", "") + by_name.get("build.gradle", "")).lower() else "JVM"
    return ""


def create_project(user_id: int, name: str, source: str, files: list[dict], github_repo: str | None = None,
                   language: str = "", framework: str = "") -> str:
    pid = uuid.uuid4().hex
    with db.conn() as c:
        c.execute(
            "INSERT INTO projects (id, user_id, name, language, framework, source, github_repo, created_at) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (pid, user_id, name, language or detect_language(files), framework or detect_framework(files),
             source, github_repo, db.now()),
        )
        c.executemany(
            "INSERT OR REPLACE INTO project_files (project_id, path, size, language, content) VALUES (?,?,?,?,?)",
            [(pid, f["path"], f["size"], f["language"], f["content"]) for f in files],
        )
    return pid


def project_row(project_id: str, user_id: int):
    with db.conn() as c:
        return c.execute("SELECT * FROM projects WHERE id = ? AND user_id = ?", (project_id, user_id)).fetchone()


def require_project(project_id: str, user_id: int):
    row = project_row(project_id, user_id)
    if not row:
        raise HTTPException(404, "Project not found.")
    return row


def project_json(row, file_count: int) -> dict:
    if row["last_analyzed"] is None:
        status = "Not analyzed"
    else:
        status = "Healthy" if (row["last_issue_count"] or 0) == 0 else "Needs review"
    return {
        "id": row["id"], "name": row["name"], "language": row["language"], "framework": row["framework"],
        "source": row["source"], "github_repo": row["github_repo"], "file_count": file_count,
        "last_analyzed": row["last_analyzed"], "created_at": row["created_at"], "status": status,
    }


def list_files(project_id: str) -> list[dict]:
    with db.conn() as c:
        rows = c.execute(
            "SELECT path, size, language FROM project_files WHERE project_id = ? ORDER BY path", (project_id,)
        ).fetchall()
    return [dict(r) for r in rows]


def get_file(project_id: str, path: str):
    with db.conn() as c:
        return c.execute(
            "SELECT path, size, language, content FROM project_files WHERE project_id = ? AND path = ?",
            (project_id, path),
        ).fetchone()


def all_files(project_id: str) -> list[dict]:
    with db.conn() as c:
        rows = c.execute(
            "SELECT path, size, language, content FROM project_files WHERE project_id = ? ORDER BY path",
            (project_id,),
        ).fetchall()
    return [dict(r) for r in rows]


def build_context(files: list[dict], budget: int = 60_000, per_file: int = 8_000) -> tuple[str, int]:
    """Concatenate the most useful source files into a prompt-sized block."""
    def priority(f: dict):
        lang = f["language"]
        is_code = bool(lang) and lang not in NON_PROGRAMMING
        is_test = "test" in f["path"].lower()
        return (0 if is_code else 1, 1 if is_test else 0, f["size"])

    out, used, count = [], 0, 0
    tree = "\n".join(f["path"] for f in files[:300])
    header = f"Project file list:\n{tree}\n\n"
    used += len(header)
    for f in sorted(files, key=priority):
        chunk = f["content"][:per_file]
        block = f"=== {f['path']} ===\n{chunk}\n"
        if used + len(block) > budget:
            continue
        out.append(block)
        used += len(block)
        count += 1
    return header + "\n".join(out), count
