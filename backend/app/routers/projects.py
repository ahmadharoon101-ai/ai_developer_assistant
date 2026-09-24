import posixpath

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from .. import db
from ..deps import current_user
from ..projects_service import (
    MAX_FILE_BYTES, all_files, clean_path, create_project, get_file, ingest_zip, language_of, list_files,
    project_json, project_row, require_project,
)

router = APIRouter(prefix="/projects", tags=["projects"])


def _count(project_id: str) -> int:
    with db.conn() as c:
        return c.execute("SELECT COUNT(*) AS n FROM project_files WHERE project_id = ?", (project_id,)).fetchone()["n"]


class ProjectIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    language: str = Field(default="", max_length=30)
    framework: str = Field(default="", max_length=30)


class FileWrite(BaseModel):
    path: str = Field(min_length=1, max_length=300)
    content: str = Field(max_length=MAX_FILE_BYTES)


@router.get("")
def list_projects(user=Depends(current_user)):
    with db.conn() as c:
        rows = c.execute("SELECT * FROM projects WHERE user_id = ? ORDER BY created_at DESC", (user["id"],)).fetchall()
        counts = {r["project_id"]: r["n"] for r in c.execute(
            "SELECT project_id, COUNT(*) AS n FROM project_files WHERE project_id IN "
            "(SELECT id FROM projects WHERE user_id = ?) GROUP BY project_id", (user["id"],))}
    return [project_json(r, counts.get(r["id"], 0)) for r in rows]


@router.post("", status_code=201)
def create_empty(body: ProjectIn, user=Depends(current_user)):
    pid = create_project(user["id"], body.name.strip(), "empty", [], language=body.language, framework=body.framework)
    return project_json(project_row(pid, user["id"]), 0)


@router.post("/upload", status_code=201)
async def upload_zip(file: UploadFile = File(...), name: str = Form(default=""), user=Depends(current_user)):
    if not (file.filename or "").lower().endswith(".zip"):
        raise HTTPException(400, "Only .zip files are accepted.")
    data = await file.read()
    files = ingest_zip(data)
    project_name = (name.strip() or (file.filename or "project")[:-4])[:80]
    pid = create_project(user["id"], project_name, "zip", files)
    return project_json(project_row(pid, user["id"]), len(files))


@router.get("/{project_id}")
def get_project(project_id: str, user=Depends(current_user)):
    row = require_project(project_id, user["id"])
    return project_json(row, _count(project_id))


@router.delete("/{project_id}", status_code=204)
def delete_project(project_id: str, user=Depends(current_user)):
    require_project(project_id, user["id"])
    with db.conn() as c:
        c.execute("DELETE FROM projects WHERE id = ?", (project_id,))


@router.get("/{project_id}/files")
def files(project_id: str, user=Depends(current_user)):
    require_project(project_id, user["id"])
    return list_files(project_id)


@router.get("/{project_id}/files/content")
def file_content(project_id: str, path: str, user=Depends(current_user)):
    require_project(project_id, user["id"])
    row = get_file(project_id, path)
    if not row:
        raise HTTPException(404, "File not found.")
    return dict(row)


@router.put("/{project_id}/files/content")
def write_file(project_id: str, body: FileWrite, user=Depends(current_user)):
    """Create or update a file inside the stored project copy (never touches your disk)."""
    require_project(project_id, user["id"])
    path = clean_path(body.path)
    if not path:
        raise HTTPException(400, "Invalid file path.")
    if _count(project_id) >= 3000 and not get_file(project_id, path):
        raise HTTPException(413, "Project has too many files.")
    size = len(body.content.encode("utf-8"))
    with db.conn() as c:
        c.execute(
            "INSERT INTO project_files (project_id, path, size, language, content) VALUES (?,?,?,?,?) "
            "ON CONFLICT(project_id, path) DO UPDATE SET size=excluded.size, content=excluded.content, "
            "language=excluded.language",
            (project_id, path, size, language_of(path), body.content),
        )
    return {"path": path, "size": size, "language": language_of(path)}
