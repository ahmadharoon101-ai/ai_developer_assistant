import json

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .. import ai, db
from ..deps import limit_ai
from ..projects_service import all_files, build_context, get_file, require_project

router = APIRouter(prefix="/ai", tags=["ai"])

SEVERITIES = {"critical", "high", "medium", "low", "info"}
FOCUS = {"explain", "bugs", "smells", "complexity", "improve", "security", "performance"}
FOCUS_TEXT = {
    "explain": "explain what the code does in plain language (put this in `summary`)",
    "bugs": "find real bugs and logic errors",
    "smells": "detect code smells and maintainability problems",
    "complexity": "analyze complexity (cyclomatic/cognitive, deep nesting, long functions)",
    "improve": "suggest concrete improvements",
    "security": "find security problems (injection, secrets, unsafe deserialization, auth flaws)",
    "performance": "find performance problems",
}

TOOL_SYSTEM = (
    "You are a senior software engineer reviewing code. Be specific and honest. "
    "Only report issues you can point to in the provided code; never invent files or line numbers. "
    "If the code is fine, say so and return few or no issues."
)


class AnalyzeIn(BaseModel):
    project_id: str | None = None
    path: str | None = None
    code: str | None = Field(default=None, max_length=60_000)
    language: str | None = None
    focus: list[str] = ["bugs", "smells", "security"]


class DebugIn(BaseModel):
    error: str = Field(min_length=1, max_length=20_000)
    stack_trace: str = Field(default="", max_length=30_000)
    code: str = Field(default="", max_length=40_000)
    language: str = Field(default="", max_length=40)


class GenerateIn(BaseModel):
    mode: str = "generate"  # generate | improve | explain
    language: str = Field(max_length=40)
    framework: str = Field(default="", max_length=40)
    kind: str = Field(default="", max_length=40)
    prompt: str = Field(default="", max_length=8_000)
    code: str = Field(default="", max_length=40_000)


class TestsIn(BaseModel):
    project_id: str
    path: str
    symbol: str = Field(default="", max_length=120)
    kinds: list[str] = ["unit", "edge", "negative"]
    framework: str = Field(default="", max_length=60)


class DocsIn(BaseModel):
    project_id: str
    doc_type: str = "readme"
    path: str | None = None


class AgentPlanIn(BaseModel):
    project_id: str
    request: str = Field(min_length=3, max_length=4_000)


def _run(project_id: str | None, user_id: int, files: int, issues: int) -> None:
    with db.conn() as c:
        c.execute(
            "INSERT INTO analysis_runs (user_id, project_id, files, issues, created_at) VALUES (?,?,?,?,?)",
            (user_id, project_id, files, issues, db.now()),
        )
        if project_id:
            c.execute(
                "UPDATE projects SET last_analyzed = ?, last_issue_count = ? WHERE id = ?",
                (db.now(), issues, project_id),
            )


def _guard(coro_exc: Exception):
    raise HTTPException(502, str(coro_exc))


@router.post("/analyze")
async def analyze(body: AnalyzeIn, user=Depends(limit_ai)):
    focus = [f for f in body.focus if f in FOCUS] or ["bugs", "smells", "security"]
    file_count = 1
    if body.project_id:
        require_project(body.project_id, user["id"])
        if body.path:
            f = get_file(body.project_id, body.path)
            if not f:
                raise HTTPException(404, "File not found.")
            context, subject = f"=== {f['path']} ===\n{f['content'][:60_000]}", f["path"]
        else:
            files = all_files(body.project_id)
            if not files:
                raise HTTPException(400, "This project has no files yet. Upload or import code first.")
            context, file_count = build_context(files)
            subject = "the whole project"
    elif body.code and body.code.strip():
        context, subject = f"```{body.language or ''}\n{body.code}\n```", "the pasted code"
    else:
        raise HTTPException(400, "Provide a project (and optionally a file) or paste some code.")

    tasks = "\n".join(f"- {FOCUS_TEXT[f]}" for f in focus)
    prompt = f"""Analyze {subject}. Tasks:
{tasks}

Return ONLY JSON with this exact shape:
{{"summary": "2-6 sentence overview / explanation",
  "complexity": "low|medium|high",
  "issues": [{{"title": "short title", "severity": "critical|high|medium|low|info",
              "category": "bug|smell|complexity|security|performance|improvement",
              "location": "path:line or path or function name",
              "explanation": "why this is a problem",
              "suggested_fix": "concrete fix; include a short code snippet if useful"}}]}}

Code:
{context}"""
    try:
        data = await ai.complete_json(TOOL_SYSTEM, prompt, temperature=0.2)
    except ai.AIError as e:
        raise HTTPException(502, str(e))

    issues = []
    for i in data.get("issues") or []:
        if not isinstance(i, dict):
            continue
        sev = str(i.get("severity", "info")).lower()
        issues.append({
            "title": str(i.get("title", "Issue"))[:200],
            "severity": sev if sev in SEVERITIES else "info",
            "category": str(i.get("category", ""))[:40],
            "location": str(i.get("location", ""))[:300],
            "explanation": str(i.get("explanation", "")),
            "suggested_fix": str(i.get("suggested_fix", "")),
        })
    _run(body.project_id, user["id"], file_count, len(issues))
    return {
        "summary": str(data.get("summary", "")),
        "complexity": str(data.get("complexity", "")),
        "files_analyzed": file_count,
        "issues": issues,
    }


