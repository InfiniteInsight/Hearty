-- Daily check-in dismissals: gaps the user skipped during a day's review. The
-- gaps endpoint filters these out so a skipped gap stays gone for the day, while
-- a genuinely new gap (different key) still surfaces. Keyed by a deterministic
-- gap_key (e.g. "food:<meal_id>:<name>", "chunk:<window_start>"). Service-key
-- access from the API; RLS is defense-in-depth (auth.uid() = user_id).
create table if not exists checkin_dismissals (
  user_id     uuid not null references auth.users(id) on delete cascade,
  target_date date not null,
  gap_key     text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, target_date, gap_key)
);

alter table checkin_dismissals enable row level security;

create policy "own checkin dismissals - select" on checkin_dismissals
  for select using (auth.uid() = user_id);
create policy "own checkin dismissals - insert" on checkin_dismissals
  for insert with check (auth.uid() = user_id);
create policy "own checkin dismissals - delete" on checkin_dismissals
  for delete using (auth.uid() = user_id);
