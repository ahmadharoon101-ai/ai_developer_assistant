# AI Developer Assistant

Build. Debug. Understand. Ship.

A Flutter client (dark, developer-focused UI) backed by a real FastAPI server that calls a real AI
model (Gemini or Claude). No mock data: every screen reads and writes through the backend and a
SQLite database, and AI answers come from the provider you configure.

## What's included
- **Flutter app** (`lib/`): Dashboard, AI Chat (streaming, real conversation history), Projects
  (ZIP upload, GitHub import, file explorer), Code Analyzer, Debugger, Code Generator, Test
  Generator, Documentation Generator, GitHub integration, AI Agent (planning preview), Settings.
- **FastAPI backend** (`backend/`): auth (JWT + bcrypt), SQLite storage, project ingestion (ZIP/GitHub,
  stored as text and never executed), streaming AI chat over WebSocket, and the analyze/debug/
  generate/tests/documentation/agent-plan endpoints the app calls.

## 1. Run the backend first
```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env             # Windows: copy .env.example .env
```
Edit `backend/.env`:
- Set `JWT_SECRET` (generate one: `python -c "import secrets; print(secrets.token_urlsafe(48))"`)
- Set `GEMINI_API_KEY` (get one free at https://aistudio.google.com/apikey), or set
  `AI_PROVIDER=anthropic` and `ANTHROPIC_API_KEY`
- Leave `GITHUB_CLIENT_ID`/`SECRET` empty to use personal-access-token GitHub connect instead of OAuth

Start it:
```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Check http://localhost:8000/health — `api_key_configured` must be `true`. Interactive docs at
http://localhost:8000/docs. Run the backend smoke tests (no network/API key needed, the AI client
is stubbed) with `python -m tests.test_api` from inside `backend/`.

## 2. Run the Flutter app
This zip ships only `lib/` and `pubspec.yaml`; generate the platform folders once:
```bash
flutter create . --project-name ai_developer_assistant --platforms=android,ios,web,windows,macos,linux
flutter pub get
flutter run -d chrome
```
By default the app talks to `http://localhost:8000` (Android emulator automatically uses
`10.0.2.2` instead of `localhost`). Point it elsewhere with:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000   # phone on your Wi-Fi, use your PC's LAN IP
```

Register a real account in the app (password needs 8+ chars with a letter and a number) and sign in.

## Forgot / reset password
`POST /auth/forgot-password` always returns the same message either way (so it can't be used to
check which emails are registered). If `SMTP_*` is set in `.env`, it emails an 8-character code;
otherwise the code comes back directly in the response and the app shows it inline, so the flow is
testable without mail infrastructure. Codes expire after 30 minutes and are single-use.

## Theme
Settings → Appearance has real Dark / Light / System options, persisted across launches. Choosing
"System" follows the OS setting live.

## Chat attachments & voice input
- **File**: picks any file; images become an attached thumbnail sent to the model, text files are
  inserted as a fenced code block in the message.
- **Code**: paste code + optional language into a dialog; inserted as a fenced code block.
- **Image**: attaches up to 4 images (6 MB each) that are sent live to the model (Gemini/Claude
  vision). They are **not** saved server-side — reopening the conversation later won't show them
  again, only the message text.
- **Voice input**: uses on-device speech recognition (`speech_to_text`). After `flutter create`,
  add these permissions or the mic button will fail silently on device:
  - **Android** (`android/app/src/main/AndroidManifest.xml`): `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`
  - **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`
  - **macOS** (`macos/Runner/*.entitlements`): `com.apple.security.device.audio-input` and enable the
    microphone capability in Xcode
  - Web and desktop Windows/Linux support for `speech_to_text` varies by plugin version — the button
    shows a clear message if it isn't available rather than failing silently.

## Notes / known limitations
- I could not run `flutter pub get` / compile the Flutter app or run `flutter analyze` in this
  environment (no Flutter SDK here) — the backend's own test suite passes (including the new
  reset-password and image-attachment paths), but please run `flutter analyze` after
  `flutter pub get` and send me any errors.
- `file_saver: 0.2.14` is pinned; if its `saveFile` signature differs on your installed version,
  downloads (`core/utils/file_export.dart`) may need a one-line adjustment.
- Registering an account does **not** sign you in — you land back on the login screen with a
  confirmation message, by design.
- The AI Agent page plans a change (steps + files it would touch) but does not execute anything —
  real execution needs an isolated sandbox on the backend, called out in the app itself. This is a
  deliberate scope boundary, not an oversight: unsandboxed code execution isn't something to bolt
  on casually.
- Android needs `minSdk 23+` for `flutter_secure_storage` — set it in
  `android/app/build.gradle` if `flutter create` gives you a lower default.
- Chat image attachments are sent to the model live but aren't persisted in conversation history
  (SQLite stores a "[N image(s) attached]" placeholder instead) — reopening a conversation later
  won't show the picture again.

## Publishing this to GitHub safely
Nothing in this codebase has a real key or secret hardcoded — every key is read from
`backend/.env` at runtime (see `backend/app/config.py`), which is `.gitignore`d. Before you push:

1. **Confirm `.env` was never committed**: `git status --ignored` should list `backend/.env` under
   ignored files (not tracked). If you already `git add`ed it in the past, remove it from history:
   `git rm --cached backend/.env` (and rotate any key that was in it — treat it as compromised).
2. **Only `.env.example` should be tracked** — it ships with every value blank, safe to publish.
3. **Double-check before your first push**: `git grep -niE "sk-ant|AIza|api[_-]?key\s*=\s*['\"][A-Za-z0-9]" -- . ':!*.example'`
   should return nothing. Re-run this after any change that touches config.
4. Anyone who clones the repo needs their own `backend/.env` (copy `.env.example`) with their own
   Gemini/Anthropic key — the app will not run without one, by design.
5. If you deploy the backend anywhere (Render, Railway, a VPS, etc.), set the same variables as
   real environment variables / secrets in that platform's dashboard — never paste them into a
   committed file.

## Security
- No AI or GitHub keys ever reach the Flutter app; both live only in `backend/.env` /
  the encrypted `github_tokens` table.
- Uploaded/imported code is stored as text in SQLite and is never executed by the server or the app.
- Passwords are hashed with bcrypt; JWTs carry a token version so "sign out everywhere" and password
  changes invalidate old tokens.