@router.post("/debug")
async def debug(body: DebugIn, user=Depends(limit_ai)):
    prompt = f"""Diagnose this error.
Language/runtime: {body.language or 'unknown'}

Error message:
{body.error}

Stack trace:
{body.stack_trace or '(none)'}

Relevant code:
{body.code or '(none)'}

Return ONLY JSON:
{{"problem": "what is wrong, 1-3 sentences",
  "cause": "why it happens, specific to this input",
  "solution": "markdown: exact commands or code changes, with fenced code blocks that have language tags",
  "explanation": "why the solution works",
  "fix_code": "the corrected code as a plain string if the fix is a code change, else empty string",
  "fix_language": "language of fix_code or shell for commands"}}
If information is missing to be sure, say what is missing in `cause` and give the most likely fix."""
    try:
        d = await ai.complete_json(TOOL_SYSTEM, prompt, temperature=0.2)
    except ai.AIError as e:
        raise HTTPException(502, str(e))
    return {k: str(d.get(k, "")) for k in ("problem", "cause", "solution", "explanation", "fix_code", "fix_language")}


@router.post("/generate")
async def generate(body: GenerateIn, user=Depends(limit_ai)):
    stack = f"{body.language}" + (f" with {body.framework}" if body.framework else "")
    if body.mode == "explain":
        if not body.code.strip():
            raise HTTPException(400, "There is no code to explain yet.")
        system = "You explain code clearly to working developers."
        prompt = f"Explain this {stack} code step by step. Use ### headings and bullets, keep it tight.\n\n```\n{body.code}\n```"
    elif body.mode == "improve":
        if not body.code.strip():
            raise HTTPException(400, "There is no code to improve yet.")
        system = "You are a senior engineer improving code without changing its behavior unless asked."
        prompt = (f"Improve this {stack} code (readability, correctness, error handling, performance). "
                  f"{('Extra instruction: ' + body.prompt) if body.prompt else ''}\n"
                  "Reply with ONE fenced code block containing the full improved code, then a '### Changes' section with bullets.\n\n"
                  f"```\n{body.code}\n```")
    else:
        if not body.prompt.strip():
            raise HTTPException(400, "Describe what you want to build.")
        system = "You are a senior engineer who writes clean, idiomatic, production-quality code."
        kind = f" Target: {body.kind}." if body.kind else ""
        prompt = (f"Write {stack} code for this request.{kind}\n\nRequest: {body.prompt}\n\n"
                  "Reply with ONE fenced code block (language tag included) containing complete, runnable code "
                  "with sensible error handling, then a short '### Notes' section (max 5 bullets) with setup steps "
                  "or assumptions. Do not add anything else.")
    try:
        text = await ai.complete(system, prompt, temperature=0.3)
    except ai.AIError as e:
        raise HTTPException(502, str(e))
    return {"content": text}


