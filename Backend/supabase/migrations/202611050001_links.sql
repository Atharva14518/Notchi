-- Supabase Auth owns identities and session/JWT issuance. Only this backend's
-- service_role can call the RPCs; clients cannot promote their own paid tier.
create table public.link_accounts (
  id uuid primary key references auth.users(id) on delete cascade,
  tier text not null default 'free' check (tier in ('free','paid'))
);
create table public.link_uploads (
  id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
  filename text not null, size bigint not null check(size > 0), mime text not null,
  staging_key text not null unique, object_key text not null unique,
  state text not null default 'pending' check(state in ('pending','completing','complete','cancelled')),
  pending_until timestamptz not null, created_at timestamptz not null default now()
);
create table public.link_shares (
  id uuid primary key default gen_random_uuid(), upload_id uuid not null unique references public.link_uploads(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  slug text not null unique check(slug ~ '^[A-Za-z0-9_-]{24}$'),
  filename text not null, size bigint not null, object_key text not null,
  expires_at timestamptz not null, password_hash text, download_limit integer check(download_limit between 1 and 10000),
  download_count integer not null default 0, exhausted_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now()
);
create index on public.link_uploads(owner_id, pending_until);
create index on public.link_shares(owner_id, expires_at);
create table public.link_reports (
  id uuid primary key default gen_random_uuid(), slug text not null, reporter_hash text not null,
  reason text not null check(reason in ('malware','phishing','copyright','other')), created_at timestamptz not null default now(),
  unique(slug,reporter_hash)
);
-- Retain reports for operator review independently of expired file records.
alter table public.link_accounts enable row level security;
alter table public.link_uploads enable row level security;
alter table public.link_shares enable row level security;
alter table public.link_reports enable row level security;
revoke all on public.link_accounts,public.link_uploads,public.link_shares,public.link_reports from public,anon,authenticated;
grant all on public.link_accounts,public.link_uploads,public.link_shares,public.link_reports to service_role;

create function public.link_limits(p_owner uuid,p_paid_bytes bigint,p_paid_links integer) returns jsonb
language sql security definer set search_path=public as $$
  select jsonb_build_object('maxBytes',case when exists(select 1 from link_accounts where id=p_owner and tier='paid') then p_paid_bytes else 100000000 end,
    'maxActiveLinks',case when exists(select 1 from link_accounts where id=p_owner and tier='paid') then p_paid_links else 5 end,
    'activeLinks',(select count(*) from link_uploads u left join link_shares s on s.upload_id=u.id where u.owner_id=p_owner and
      ((u.state in ('pending','completing') and u.pending_until>now()) or
       (s.expires_at>now() and s.revoked_at is null and (s.download_limit is null or s.download_count<s.download_limit)))))
$$;
create function public.link_reserve_upload(p_owner uuid,p_id uuid,p_filename text,p_size bigint,p_mime text,p_until timestamptz,p_paid_bytes bigint,p_paid_links integer) returns jsonb
language plpgsql security definer set search_path=public as $$
declare lim jsonb; item link_uploads;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text,0));
  lim := link_limits(p_owner,p_paid_bytes,p_paid_links);
  if p_size>(lim->>'maxBytes')::bigint then raise exception 'too_large'; end if;
  if (lim->>'activeLinks')::integer >= (lim->>'maxActiveLinks')::integer then raise exception 'quota_exceeded'; end if;
  if p_until<=now() or p_until>now()+interval '31 minutes' then raise exception 'upload_expired'; end if;
  insert into link_uploads(id,owner_id,filename,size,mime,staging_key,object_key,pending_until)
    values(p_id,p_owner,p_filename,p_size,p_mime,'staging/'||p_owner||'/'||p_id,'files/'||p_owner||'/'||p_id,p_until) returning * into item;
  return to_jsonb(item);
