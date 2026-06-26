-- Prompt Overlays (Spec 11 Layer 3): owner-editable guidance per AI surface,
-- layered onto locked core prompts. Service-key only (server config, not user data).
create table if not exists prompt_overlays (
  surface     text primary key,            -- 'summary' | 'trends_conversation'
  guidance    text not null default '',    -- the editable overlay block ('' = none)
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
alter table prompt_overlays enable row level security;
insert into prompt_overlays (surface) values ('summary'), ('trends_conversation')
  on conflict (surface) do nothing;

-- Append-only history: one row per save, enabling view + one-click revert.
create table if not exists prompt_overlay_versions (
  id          uuid primary key default gen_random_uuid(),
  surface     text not null,
  guidance    text not null,
  created_at  timestamptz not null default now(),
  created_by  uuid
);
alter table prompt_overlay_versions enable row level security;
create index if not exists prompt_overlay_versions_surface_idx
  on prompt_overlay_versions (surface, created_at desc);