@router.post("/tests")
async def tests(body: TestsIn, user=Depends(limit_ai)):
    require_project(body.project_id, user["id"])
    f = get_file(body.project_id, body.path)
    if not f:
        raise HTTPException(404, "File not found.")
    kinds = ", ".join(body.kinds) or "unit"
    target = f"the `{body.symbol}` function/class in" if body.symbol else "all public functions/classes in"
    prompt = (f"Write tests for {target} `{f['path']}` ({f['language'] or 'unknown language'}).\n"
              f"Test types to include: {kinds} (unit, integration, api, edge cases, negative tests).\n"
              f"Test framework: {body.framework or 'the standard/most common one for this language'}.\n"
              "Reply with ONE fenced code block containing a complete test file (imports included), then a "
              "'### Notes' section with bullets on how to run it and any assumptions. Do not invent APIs that "
              f"are not in the code.\n\n=== {f['path']} ===\n{f['content'][:40_000]}")
    try:
        text = await ai.complete("You write reliable, readable automated tests.", prompt, temperature=0.2)
    except ai.AIError as e:
        raise HTTPException(502, str(e))
    return {"content": text}


DOC_TYPES = {
    "readme": "a complete README.md (overview, features, tech stack, installation, usage, project structure, contributing)",
    "api": "API documentation (endpoints/functions, parameters, responses, examples)",
    "install": "an installation and setup guide with exact commands",
    "architecture": "architecture documentation (components, data flow, key decisions), with an ASCII diagram if helpful",
    "developer": "a developer guide (how to work on the code, conventions, testing, common tasks)",
    "comments": "code comments/docstrings: return the file with documentation comments added, code unchanged",
}


@router.post("/documentation")
async def documentation(body: DocsIn, user=Depends(limit_ai)):
    if body.doc_type not in DOC_TYPES:
        raise HTTPException(400, "Unknown documentation type.")
    project = require_project(body.project_id, user["id"])
    if body.doc_type == "comments":
        if not body.path:
            raise HTTPException(400, "Pick a file to add comments to.")
        f = get_file(body.project_id, body.path)
        if not f:
            raise HTTPException(404, "File not found.")
        context = f"=== {f['path']} ===\n{f['content'][:40_000]}"
    else:
        files = all_files(body.project_id)
        if not files:
            raise HTTPException(400, "This project has no files yet.")
        context, _ = build_context(files)
    prompt = (f"Project name: {project['name']}\nWrite {DOC_TYPES[body.doc_type]}.\n"
              "Base everything on the provided files; do not invent features, commands or endpoints that are not "
              "there. Output Markdown only (for 'comments', output one fenced code block).\n\n" + context)
    try:
        text = await ai.complete("You are a meticulous technical writer.", prompt, temperature=0.3)
    except ai.AIError as e:
        raise HTTPException(502, str(e))
    return {"content": text}


@router.post("/agent/plan")
async def agent_plan(body: AgentPlanIn, user=Depends(limit_ai)):
    project = require_project(body.project_id, user["id"])
    files = all_files(body.project_id)
    if not files:
        raise HTTPException(400, "This project has no files yet.")
    context, _ = build_context(files, budget=50_000)
    prompt = f"""A developer wants this done in project "{project['name']}":
"{body.request}"

Produce an execution plan. Only reference files that exist in the file list unless you mark them as new.
Return ONLY JSON:
{{"summary": "one-sentence approach",
  "steps": [{{"stage": "analysis|file_selection|modification|testing|fixing|report",
             "title": "short imperative title",
             "detail": "what will be done and why",
             "files": ["path", "..."]}}],
  "risks": ["short risk or assumption", "..."]}}

{context}"""
    try:
        d = await ai.complete_json("You are a careful staff engineer planning a change.", prompt, temperature=0.2)
    except ai.AIError as e:
        raise HTTPException(502, str(e))
    steps = []
    for s in d.get("steps") or []:
        if isinstance(s, dict):
            steps.append({
                "stage": str(s.get("stage", "modification")),
                "title": str(s.get("title", "Step"))[:200],
                "detail": str(s.get("detail", "")),
                "files": [str(x) for x in (s.get("files") or []) if isinstance(x, (str,))][:20],
            })
    return {
        "summary": str(d.get("summary", "")),
        "steps": steps,
        "risks": [str(x) for x in (d.get("risks") or [])][:10],
    }
