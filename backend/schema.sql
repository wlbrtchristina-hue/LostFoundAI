-- ============================================================
-- 校园失物招领：items / matches 建表脚本
-- 在 Supabase 控制台 → SQL Editor → New query 中粘贴执行一次即可
-- （可重复执行，幂等）
-- ============================================================

create table if not exists public.items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  type        smallint not null check (type in (0, 1)),   -- 0=失物 1=招领
  category    varchar(30) not null default '',
  color       varchar(20) not null default '',
  quantity    int not null default 1 check (quantity >= 1),
  brand       varchar(30) not null default '',
  material    varchar(20) not null default '',
  special_mark text not null default '',
  location    varchar(100) not null default '',
  description text not null default '',
  image_url   text not null default '',
  status      smallint not null default 0 check (status in (0, 1)), -- 0=待匹配 1=已匹配
  embedding   float8[] null,     -- 预留向量列（后续接入 embedding 模型）
  created_at  timestamptz not null default now()
);

create index if not exists items_type_status_idx on public.items (type, status);
create index if not exists items_user_id_idx on public.items (user_id);

create table if not exists public.matches (
  id            uuid primary key default gen_random_uuid(),
  lost_item_id  uuid not null references public.items(id) on delete cascade,
  found_item_id uuid not null references public.items(id) on delete cascade,
  similarity    float not null default 0,
  seen_lost     boolean not null default false,
  seen_found    boolean not null default false,
  created_at    timestamptz not null default now(),
  constraint matches_pair_unique unique (lost_item_id, found_item_id)
);

create index if not exists matches_lost_idx on public.matches (lost_item_id);
create index if not exists matches_found_idx on public.matches (found_item_id);

-- ---------- 表权限（Supabase 默认权限缺失时必须执行，否则 PostgREST 403） ----------

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all functions in schema public to anon, authenticated, service_role;

-- ---------- 行级安全（后端走 service_role 自动绕过，此处为前端直连兜底） ----------

alter table public.items enable row level security;
alter table public.matches enable row level security;

drop policy if exists items_select on public.items;
create policy items_select on public.items
  for select using (true);
drop policy if exists items_insert on public.items;
create policy items_insert on public.items
  for insert with check (auth.uid() = user_id);
drop policy if exists items_update on public.items;
create policy items_update on public.items
  for update using (auth.uid() = user_id);

drop policy if exists matches_select on public.matches;
create policy matches_select on public.matches
  for select using (
    exists (select 1 from public.items i where i.id = lost_item_id and i.user_id = auth.uid())
    or exists (select 1 from public.items i where i.id = found_item_id and i.user_id = auth.uid())
  );
drop policy if exists matches_insert on public.matches;
create policy matches_insert on public.matches
  for insert with check (true);
drop policy if exists matches_update on public.matches;
create policy matches_update on public.matches
  for update using (true);
