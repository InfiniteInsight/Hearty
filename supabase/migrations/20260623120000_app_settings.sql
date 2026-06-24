-- App-wide, owner-configurable settings. Single row (id=1). Service-key only.
create table if not exists app_settings (
  id int primary key default 1 check (id = 1),
  provisioning_mode text not null default 'open'
    check (provisioning_mode in ('open','trial','paywall')),
  trial_days int not null default 14 check (trial_days > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table app_settings enable row level security;
-- No anon/authenticated policies: read/written only via the service key (like licenses).
insert into app_settings (id) values (1) on conflict (id) do nothing;

-- Allow auto-provisioned trial licenses.
alter table licenses drop constraint licenses_activation_source_check;
alter table licenses add constraint licenses_activation_source_check
  check (activation_source in ('manual','web_checkout','play_billing','comp','trial'));
