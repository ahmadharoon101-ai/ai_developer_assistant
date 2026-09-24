# AI Developer Assistant - backend (FastAPI)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env             # Windows: copy .env.example .env
# edit .env: set GEMINI_API_KEY (or ANTHROPIC_API_KEY + AI_PROVIDER=anthropic) and JWT_SECRET
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Check http://localhost:8000/health - `api_key_configured` must be true.
Interactive docs: http://localhost:8000/docs
