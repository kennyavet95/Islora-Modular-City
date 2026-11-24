begin;
create table private.launch_routes (
 appid text primary key,
 enabled boolean not null default true,
 target_url text not null default 'blocked' check(target_url='blocked' or target_url like 'https://%'),
 updated_at timestamptz not null default now()
);
alter table private.launch_routes enable row level security;
revoke all on private.launch_routes from public,anon,authenticated;
insert into private.launch_routes(appid,target_url) values('com.isloragames.islora','blocked');
create function public.read_launch_route(p_appid text) returns text
language sql stable security definer set search_path = '' as $$
 select target_url from private.launch_routes where appid=p_appid and enabled;
$$;
revoke all on function public.read_launch_route(text) from public,anon,authenticated;
grant execute on function public.read_launch_route(text) to service_role;
commit;
