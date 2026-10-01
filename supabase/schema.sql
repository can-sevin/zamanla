-- Zamanla — Supabase şeması
-- Supabase Dashboard > SQL Editor'e yapıştırıp bir kez çalıştırın.
--
-- Senkronizasyon modeli:
--   * Her satır (user_id, id) ile tanımlanır; id istemcide üretilir.
--   * updated_at istemcinin son değişiklik zamanıdır (last-write-wins).
--   * server_updated_at sunucu tarafından atanır; istemciler değişiklikleri
--     bu sütuna göre çeker.
--   * Silme işlemleri yumuşaktır (deleted = true).

create or replace function public.zamanla_touch_row()
returns trigger
language plpgsql
as $$
begin
  -- Eski bir cihazdan gelen bayat yazma, daha yeni sunucu kaydını ezmesin.
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

-- ---------------------------------------------------------------- areas
create table if not exists public.areas (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  color bigint not null,
  icon text not null default '',
  kind text not null default 'other',
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- goals
create table if not exists public.goals (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  area_id text,
  title text not null,
  description text not null default '',
  target_date timestamptz,
  progress_mode text not null default 'tasks',
  target_value double precision not null default 100,
  current_value double precision not null default 0,
  unit text not null default '',
  status text not null default 'active',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- tasks
create table if not exists public.tasks (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  area_id text,
  goal_id text,
  parent_id text,
  title text not null,
  notes text not null default '',
  priority integer not null default 0,
  important boolean not null default false,
  urgent boolean not null default false,
  due_at timestamptz,
  due_has_time boolean not null default false,
  estimate_minutes integer,
  status text not null default 'todo',
  completed_at timestamptz,
  tags text not null default '',
  sort_order integer not null default 0,
  recurrence text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- blocks (takvim zaman blokları)
create table if not exists public.blocks (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  area_id text,
  task_id text,
  title text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  notes text not null default '',
  color bigint,
  kind text not null default 'event',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- time_entries (zaman takibi)
create table if not exists public.time_entries (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  task_id text,
  area_id text,
  start_at timestamptz not null,
  end_at timestamptz,
  kind text not null default 'manual',
  note text not null default '',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- habits
create table if not exists public.habits (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  area_id text,
  name text not null,
  icon text not null default '',
  color bigint not null,
  target_per_day integer not null default 1,
  weekdays integer not null default 127,
  archived boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- habit_logs
create table if not exists public.habit_logs (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  habit_id text not null,
  day text not null,
  count integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

-- ---------------------------------------------------------------- ortak: indeks, tetikleyici, RLS, realtime
do $$
declare
  t text;
begin
  foreach t in array array['areas', 'goals', 'tasks', 'blocks', 'time_entries', 'habits', 'habit_logs']
  loop
    execute format(
      'create index if not exists %I on public.%I (user_id, server_updated_at)',
      t || '_sync_idx', t);

    execute format('drop trigger if exists zamanla_touch on public.%I', t);
    execute format(
      'create trigger zamanla_touch before insert or update on public.%I '
      'for each row execute function public.zamanla_touch_row()', t);

    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "own rows" on public.%I', t);
    execute format(
      'create policy "own rows" on public.%I for all to authenticated '
      'using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);

    -- Diğer cihazlardaki değişikliklerin anında gelmesi için realtime yayını.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
