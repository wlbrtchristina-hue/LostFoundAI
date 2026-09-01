-- ============================================================
-- 聊天功能：messages 消息表
-- 设计：一个匹配（matches）即一个会话——每个匹配恰好有失物方+招领方
-- 两个参与者，无需单独的 conversations 表。
-- 消息直写 Supabase（Flutter 客户端 + RLS 鉴权），配合 Realtime 实时推送，
-- FastAPI 后端无需任何改动。
-- 在 Supabase 控制台 → SQL Editor → New query 中粘贴执行一次即可
-- （可重复执行，幂等）
-- ============================================================

create table if not exists public.messages (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null references public.matches(id) on delete cascade,
  sender_id  uuid not null,
  content    text not null check (length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists messages_match_idx on public.messages (match_id, created_at);

-- ---------- 权限（Supabase 默认权限缺失时必须执行，否则 PostgREST 403） ----------

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;

-- ---------- 行级安全：只有匹配的双方能读写自己的会话 ----------

-- 参与者判断：用户是该匹配中失物或招领物品的发布者
create or replace function public.is_match_participant(mid uuid, uid uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from public.matches m
    join public.items i on i.id in (m.lost_item_id, m.found_item_id)
    where m.id = mid and i.user_id = uid
  );
$$;

alter table public.messages enable row level security;

drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select using (is_match_participant(match_id, auth.uid()));

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert with check (
    sender_id = auth.uid() and is_match_participant(match_id, auth.uid())
  );

-- ---------- Realtime：新消息实时推送给订阅客户端（RLS 同时生效） ----------

do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;
