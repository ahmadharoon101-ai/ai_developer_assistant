"""Talks to the configured AI provider. API keys never leave this server."""
import json
import re
from typing import AsyncIterator

import httpx

from .config import settings

CHAT_SYSTEM_PROMPT = """You are AI Developer Assistant, an expert software engineer helping inside a developer tool.
Be accurate, direct and practical. Answer the user's actual question; do not repeat the question back.

Formatting rules (the app renders only these):
- Use ### headings, "- " bullets, **bold**, `inline code`, and fenced code blocks with a language tag.
- No tables, no HTML, no images.

When the user pastes an error, stack trace or asks you to debug, structure the answer with these headings:
### Problem, ### Cause, ### Solution (with a code block or commands), ### Explanation.
For other questions, answer naturally and only use headings when they help.
If you need more information (missing code, versions, full traceback), ask for it briefly instead of guessing."""

STYLE_HINTS = {
    "concise": "Keep answers short: lead with the answer, minimal explanation.",
    "balanced": "Balance brevity with enough explanation to be useful.",
    "detailed": "Be thorough: explain reasoning, trade-offs and edge cases.",
}

TIMEOUT = httpx.Timeout(120.0, connect=10.0)


class AIError(Exception):
    """A message that is safe to show to the user."""


def chat_system(style: str = "balanced", project_context: str = "") -> str:
    parts = [CHAT_SYSTEM_PROMPT, STYLE_HINTS.get(style, STYLE_HINTS["balanced"])]
    if project_context:
        parts.append(
            "The user has attached a project. Use it to answer. Refer to files by path.\n\n"
            + project_context
        )
    return "\n\n".join(parts)


MAX_IMAGES = 4
MAX_IMAGE_BYTES = 6_000_000  # ~6MB decoded, per image


def _normalize(history: list[dict]) -> list[dict]:
    out: list[dict] = []
    for m in history:
        if out and out[-1]["role"] == m["role"]:
            out[-1]["content"] += "\n\n" + m["content"]
        else:
            out.append({"role": m["role"], "content": m["content"]})
    while out and out[0]["role"] != "user":
        out.pop(0)
    return out


def validate_images(images: list[dict] | None) -> list[dict]:
    """images: [{"mime": "image/png", "data": "<base64>"}]. Raises AIError on anything malformed."""
    if not images:
        return []
    if len(images) > MAX_IMAGES:
        raise AIError(f"Attach at most {MAX_IMAGES} images per message.")
    allowed = {"image/png", "image/jpeg", "image/webp", "image/gif"}
    out = []
    for img in images:
        mime = img.get("mime", "")
        data = img.get("data", "")
        if mime not in allowed:
            raise AIError(f"Unsupported image type: {mime or 'unknown'}.")
        if not data or len(data) > MAX_IMAGE_BYTES * 4 // 3:  # base64 overhead
            raise AIError("An attached image is missing or too large (max ~6MB).")
        out.append({"mime": mime, "data": data})
    return out


def provider_label(model: str | None = None) -> str:
    return f"{settings.ai_provider} ({model or settings.active_model})"


async def stream_reply(history: list[dict], system: str = CHAT_SYSTEM_PROMPT, model: str | None = None,
                       temperature: float | None = None, json_mode: bool = False,
                       max_tokens: int = 8192, images: list[dict] | None = None) -> AsyncIterator[str]:
    if not settings.active_key:
        raise AIError(
            f"The backend has no API key for '{settings.ai_provider}'. "
            "Add it to backend/.env and restart the server."
        )
    messages = _normalize(history)
    if not messages:
        raise AIError("There is nothing to answer yet.")
    model = model or settings.active_model
    images = validate_images(images)
    if images and settings.ai_provider not in ("anthropic", "gemini"):
        images = []
    if settings.ai_provider == "anthropic":
        gen = _anthropic(messages, system, model, temperature, max_tokens, images)
    elif settings.ai_provider == "gemini":
        gen = _gemini(messages, system, model, temperature, json_mode, images)
    else:
        raise AIError(f"Unknown AI_PROVIDER '{settings.ai_provider}'. Use 'gemini' or 'anthropic'.")
    async for chunk in gen:
        yield chunk


async def complete(system: str, prompt: str, temperature: float = 0.2, json_mode: bool = False,
                   model: str | None = None, max_tokens: int = 8192) -> str:
    parts: list[str] = []
    async for c in stream_reply([{"role": "user", "content": prompt}], system=system, model=model,
                                temperature=temperature, json_mode=json_mode, max_tokens=max_tokens):
        parts.append(c)
    text = "".join(parts).strip()
    if not text:
        raise AIError("The model returned an empty response. Try again.")
    return text


