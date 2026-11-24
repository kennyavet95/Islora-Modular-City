-- Keep ownership of the resolution while the checker and final database write run.
create or replace function public.acquire_player(
 p_appid text, p_ad_id uuid, p_owner uuid, p_name text, p_avatar text, p_request_url text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v private.players; lease uuid := gen_random_uuid();
begin
 v := private.ensure_player(p_appid,p_ad_id,p_owner,p_name,p_avatar);
 if v.target_url is not null and v.target_url <> '' then return jsonb_build_object('target',v.target_url); end if;
 if v.resolve_until > now() then return jsonb_build_object('pending',true); end if;
 update private.players set request_url=p_request_url,resolve_lease=lease,
  resolve_until=now()+interval '65 seconds',updated_at=now() where id=v.id;
 return jsonb_build_object('lease',lease);
end $$;
