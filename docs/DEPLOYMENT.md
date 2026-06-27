# Hearty — Production Deployment

The canonical reference for how Hearty runs in production and how to redeploy each piece.

## Live services

| Piece | Where | URL |
|---|---|---|
| **Backend** (FastAPI) | Google Cloud Run — project `hearty-495323`, region `us-central1`, service `hearty-api` | `https://hearty-api-5aclgyfsva-uc.a.run.app` |
| **Web dashboard** (Vite SPA) | Vercel — team "Evan's projects", project `hearty-web` | `https://hearty-web-blush.vercel.app` |
| **Database / Auth / Storage** | Supabase — project `ehuanqnkqehpivwuqpqw` | `https://ehuanqnkqehpivwuqpqw.supabase.co` |
| **Phone** (Flutter) | Sideload / store build | points at `API_BASE_URL` (set to the Cloud Run URL for prod) |

> History: the backend was originally scoped for Fly.io (`fly.toml`); it now runs on **Cloud Run**. There is no Fly deployment.

Secrets are never stored in this repo. Backend secrets live in the local `.env` (gitignored) and are set as **Cloud Run env vars**; web build-time vars are set in **Vercel**.

---

## Backend — Cloud Run

Container: `hearty-api/Dockerfile` (uvicorn on port 8080 = Cloud Run default). Built from source by Cloud Build; the upload respects `hearty-api/.gitignore` (so `.venv`/`.env` are excluded).

**Required env vars** (set on the service; pulled from `.env`):
`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `LLM_MODEL`, `ANTHROPIC_API_KEY` (or the key matching `LLM_MODEL`), `GEMINI_API_KEY` (knowledge-base RAG embeddings — `gemini/gemini-embedding-001`), `BRAVE_SEARCH_API_KEY`, `ALLOWED_ORIGINS`, `CLEANUP_TOKEN`, `PHOTO_RETENTION_HOURS`.
Optional/defaulted: `PHOTO_BUCKET` (default `food-photos` — matches the prod Storage bucket), `SUPABASE_WEBHOOK_SECRET`, `FDC_API_KEY` (optional: USDA generic-food nutrition tier; free key from https://fdc.nal.usda.gov/api-key-signup.html — unset skips the tier silently), `NUTRITIONIX_APP_ID`/`NUTRITIONIX_API_KEY` (optional: restaurant food lookup tier).

> **API keys (migrated 2026-06-26):** the project uses Supabase's **new API keys**, and the **legacy `anon`/`service_role` JWT keys are disabled**. `SUPABASE_SERVICE_KEY` is the **secret** key (`sb_secret_…`, full service-role access incl. GoTrue auth-admin); the web's `VITE_SUPABASE_ANON_KEY` is the **publishable** key (`sb_publishable_…`). Manage/rotate both under **Supabase → Settings → API Keys** (independently rotatable — rotating a new key does NOT touch the JWT secret or user sessions). The legacy JWTs are dead; don't reintroduce them. **Flutter app:** its Supabase client must use the **publishable** key too — rebuild with `SUPABASE_ANON_KEY=sb_publishable_…` before it can auth against prod again (the old build embeds the now-disabled legacy anon JWT).

> **CRITICAL:** `--env-vars-file` **replaces the entire env set** (not additive). The build loop below must list **every** key the service needs, or a redeploy silently un-sets the omitted ones. The loop skips any key that's empty in `.env`, so listing an unused optional key is harmless.

**Redeploy** (gcloud is installed at `~/google-cloud-sdk`; auth as the project owner first with `gcloud auth login`):
```bash
cd hearty-api    # or wherever master's backend lives
# build an env-vars file from .env without echoing secrets:
: > /tmp/hearty-env.yaml
for k in SUPABASE_URL SUPABASE_SERVICE_KEY LLM_MODEL ANTHROPIC_API_KEY GEMINI_API_KEY BRAVE_SEARCH_API_KEY FDC_API_KEY ALLOWED_ORIGINS CLEANUP_TOKEN PHOTO_RETENTION_HOURS PHOTO_BUCKET SUPABASE_WEBHOOK_SECRET; do
  v=$(grep -E "^$k=" ../.env | cut -d= -f2-); [ -n "$v" ] && printf '%s: "%s"\n' "$k" "$v" >> /tmp/hearty-env.yaml
done
gcloud run deploy hearty-api \
  --source . --region us-central1 \
  --allow-unauthenticated --memory 1Gi --min-instances 0 \
  --no-cpu-throttling \
  --env-vars-file /tmp/hearty-env.yaml
