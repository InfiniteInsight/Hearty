-- Per-user license / access record. Server-authoritative (service-key only).
create table if not exists licenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','revoked')),
  expires_at timestamptz,
  tier text,
  activation_source text not null default 'manual'
    check (activation_source in ('manual','web_checkout','play_billing','comp')),
  granted_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table licenses enable row level security;
-- Intentionally NO anon/authenticated policies: the gate runs server-side with the
-- service key, so license state stays off the client. Service role bypasses RLS.

-- Rollout safety: grant every existing user an active license so enabling the
-- gate never locks anyone out.
insert into licenses (user_id, status, activation_source)
select id, 'active', 'comp' from auth.users
on conflict (user_id) do nothing;