end $$;
create function public.link_claim_upload(p_owner uuid,p_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare item link_uploads;
begin
  select * into item from link_uploads where id=p_id and owner_id=p_owner for update;
  if not found or item.state='cancelled' then raise exception 'upload_missing'; end if;
  if item.pending_until<=now() then raise exception 'upload_expired'; end if;
  if item.state='complete' then raise exception 'already_complete'; end if;
  if item.state='completing' then raise exception 'upload_busy'; end if;
  update link_uploads set state='completing' where id=p_id returning * into item;
  return to_jsonb(item);
end $$;
create function public.link_release_upload(p_owner uuid,p_id uuid) returns void
language sql security definer set search_path=public as $$
 update link_uploads set state='pending' where id=p_id and owner_id=p_owner and state='completing'
$$;
create function public.link_complete_upload(p_owner uuid,p_id uuid,p_slug text,p_expires timestamptz,p_hash text,p_limit integer) returns jsonb
language plpgsql security definer set search_path=public as $$
declare item link_uploads; result link_shares;
begin
 select * into item from link_uploads where id=p_id and owner_id=p_owner for update;
 if not found or item.state<>'completing' or item.pending_until<=now() then raise exception 'upload_expired'; end if;
 if p_expires<=now() or p_expires>now()+interval '7 days 1 minute' then raise exception 'invalid_share'; end if;
 insert into link_shares(upload_id,owner_id,slug,filename,size,object_key,expires_at,password_hash,download_limit)
   values(item.id,p_owner,p_slug,item.filename,item.size,item.object_key,p_expires,p_hash,p_limit) returning * into result;
 update link_uploads set state='complete' where id=p_id;
 return to_jsonb(result);
end $$;
create function public.link_owned_share(p_owner uuid,p_upload uuid) returns jsonb
language sql security definer set search_path=public as $$ select to_jsonb(s) from link_shares s where s.upload_id=p_upload and s.owner_id=p_owner $$;
create function public.link_get_share(p_slug text) returns jsonb
language sql security definer set search_path=public as $$ select to_jsonb(s) from link_shares s where s.slug=p_slug $$;
create function public.link_claim_download(p_slug text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare result link_shares;
begin
 -- Conditional UPDATE locks and rechecks the limit; concurrent last downloads
 -- cannot both consume the same remaining allowance.
 update link_shares set download_count=download_count+1,
   exhausted_at=case when download_limit is not null and download_count+1>=download_limit then now() else exhausted_at end
 where slug=p_slug and revoked_at is null and expires_at>now() and (download_limit is null or download_count<download_limit)
 returning * into result;
 if not found then return null; end if;
 return to_jsonb(result);
end $$;
create function public.link_list_shares(p_owner uuid) returns jsonb
language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at desc),'[]'::jsonb) from link_shares s where s.owner_id=p_owner
$$;
create function public.link_revoke(p_owner uuid,p_id uuid) returns void
language sql security definer set search_path=public as $$ update link_shares set revoked_at=coalesce(revoked_at,now()) where id=p_id and owner_id=p_owner $$;
create function public.link_report(p_slug text,p_reporter text,p_reason text) returns void
language sql security definer set search_path=public as $$
 insert into link_reports(slug,reporter_hash,reason) select p_slug,p_reporter,p_reason where exists(select 1 from link_shares where slug=p_slug) on conflict(slug,reporter_hash) do nothing
$$;
create function public.link_expired_uploads() returns jsonb
language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from (
  select u.* from link_uploads u left join link_shares s on s.upload_id=u.id where
    (u.state<>'complete' and u.pending_until<=now()) or s.expires_at<=now() or s.revoked_at is not null or s.exhausted_at<=now()-interval '2 minutes'
  order by u.created_at limit 100
 ) t
$$;
create function public.link_delete_expired(p_id uuid) returns void
language sql security definer set search_path=public as $$
 delete from link_uploads u where u.id=p_id and
 ((u.state<>'complete' and u.pending_until<=now()) or exists(select 1 from link_shares s where s.upload_id=u.id and
 (s.expires_at<=now() or s.revoked_at is not null or s.exhausted_at<=now()-interval '2 minutes')))