def parse_json(text: str) -> dict:
    t = text.strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t, flags=re.IGNORECASE)
    start, end = t.find("{"), t.rfind("}")
    if start == -1 or end <= start:
        raise AIError("The model returned an unreadable answer. Try again.")
    try:
        data = json.loads(t[start : end + 1])
    except ValueError:
        raise AIError("The model returned an unreadable answer. Try again.")
    if not isinstance(data, dict):
        raise AIError("The model returned an unreadable answer. Try again.")
    return data


async def complete_json(system: str, prompt: str, temperature: float = 0.2, max_tokens: int = 8192) -> dict:
    text = await complete(system, prompt, temperature=temperature, json_mode=True, max_tokens=max_tokens)
    return parse_json(text)


async def _raise_for_status(resp: httpx.Response) -> None:
    if resp.status_code < 400:
        return
    body = (await resp.aread()).decode("utf-8", "replace")
    detail = ""
    try:
        detail = json.loads(body).get("error", {}).get("message", "")
    except (ValueError, AttributeError):
        pass
    hint = {
        400: "The provider rejected the request.",
        401: "The API key was rejected. Check the key in backend/.env.",
        403: "The API key is not allowed to use this model.",
        404: "Model not found. Check the model name in backend/.env.",
        429: "The provider rate limit or quota was hit. Wait a moment and retry.",
    }.get(resp.status_code, f"The provider returned an error ({resp.status_code}).")
    raise AIError(f"{hint} {detail}".strip()[:500])


async def _sse_json(resp: httpx.Response) -> AsyncIterator[dict]:
    async for line in resp.aiter_lines():
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if not payload or payload == "[DONE]":
            continue
        try:
            yield json.loads(payload)
        except ValueError:
            continue


def _attach_anthropic_images(messages: list[dict], images: list[dict]) -> list[dict]:
    if not images:
        return messages
    out = [dict(m) for m in messages]
    last = out[-1]
    blocks = [{"type": "text", "text": last["content"]}]
    for img in images:
        blocks.append({"type": "image",
                        "source": {"type": "base64", "media_type": img["mime"], "data": img["data"]}})
    out[-1] = {"role": "user", "content": blocks}
    return out


async def _anthropic(messages, system, model, temperature, max_tokens, images: list[dict] | None = None) -> AsyncIterator[str]:
    messages = _attach_anthropic_images(messages, images or [])
    body = {"model": model, "max_tokens": max_tokens, "system": system, "messages": messages, "stream": True}
    if temperature is not None:
        body["temperature"] = temperature
    headers = {
        "x-api-key": settings.anthropic_api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            async with client.stream(
                "POST", "https://api.anthropic.com/v1/messages", json=body, headers=headers
            ) as resp:
                await _raise_for_status(resp)
                async for ev in _sse_json(resp):
                    if ev.get("type") == "content_block_delta":
                        text = ev.get("delta", {}).get("text")
                        if text:
                            yield text
                    elif ev.get("type") == "error":
                        raise AIError(ev.get("error", {}).get("message", "The provider reported an error."))
    except httpx.TimeoutException:
        raise AIError("The AI provider took too long to respond. Try again.")
    except httpx.HTTPError:
        raise AIError("Could not reach the AI provider from the server.")


async def _gemini(messages, system, model, temperature, json_mode, images: list[dict] | None = None) -> AsyncIterator[str]:
    contents = [
        {"role": "user" if m["role"] == "user" else "model", "parts": [{"text": m["content"]}]}
        for m in messages
    ]
    for img in images or []:
        contents[-1]["parts"].append({"inlineData": {"mimeType": img["mime"], "data": img["data"]}})
    body: dict = {"systemInstruction": {"parts": [{"text": system}]}, "contents": contents}
    gen_cfg: dict = {}
    if temperature is not None:
        gen_cfg["temperature"] = temperature
    if json_mode:
        gen_cfg["responseMimeType"] = "application/json"
    if gen_cfg:
        body["generationConfig"] = gen_cfg
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:streamGenerateContent?alt=sse"
    )
    headers = {"x-goog-api-key": settings.gemini_api_key, "content-type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            async with client.stream("POST", url, json=body, headers=headers) as resp:
                await _raise_for_status(resp)
                async for ev in _sse_json(resp):
                    for cand in ev.get("candidates", []):
                        for part in cand.get("content", {}).get("parts", []):
                            if part.get("thought"):
                                continue
                            text = part.get("text")
                            if text:
                                yield text
    except httpx.TimeoutException:
        raise AIError("The AI provider took too long to respond. Try again.")
    except httpx.HTTPError:
        raise AIError("Could not reach the AI provider from the server.")
