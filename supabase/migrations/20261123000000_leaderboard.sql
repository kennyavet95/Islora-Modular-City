-- Islora · Top Players backend
--
-- Every function here is called from SupabaseLeaderboardService.swift via
-- POST /rest/v1/rpc/<name>. Tables are locked with RLS and have no policies:
-- the anon key can only reach data through these security-definer RPCs.
--
-- JSON keys are snake_case (the app decodes with convertFromSnakeCase) and
-- timestamps are epoch milliseconds.
--
-- Identity: no accounts. The app generates a UUID + a random device token and
-- proposes a "Builder nnnn" name; register_player keeps the name unique.
-- Mutating calls check the token (stored hashed).

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.lb_players (
  id                     uuid primary key,
  token_hash             text not null,
  builder_name           text not null unique,
  faction                text check (faction in ('coast', 'highland', 'delta')),
  faction_season         text,
  tier                   text not null default 'bronze'
                         check (tier in ('bronze', 'silver', 'gold', 'platinum', 'diamond')),
  stats                  jsonb not null default '{}'::jsonb,
  city                   jsonb not null default '{"buildings": []}'::jsonb,
  -- Denormalized from `stats` so leaderboards can sort on indexed columns.
  level                  int    not null default 1,
  total_experience       bigint not null default 0,
  production_per_minute  bigint not null default 0,
  synergies              int    not null default 0,
  tallest_building       int    not null default 0,
  skybridge_contribution bigint not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists lb_players_total_experience_idx on public.lb_players (total_experience desc);
create index if not exists lb_players_production_idx       on public.lb_players (production_per_minute desc);
create index if not exists lb_players_synergies_idx        on public.lb_players (synergies desc);
create index if not exists lb_players_tallest_idx          on public.lb_players (tallest_building desc);
create index if not exists lb_players_skybridge_idx        on public.lb_players (skybridge_contribution desc);
create index if not exists lb_players_faction_idx          on public.lb_players (faction);

-- One row per player per weekly season. Groups of 30 within a tier.
create table if not exists public.lb_league_members (
  season_id        text   not null,
  player_id        uuid   not null references public.lb_players (id) on delete cascade,
  tier             text   not null,
  group_id         uuid   not null,
  start_experience bigint not null,
  weekly_score     bigint not null default 0,
  final_rank       int,
  primary key (season_id, player_id)
);

create index if not exists lb_league_group_idx on public.lb_league_members (season_id, group_id, weekly_score desc);
create index if not exists lb_league_tier_idx  on public.lb_league_members (season_id, tier, group_id);

create table if not exists public.lb_gifts (
  id          uuid primary key default gen_random_uuid(),
  from_player uuid not null references public.lb_players (id) on delete cascade,
  to_player   uuid not null references public.lb_players (id) on delete cascade,
  kind        text not null check (kind in ('gift', 'thanks')),
  blocks      int  not null,
  sent_day    date not null default (now() at time zone 'utc')::date,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz
);

-- GiftRules.dailySendLimit = 1
create unique index if not exists lb_gifts_one_per_day on public.lb_gifts (from_player, sent_day) where kind = 'gift';
create index if not exists lb_gifts_inbox_idx on public.lb_gifts (to_player) where claimed_at is null;

create table if not exists public.lb_season_results (
  season_id      text primary key,
  winner_faction text,
  closed_at      timestamptz not null default now()
);

alter table public.lb_players        enable row level security;
alter table public.lb_league_members enable row level security;
alter table public.lb_gifts          enable row level security;
alter table public.lb_season_results enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers (not callable by clients)
-- ---------------------------------------------------------------------------

-- Matches SeasonInfo.current() in Swift: ISO week in UTC, e.g. 2026-W48.
create or replace function public.lb_current_season() returns text
language sql stable as $$
  select to_char(now() at time zone 'utc', 'IYYY-"W"IW')
$$;

create or replace function public.lb_season_json() returns json
language sql stable as $$
  select json_build_object(
    'id', public.lb_current_season(),
    'ends_at', (extract(epoch from date_trunc('week', now() at time zone 'utc') + interval '7 days') * 1000)::bigint
  )
$$;

create or replace function public.lb_hash(p_token text) returns text
language sql immutable as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex')
$$;

create or replace function public.lb_auth(p_player_id uuid, p_token text) returns void
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from lb_players where id = p_player_id and token_hash = lb_hash(p_token)) then
    raise exception 'unauthorized';
  end if;
end;
$$;

