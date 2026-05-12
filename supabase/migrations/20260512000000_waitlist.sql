create table if not exists waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  name text,
  created_at timestamptz not null default now()
);

alter table waitlist enable row level security;

-- Allow anyone to join the waitlist, no reads
create policy "waitlist_insert" on waitlist
  for insert to anon with check (true);

grant insert on table waitlist to anon;
