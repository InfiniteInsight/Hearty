-- Service monitoring: last LLM call outcome (single row), updated by the litellm
-- health callback. Service-key only.
create table if not exists service_health (
  id int primary key default 1 check (id = 1),
  llm_last_ok_at    timestamptz,
  llm_last_error_at timestamptz,
  llm_last_error    text,
  llm_last_model    text,
  updated_at        timestamptz not null default now()
);
alter table service_health enable row level security;
insert into service_health (id) values (1) on conflict (id) do nothing;