create or replace function public.lb_entry(
  p_id uuid, p_name text, p_faction text, p_tier text, p_rank bigint, p_score bigint, p_level int, p_me uuid
) returns json
language sql immutable as $$
  select json_build_object(
    'player_id', p_id, 'builder_name', p_name, 'faction', p_faction, 'tier', p_tier,
    'rank', p_rank, 'score', p_score, 'level', p_level, 'is_me', p_id = p_me
  )
$$;

-- Fills in missing keys so PlayerStats always decodes, even before the first submit.
create or replace function public.lb_default_stats() returns jsonb
language sql immutable as $$
  select '{"level": 1, "total_experience": 0, "buildings": 0, "modules": 0, "production_per_minute": 0,
           "synergies": 0, "tallest_building": 0, "skybridge_contribution": 0, "city_orders_completed": 0}'::jsonb
$$;

-- Puts the player in a league group for the current season (once).
create or replace function public.lb_ensure_league_member(p_player_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_season text := lb_current_season();
  v_player lb_players;
  v_group  uuid;
begin
  if exists (select 1 from lb_league_members where season_id = v_season and player_id = p_player_id) then
    return;
  end if;

  select * into v_player from lb_players where id = p_player_id;
  if not found then raise exception 'player_not_found'; end if;

  -- Serialize group assignment per season+tier so groups don't overfill.
  perform pg_advisory_xact_lock(hashtext(v_season || v_player.tier));

  select group_id into v_group
  from lb_league_members
  where season_id = v_season and tier = v_player.tier
  group by group_id
  having count(*) < 30                                   -- LeagueRules.groupSize
  order by count(*) desc
  limit 1;

  insert into lb_league_members (season_id, player_id, tier, group_id, start_experience)
  values (v_season, p_player_id, v_player.tier, coalesce(v_group, gen_random_uuid()), v_player.total_experience)
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.register_player(p_player_id uuid, p_token text, p_builder_name text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_existing lb_players;
  v_name     text := coalesce(nullif(trim(p_builder_name), ''), 'Builder 1000');
begin
  select * into v_existing from lb_players where id = p_player_id;
  if found then
    if v_existing.token_hash <> lb_hash(p_token) then raise exception 'unauthorized'; end if;
    return json_build_object('player_id', v_existing.id, 'builder_name', v_existing.builder_name);
  end if;

  -- Keep the proposed number if free; otherwise roll 4 digits, then 5.
  for i in 1..40 loop
    exit when not exists (select 1 from lb_players where builder_name = v_name);
    v_name := 'Builder ' || case when i < 25 then 1000 + floor(random() * 9000)::int
                                 else 10000 + floor(random() * 90000)::int end;
  end loop;

  insert into lb_players (id, token_hash, builder_name) values (p_player_id, lb_hash(p_token), v_name);
  return json_build_object('player_id', p_player_id, 'builder_name', v_name);
end;
$$;

create or replace function public.submit_stats(p_player_id uuid, p_token text, p_stats jsonb, p_city jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_total bigint := coalesce((p_stats->>'total_experience')::bigint, 0);
begin
  perform lb_auth(p_player_id, p_token);

  update lb_players set
    stats                  = p_stats,
    city                   = coalesce(p_city, '{"buildings": []}'::jsonb),
    level                  = coalesce((p_stats->>'level')::int, 1),
    total_experience       = v_total,
    production_per_minute  = coalesce((p_stats->>'production_per_minute')::bigint, 0),
    synergies              = coalesce((p_stats->>'synergies')::int, 0),
    tallest_building       = coalesce((p_stats->>'tallest_building')::int, 0),
    skybridge_contribution = coalesce((p_stats->>'skybridge_contribution')::bigint, 0),
    updated_at             = now()
  where id = p_player_id;

  perform lb_ensure_league_member(p_player_id);

  update lb_league_members
  set weekly_score = greatest(0, v_total - start_experience)
  where season_id = lb_current_season() and player_id = p_player_id;
end;
$$;

create or replace function public.get_leaderboard(p_player_id uuid, p_category text, p_limit int default 50) returns json
language sql stable security definer set search_path = public, extensions as $$
  with scored as (
    select p.*,
           case p_category
             when 'production' then p.production_per_minute
             when 'synergies'  then p.synergies::bigint
             when 'tallest'    then p.tallest_building::bigint
             when 'skybridge'  then p.skybridge_contribution
             else p.total_experience
           end as score
    from lb_players p
  ),
  ranked as (
    select s.*, row_number() over (order by s.score desc, s.builder_name) as rnk from scored s
  )
  select json_build_object(
    'category', coalesce(nullif(p_category, ''), 'level'),
    'entries', coalesce((
      select json_agg(lb_entry(r.id, r.builder_name, r.faction, r.tier, r.rnk, r.score, r.level, p_player_id) order by r.rnk)
      from ranked r where r.rnk <= least(greatest(p_limit, 1), 100)
    ), '[]'::json),
    'me', (
      select lb_entry(r.id, r.builder_name, r.faction, r.tier, r.rnk, r.score, r.level, p_player_id)
      from ranked r where r.id = p_player_id
    )
  )
$$;

create or replace function public.get_league(p_player_id uuid) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_season text := lb_current_season();
  v_me     lb_league_members;
begin
  perform lb_ensure_league_member(p_player_id);
  select * into v_me from lb_league_members where season_id = v_season and player_id = p_player_id;

  return json_build_object(
    'season', lb_season_json(),
    'tier', v_me.tier,
    'promote_count', 5,                                  -- LeagueRules.promoteCount
    'demote_count', 5,                                   -- LeagueRules.demoteCount
    'entries', coalesce((
      select json_agg(lb_entry(x.id, x.builder_name, x.faction, x.tier, x.rnk, x.weekly_score, x.level, p_player_id) order by x.rnk)
      from (
        select p.id, p.builder_name, p.faction, m.tier, p.level, m.weekly_score,
               row_number() over (order by m.weekly_score desc, p.builder_name) as rnk
        from lb_league_members m
        join lb_players p on p.id = m.player_id
        where m.season_id = v_season and m.group_id = v_me.group_id
      ) x
    ), '[]'::json)
  );
end;
$$;

create or replace function public.get_faction_war(p_player_id uuid) returns json
language sql stable security definer set search_path = public, extensions as $$
  with totals as (
    select f.faction,
           coalesce(sum(m.weekly_score), 0)::bigint as score,
           count(p.id)::int as members
    from (values ('coast'), ('highland'), ('delta')) as f(faction)
    left join lb_players p on p.faction = f.faction
    left join lb_league_members m on m.player_id = p.id and m.season_id = lb_current_season()
    group by f.faction
  )
  select json_build_object(
    'season', lb_season_json(),
    'standings', (
      select json_agg(json_build_object('faction', t.faction, 'score', t.score, 'members', t.members, 'rank', t.rnk) order by t.rnk)
      from (select totals.*, row_number() over (order by score desc, faction) as rnk from totals) t
    ),
    'my_faction', (select faction from lb_players where id = p_player_id),
    'can_switch', coalesce((select faction_season is distinct from lb_current_season() from lb_players where id = p_player_id), true),
    'last_winner', (select winner_faction from lb_season_results order by closed_at desc limit 1)
  )
$$;

create or replace function public.join_faction(p_player_id uuid, p_token text, p_faction text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform lb_auth(p_player_id, p_token);
  if p_faction not in ('coast', 'highland', 'delta') then raise exception 'bad_faction'; end if;
  if exists (select 1 from lb_players where id = p_player_id and faction_season = lb_current_season()) then
    raise exception 'faction_locked';
  end if;
  update lb_players set faction = p_faction, faction_season = lb_current_season() where id = p_player_id;
  return get_faction_war(p_player_id);
end;
$$;

create or replace function public.get_player(p_player_id uuid, p_target_id uuid) returns json
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_target lb_players;
begin
  select * into v_target from lb_players where id = p_target_id;
  if not found then raise exception 'player_not_found'; end if;
  return json_build_object(
    'player_id', v_target.id,
    'builder_name', v_target.builder_name,
    'faction', v_target.faction,
    'tier', v_target.tier,
    'stats', lb_default_stats() || v_target.stats,
    'city', v_target.city,
    'is_me', v_target.id = p_player_id
  );
end;
$$;

create or replace function public.get_gift_status(p_player_id uuid, p_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_today   date := (now() at time zone 'utc')::date;
  v_sent_to uuid;
begin
  perform lb_auth(p_player_id, p_token);
  select to_player into v_sent_to from lb_gifts where from_player = p_player_id and kind = 'gift' and sent_day = v_today;

  return json_build_object(
    'can_send_today', v_sent_to is null,
    'sent_today_to', v_sent_to,
    'inbox', coalesce((
      select json_agg(json_build_object(
        'id', g.id, 'from_player_id', g.from_player, 'from_name', p.builder_name, 'kind', g.kind,
        'blocks', g.blocks, 'created_at', (extract(epoch from g.created_at) * 1000)::bigint
      ) order by g.created_at desc)
      from lb_gifts g join lb_players p on p.id = g.from_player
      where g.to_player = p_player_id and g.claimed_at is null
    ), '[]'::json)
  );
end;
$$;

create or replace function public.send_gift(p_player_id uuid, p_token text, p_target_id uuid) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform lb_auth(p_player_id, p_token);
  if p_target_id = p_player_id then raise exception 'cannot_gift_self'; end if;
  if not exists (select 1 from lb_players where id = p_target_id) then raise exception 'player_not_found'; end if;
  if exists (select 1 from lb_gifts where from_player = p_player_id and kind = 'gift'
             and sent_day = (now() at time zone 'utc')::date) then
    raise exception 'gift_already_sent';
  end if;

  insert into lb_gifts (from_player, to_player, kind, blocks)
  values (p_player_id, p_target_id, 'gift', 2);          -- GiftRules.giftBlocks
  return get_gift_status(p_player_id, p_token);
end;
$$;

create or replace function public.claim_gifts(p_player_id uuid, p_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_count  int;
  v_blocks int;
begin
  perform lb_auth(p_player_id, p_token);

  with claimed as (
    update lb_gifts set claimed_at = now()
    where to_player = p_player_id and claimed_at is null
    returning from_player, kind, blocks
  ),
  thanks as (                                            -- GiftRules.thanksBlocks back to each sender
    insert into lb_gifts (from_player, to_player, kind, blocks)
    select p_player_id, from_player, 'thanks', 1 from claimed where kind = 'gift'
    returning 1
  )
  select count(*), coalesce(sum(blocks), 0) into v_count, v_blocks from claimed;

  return json_build_object('claimed_count', v_count, 'blocks', v_blocks);
end;
$$;

-- ---------------------------------------------------------------------------
-- Weekly season close: promotions, demotions, faction winner.
-- Schedule with pg_cron (Dashboard → Integrations → Cron), Mondays 00:05 UTC:
--
--   select cron.schedule('lb-close-season', '5 0 * * 1',
--     $$ select public.lb_close_season(to_char((now() at time zone 'utc') - interval '1 day', 'IYYY-"W"IW')) $$);
-- ---------------------------------------------------------------------------

create or replace function public.lb_close_season(p_season_id text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tiers text[] := array['bronze', 'silver', 'gold', 'platinum', 'diamond'];
begin
  if exists (select 1 from lb_season_results where season_id = p_season_id) then return; end if;

  update lb_league_members m set final_rank = r.rnk
  from (
    select player_id, row_number() over (partition by group_id order by weekly_score desc) as rnk
    from lb_league_members where season_id = p_season_id
  ) r
  where m.season_id = p_season_id and m.player_id = r.player_id;

  -- Top 5 up, bottom 5 down. Tiny groups (< 10) don't demote, so a group of
  -- a few early players doesn't push everyone down.
  update lb_players p set tier = case
      when x.final_rank <= 5 then v_tiers[least(array_position(v_tiers, x.tier) + 1, 5)]
      when x.size >= 10 and x.final_rank > x.size - 5 then v_tiers[greatest(array_position(v_tiers, x.tier) - 1, 1)]
      else p.tier
    end
  from (
    select player_id, tier, final_rank, count(*) over (partition by group_id) as size
    from lb_league_members where season_id = p_season_id
  ) x
  where p.id = x.player_id;

  insert into lb_season_results (season_id, winner_faction)
  select p_season_id, p.faction
  from lb_league_members m join lb_players p on p.id = m.player_id
  where m.season_id = p_season_id and p.faction is not null
  group by p.faction
  order by sum(m.weekly_score) desc
  limit 1;

  -- No faction played this week: still mark the season closed.
  insert into lb_season_results (season_id) values (p_season_id) on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions: only the RPCs are reachable with the anon key.
-- ---------------------------------------------------------------------------

revoke all on function
  public.lb_current_season(), public.lb_season_json(), public.lb_hash(text), public.lb_auth(uuid, text),
  public.lb_entry(uuid, text, text, text, bigint, bigint, int, uuid), public.lb_default_stats(),
  public.lb_ensure_league_member(uuid), public.lb_close_season(text)
from public, anon, authenticated;

revoke all on function
  public.register_player(uuid, text, text), public.submit_stats(uuid, text, jsonb, jsonb),
  public.get_leaderboard(uuid, text, int), public.get_league(uuid), public.get_faction_war(uuid),
  public.join_faction(uuid, text, text), public.get_player(uuid, uuid), public.get_gift_status(uuid, text),
  public.send_gift(uuid, text, uuid), public.claim_gifts(uuid, text)
from public;

grant execute on function
  public.register_player(uuid, text, text), public.submit_stats(uuid, text, jsonb, jsonb),
  public.get_leaderboard(uuid, text, int), public.get_league(uuid), public.get_faction_war(uuid),
  public.join_faction(uuid, text, text), public.get_player(uuid, uuid), public.get_gift_status(uuid, text),
  public.send_gift(uuid, text, uuid), public.claim_gifts(uuid, text)
to anon, authenticated;