shred -u /tmp/hearty-env.yaml
```

**Why these flags:**
- `--allow-unauthenticated` — the app does its own JWT auth + license gate; Cloud Run IAM stays open.
- `--min-instances 0` — scale to zero (cheapest); cold start is a few seconds, acceptable.
- `--no-cpu-throttling` — **required**: photo analysis, trends-analyze, and check-in run as FastAPI `BackgroundTasks` *after* the response is sent. Cloud Run's default (CPU only during a request) would starve them. This keeps CPU allocated for the instance lifetime so background work completes.

**Update one env var** (no rebuild, new revision):
```bash
gcloud run services update hearty-api --region us-central1 \
  --update-env-vars ALLOWED_ORIGINS=https://hearty-web-blush.vercel.app
```

---

## Web — Vercel

Vite SPA in `hearty-web/`. Root Directory = `hearty-web`; `vercel.json` adds the SPA rewrite. Vercel CLI is authenticated as `infiniteinsight-5162` (team "Evan's projects").

**Build-time env vars** (Production + Preview):
- `VITE_SUPABASE_URL` = `https://ehuanqnkqehpivwuqpqw.supabase.co`
- `VITE_SUPABASE_ANON_KEY` = the Supabase **publishable** key (`sb_publishable_…`, public client key — never the secret key). Legacy anon JWT is disabled.
- `VITE_API_URL` = `https://hearty-api-5aclgyfsva-uc.a.run.app`

`VITE_*` vars are inlined at build time, so they must be set **before** a deploy.

**Redeploy:**
```bash
cd hearty-web
npx vercel@latest deploy --prod   # or `deploy` for a preview URL
```

---

## Supabase — Auth config

Web Google sign-in requires the web origin in the auth redirect allow-list. Managed via the dashboard (Authentication → URL Configuration) or the Management API (token in `~/.supabase/access-token`):
```bash
TOKEN=$(cat ~/.supabase/access-token)
curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  https://api.supabase.com/v1/projects/ehuanqnkqehpivwuqpqw/config/auth \
  -d '{"site_url":"https://hearty-web-blush.vercel.app","uri_allow_list":"http://localhost:5173/**,https://hearty-web-blush.vercel.app/**"}'
```
Current: `site_url` = the Vercel prod URL; allow-list keeps `http://localhost:5173/**` for local dev. The phone uses its own deep-link redirect (not in this list).

## Database — migrations

```bash
export SUPABASE_DB_PASSWORD="$(grep -E '^SUPABASE_DB_PASSWORD=' .env | cut -d= -f2-)"
supabase link --project-ref ehuanqnkqehpivwuqpqw
supabase db push
```
Apply migrations **before** deploying backend code that depends on them.

---

## Licensing / provisioning (live)

The `require_active_license` gate is active on all data routes. New signups are provisioned per the owner-set **provisioning mode** in `app_settings` (default `open` = auto-grant). Change it in the web **/admin → Signup policy** control (or `PUT /api/admin/settings`). Owner accounts need `app_metadata.role="admin"` (set in Supabase).

## Photo retention (after PR #17 merges + redeploy)

Raw images are deleted on successful analysis; failed/unprocessed ones are purged after `PHOTO_RETENTION_HOURS` (default 24) by `POST /internal/photos/purge`. To enable in prod:
1. Apply the `image_purged_at` migration (`supabase db push`).
2. Set Cloud Run env: `CLEANUP_TOKEN=<≥32 random bytes, never logged>`, `PHOTO_RETENTION_HOURS=24`.
3. Create an hourly Cloud Scheduler job:
   ```bash
   gcloud scheduler jobs create http hearty-photo-purge \
     --schedule="0 * * * *" --location=us-central1 \
     --uri="https://hearty-api-5aclgyfsva-uc.a.run.app/internal/photos/purge" \
     --http-method=POST --headers="X-Cleanup-Token=<token>"
   ```
The endpoint is publicly routable, protected solely by the secret token (fail-closed).

---

## Smoke check after any deploy

```bash
curl -s https://hearty-api-5aclgyfsva-uc.a.run.app/health           # {"status":"ok"}
curl -s -o /dev/null -w "%{http_code}\n" https://hearty-web-blush.vercel.app   # 200
# CORS preflight from the web origin should echo access-control-allow-origin:
curl -s -i -X OPTIONS https://hearty-api-5aclgyfsva-uc.a.run.app/api/preferences \
  -H "Origin: https://hearty-web-blush.vercel.app" \
  -H "Access-Control-Request-Method: GET" | grep -i access-control-allow-origin
```
Full interactive QA: `docs/superpowers/web-dashboard-integration-checklist.md`.