$$;
-- RPC access is server-only. Supabase grants function EXECUTE to public by
-- default, so explicitly revoke it for every function in this migration.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'link_%'
 loop execute format('revoke all on function %s from public,anon,authenticated',f.signature);
      execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
create function public.link_pending_upload(p_owner uuid,p_id uuid) returns jsonb
language sql security definer set search_path=public as $$ select to_jsonb(u) from link_uploads u where u.id=p_id and u.owner_id=p_owner and u.state='pending' and u.pending_until>now()+interval '5 seconds' $$;
create function public.link_cancel_upload(p_owner uuid,p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 perform 1 from link_uploads where id=p_id and owner_id=p_owner for update;
 update link_shares set revoked_at=coalesce(revoked_at,now()) where upload_id=p_id and owner_id=p_owner;
 update link_uploads set state='cancelled',pending_until=now()+interval '2 minutes' where id=p_id and owner_id=p_owner and state<>'complete';
end $$;
revoke all on function public.link_pending_upload(uuid,uuid),public.link_cancel_upload(uuid,uuid) from public,anon,authenticated;
grant execute on function public.link_pending_upload(uuid,uuid),public.link_cancel_upload(uuid,uuid) to service_role;
-- Downloads redirect to one-use signed Worker tickets. Unlike a reusable R2
-- GET capability, replaying a ticket cannot bypass a one-download limit.
create table public.link_download_tickets (
 id uuid primary key, share_id uuid not null references public.link_shares(id) on delete cascade,
 expires_at timestamptz not null, used_at timestamptz
);
alter table public.link_download_tickets enable row level security;
revoke all on public.link_download_tickets from public,anon,authenticated;
grant all on public.link_download_tickets to service_role;
create function public.link_issue_ticket(p_slug text,p_id uuid,p_expires timestamptz) returns boolean
language plpgsql security definer set search_path=public as $$
begin
 delete from link_download_tickets where expires_at<now()-interval '1 hour';
 insert into link_download_tickets(id,share_id,expires_at) select p_id,s.id,least(p_expires,s.expires_at) from link_shares s
 where s.slug=p_slug and s.revoked_at is null and s.expires_at>now() and (s.download_limit is null or s.download_count<s.download_limit);
 return found;
end $$;
create function public.link_consume_ticket(p_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare ticket link_download_tickets; result link_shares;
begin
 update link_download_tickets set used_at=now() where id=p_id and used_at is null and expires_at>now() returning * into ticket;
 if not found then return null; end if;
 update link_shares set download_count=download_count+1,
  exhausted_at=case when download_limit is not null and download_count+1>=download_limit then now() else exhausted_at end
 where id=ticket.share_id and revoked_at is null and expires_at>now() and (download_limit is null or download_count<download_limit) returning * into result;
 if not found then return null; end if;
 return to_jsonb(result);
end $$;
revoke all on function public.link_issue_ticket(text,uuid,timestamptz),public.link_consume_ticket(uuid) from public,anon,authenticated;
grant execute on function public.link_issue_ticket(text,uuid,timestamptz),public.link_consume_ticket(uuid) to service_role;
create or replace function public.link_expired_uploads() returns jsonb
language sql security definer set search_path=public as $$
 with pruned_tickets as (delete from link_download_tickets where expires_at<=now()),
      pruned_reports as (delete from link_reports where created_at<now()-interval '30 days')
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from (
  select u.* from link_uploads u left join link_shares s on s.upload_id=u.id where
    (u.state<>'complete' and u.pending_until<=now()) or s.expires_at<=now() or s.revoked_at is not null or s.exhausted_at<=now()-interval '2 minutes'
  order by u.created_at limit 100
 ) t
$$;
