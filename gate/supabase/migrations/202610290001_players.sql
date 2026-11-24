begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.players (
 id uuid primary key default gen_random_uuid(),
 appid text not null, ad_id uuid not null, owner_id uuid not null references auth.users(id),
 name text not null check (char_length(name) between 1 and 32),
 avatar text check (avatar in ('clover','pip','rusty','mabel','nova','duchess','zippy')),
 last_score bigint not null default 0 check(last_score >= 0),
 best_score bigint not null default 0 check(best_score >= 0),
 last_score_at timestamptz, last_game_id uuid,
 request_url text, target_url text,
 resolve_lease uuid, resolve_until timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(appid, ad_id)
);
alter table private.players enable row level security;
create table private.score_receipts (
 player_id uuid not null references private.players(id) on delete cascade,
 game_id uuid not null, score bigint not null, completed_at timestamptz not null,
 created_at timestamptz not null default now(), primary key(player_id, game_id)
);
alter table private.score_receipts enable row level security;

-- Only this projection is exposed to clients and Realtime. Never publish private.players.
create table public.leaderboard (
 id uuid primary key references private.players(id) on delete cascade,
 appid text not null, name text not null, avatar text, best_score bigint not null
);
create index leaderboard_ranking on public.leaderboard(appid, best_score desc, id);
alter table public.leaderboard enable row level security;
revoke all on public.leaderboard from anon, authenticated;
grant select on public.leaderboard to authenticated;
create policy leaderboard_read on public.leaderboard for select to authenticated using (true);

create function private.publish_player() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.leaderboard(id, appid, name, avatar, best_score)
 values(new.id,new.appid,new.name,new.avatar,new.best_score)
 on conflict(id) do update set name=excluded.name,avatar=excluded.avatar,best_score=excluded.best_score
 where (leaderboard.name,leaderboard.avatar,leaderboard.best_score) is distinct from (excluded.name,excluded.avatar,excluded.best_score);
 return new;
end $$;
create trigger player_public_projection after insert or update on private.players for each row execute function private.publish_player();

create function private.ensure_player(p_appid text, p_ad_id uuid, p_owner uuid, p_name text, p_avatar text)
returns private.players language plpgsql security definer set search_path = '' as $$
declare v private.players;
begin
 insert into private.players(appid,ad_id,owner_id,name,avatar) values(p_appid,p_ad_id,p_owner,p_name,p_avatar)
 on conflict(appid,ad_id) do nothing;
 select * into v from private.players where appid=p_appid and ad_id=p_ad_id for update;
 if v.owner_id <> p_owner then raise exception 'Identity belongs to a different session' using errcode='42501'; end if;
 return v;
end $$;

create function public.acquire_player(p_appid text,p_ad_id uuid,p_owner uuid,p_name text,p_avatar text,p_request_url text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v private.players; lease uuid := gen_random_uuid();
begin
 v := private.ensure_player(p_appid,p_ad_id,p_owner,p_name,p_avatar);
 if v.target_url is not null and v.target_url <> '' then return jsonb_build_object('target',v.target_url); end if;
 if v.resolve_until > now() then return jsonb_build_object('pending',true); end if;
 update private.players set request_url=p_request_url,resolve_lease=lease,resolve_until=now()+interval '25 seconds',updated_at=now() where id=v.id;
 return jsonb_build_object('lease',lease);
end $$;
create function public.finish_resolution(p_appid text,p_ad_id uuid,p_owner uuid,p_lease uuid,p_target text)
returns text language plpgsql security definer set search_path = '' as $$
declare result text;
begin
 update private.players set target_url=coalesce(nullif(p_target,''),target_url),resolve_lease=null,resolve_until=null,updated_at=now()
 where appid=p_appid and ad_id=p_ad_id and owner_id=p_owner and resolve_lease=p_lease
 returning target_url into result;
 return result;
end $$;
create function public.save_score(p_appid text,p_ad_id uuid,p_owner uuid,p_game_id uuid,p_score bigint,p_completed_at timestamptz,p_avatar text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v private.players; inserted int; receipt private.score_receipts;
begin
 if p_score < 0 or p_score > 2000000000 or p_completed_at > now()+interval '5 minutes' then raise exception 'Invalid score'; end if;
 v := private.ensure_player(p_appid,p_ad_id,p_owner,'Builder '||left(p_ad_id::text,4),p_avatar);
 insert into private.score_receipts(player_id,game_id,score,completed_at) values(v.id,p_game_id,p_score,p_completed_at) on conflict do nothing;
 get diagnostics inserted = row_count;
 if inserted=0 then
   select * into receipt from private.score_receipts where player_id=v.id and game_id=p_game_id;
   if receipt.score <> p_score or receipt.completed_at <> p_completed_at then raise exception 'Conflicting gameId'; end if;
   return jsonb_build_object('accepted',true,'duplicate',true);
 end if;
 update private.players set
 last_score=case when last_score_at is null or (p_completed_at,p_game_id)>(last_score_at,last_game_id) then p_score else last_score end,
 last_game_id=case when last_score_at is null or (p_completed_at,p_game_id)>(last_score_at,last_game_id) then p_game_id else last_game_id end,
 last_score_at=greatest(last_score_at,p_completed_at),best_score=greatest(best_score,p_score),avatar=case when last_score_at is null or (p_completed_at,p_game_id)>(last_score_at,last_game_id) then p_avatar else avatar end,updated_at=now()
 where id=v.id;
 return jsonb_build_object('accepted',true,'duplicate',false);
end $$;
create function public.rename_player(p_appid text,p_ad_id uuid,p_owner uuid,p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v private.players;
begin
 v := private.ensure_player(p_appid,p_ad_id,p_owner,p_name,'clover');
 update private.players set name=p_name,updated_at=now() where id=v.id;
 return jsonb_build_object('updated',true);
end $$;

-- Atomic per-user throttling shared by all Edge instances.
create table private.request_limits(owner_id uuid not null, bucket text not null, minute timestamptz not null, calls int not null, primary key(owner_id,bucket));
alter table private.request_limits enable row level security;
create function public.player_rate_limit(p_owner uuid,p_bucket text,p_limit int) returns boolean
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
 insert into private.request_limits values(p_owner,p_bucket,date_trunc('minute',now()),1)
 on conflict(owner_id,bucket) do update set minute=excluded.minute,calls=case when request_limits.minute=excluded.minute then request_limits.calls+1 else 1 end
 returning calls into n;
 return n<=p_limit;
end $$;
revoke all on all functions in schema private from public,anon,authenticated;
revoke all on function public.acquire_player(text,uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.finish_resolution(text,uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.save_score(text,uuid,uuid,uuid,bigint,timestamptz,text) from public,anon,authenticated;
revoke all on function public.rename_player(text,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.player_rate_limit(uuid,text,int) from public,anon,authenticated;
grant execute on function public.acquire_player(text,uuid,uuid,text,text,text),public.finish_resolution(text,uuid,uuid,uuid,text),public.save_score(text,uuid,uuid,uuid,bigint,timestamptz,text),public.rename_player(text,uuid,uuid,text),public.player_rate_limit(uuid,text,int) to service_role;
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='leaderboard') then
 alter publication supabase_realtime add table public.leaderboard;
 end if;
end $$;
commit;
