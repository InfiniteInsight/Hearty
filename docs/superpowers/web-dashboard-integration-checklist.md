# Web Dashboard — Integration Checklist (spec §10)

Run against a **Vercel preview deploy** (or production) with the real FastAPI backend and a **throwaway test account**. The final step is destructive — use a throwaway account.

## Setup
- [ ] Vercel env vars set (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY / VITE_API_URL).
- [ ] Supabase redirect URL includes `<origin>/auth/callback`.
- [ ] Backend `ALLOWED_ORIGINS` includes the origin.

## Flows
- [ ] **Auth:** unauthenticated `/dashboard` → redirect to `/login`; Google sign-in → lands on Dashboard.
- [ ] **Realtime:** quick-log a meal on the dashboard → appears without a manual refresh; log a meal on the phone → appears on web (realtime, or within refetch-on-focus).
- [ ] **Journal:** filters (date/keyword/meal-type/symptom-type) reflect in the URL and survive refresh; pagination works; expand → edit a meal (foods preserved) → Dashboard/Trends update; delete (two-step) removes it.
- [ ] **Trends:** renders signal cards or a clean empty-state; period selector switches charts; Analyse refreshes; submit a signal verdict.
- [ ] **Conversation:** `/trends/chat` opener loads; send a message; confirm a proposed verdict; start a proposed experiment → it appears on Experiments.
- [ ] **Experiments:** list renders; evaluate / abandon / restart / ack-nudge behave; results render.
- [ ] **Reports:** date-range preview loads; CSV, JSON, and PDF each download.
- [ ] **Profile:** add/edit allergen + dietary protocol, Save, reload → persisted; disclaimer always visible, non-dismissable.
- [ ] **Settings:** toggle a preference + Save (health fields preserved); Export all data downloads JSON; Sign out → `/login`.
- [ ] **Delete account (throwaway account, LAST):** typed-confirmation → account + data deleted → signed out → `/login`; re-login fails / starts fresh.

## Sign-off
- [ ] All flows pass on the preview deploy.
- [ ] Production promoted from `master`.
