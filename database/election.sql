begin;
create schema if not exists paneludo_private;
revoke all on schema paneludo_private from public;
grant usage on schema paneludo_private to anon, authenticated;

create table paneludo_private.elections (
 id text primary key, title text not null,
 opens_at timestamptz not null, closes_at timestamptz not null,
 check(closes_at > opens_at)
);
insert into paneludo_private.elections values
 ('presidencial-2026','Eleições presidenciais 2026','2026-11-20T00:00:00-03:00','2026-11-21T00:00:00-03:00');
create table paneludo_private.candidates (
 id uuid primary key default gen_random_uuid(), election_id text not null references paneludo_private.elections,
 name text not null, president text not null, vice text not null, slogan text not null,
 poster_url text check(poster_url is null or poster_url ~ '^https://'),
 proposals text[] not null check(cardinality(proposals)>=3), active boolean not null default true,
 unique(election_id,id)
);
create table paneludo_private.profiles (
 user_id uuid primary key references auth.users(id),
 display_name text not null check(char_length(btrim(display_name)) between 2 and 80),
 created_at timestamptz not null default now()
);
create table paneludo_private.admin_invites (
 email text primary key, claimed_by uuid unique references auth.users(id)
);
-- Provision the verified administrator email privately through the SQL editor.
create table paneludo_private.admins (
 user_id uuid primary key references auth.users(id), created_at timestamptz not null default now()
);
create table paneludo_private.votes (
 id uuid primary key default gen_random_uuid(), election_id text not null references paneludo_private.elections,
 user_id uuid not null references paneludo_private.profiles(user_id),
 candidate_id uuid not null, name_snapshot text not null,
 cast_at timestamptz not null default now(),
 invalidated_at timestamptz, invalidated_by uuid references auth.users(id), reason text,
 foreign key(election_id,candidate_id) references paneludo_private.candidates(election_id,id),
 unique(election_id,user_id),
 check ((invalidated_at is null and invalidated_by is null and reason is null) or
 (invalidated_at is not null and invalidated_by is not null and char_length(btrim(reason)) between 5 and 500))
);
create index votes_election_time on paneludo_private.votes(election_id,cast_at desc);
create table paneludo_private.audit (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references auth.users(id),
 vote_id uuid not null references paneludo_private.votes(id), action text not null,
 reason text not null, occurred_at timestamptz not null default now()
);
create index audit_vote on paneludo_private.audit(vote_id);
alter table paneludo_private.elections enable row level security;
alter table paneludo_private.candidates enable row level security;
alter table paneludo_private.profiles enable row level security;
alter table paneludo_private.admin_invites enable row level security;
alter table paneludo_private.admins enable row level security;
alter table paneludo_private.votes enable row level security;
alter table paneludo_private.audit enable row level security;
revoke all on all tables in schema paneludo_private from public, anon, authenticated;

-- Privileged helpers remain in a non-exposed schema. Every protected operation
-- validates the signed-in Microsoft identity and admin UID inside the database.
create function paneludo_private.require_user() returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid := auth.uid();
begin
 if actor is null or not exists(select 1 from auth.users u join auth.identities i on i.user_id=u.id
   where u.id=actor and i.provider='azure' and u.deleted_at is null and (u.banned_until is null or u.banned_until<now())) then
  raise exception 'Entre com sua conta Microsoft.' using errcode='42501';
 end if;
 return actor;
end $$;
create function paneludo_private.require_admin() returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_user();
begin
 if not exists(select 1 from paneludo_private.admins where user_id=actor) then
  raise exception 'Acesso restrito ao administrador.' using errcode='42501';
 end if;
 return actor;
end $$;
create function paneludo_private.state() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',e.id,'opens_at',e.opens_at,'closes_at',e.closes_at,'server_time',now(),
 'is_open',now()>=e.opens_at and now()<e.closes_at,
 'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'president',c.president,'vice',c.vice,
 'slogan',c.slogan,'poster_url',c.poster_url,'proposals',c.proposals) order by c.name)
 from paneludo_private.candidates c where c.election_id=e.id and c.active),'[]'::jsonb))
 from paneludo_private.elections e where id='presidencial-2026'
$$;
create function paneludo_private.me() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_user(); result jsonb;
begin
 -- The email allowlist can bind an admin only once, using the server's verified
 -- email and a Microsoft identity. All later permissions use the immutable UID.
 with claimed as (
  update paneludo_private.admin_invites a set claimed_by=actor from auth.users u
  where u.id=actor and u.email_confirmed_at is not null and lower(u.email)=a.email
   and (a.claimed_by is null or a.claimed_by=actor) returning a.claimed_by
 ) insert into paneludo_private.admins(user_id) select claimed_by from claimed on conflict do nothing;
 select jsonb_build_object('id',actor,'name',(select display_name from paneludo_private.profiles where user_id=actor),
 'is_admin',exists(select 1 from paneludo_private.admins where user_id=actor),
 'vote',(select jsonb_build_object('cast_at',v.cast_at,'invalidated_at',v.invalidated_at,'reason',v.reason)
 from paneludo_private.votes v where v.user_id=actor and v.election_id='presidencial-2026')) into result;
 return result;
end $$;
create function paneludo_private.save_name(p_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_user(); clean text:=btrim(regexp_replace(p_name,'\s+',' ','g'));
begin
 if clean is null or char_length(clean) not between 2 and 80 or clean ~ '[[:cntrl:]]' then
  raise exception 'Informe seu nome, com 2 a 80 caracteres.';
 end if;
 -- Serialize profile changes and vote submission for this account.
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 if exists(select 1 from paneludo_private.votes where user_id=actor and election_id='presidencial-2026') then
  raise exception 'O nome fica registrado após o voto.';
 end if;
 insert into paneludo_private.profiles(user_id,display_name) values(actor,clean)
 on conflict(user_id) do update set display_name=excluded.display_name;
 return paneludo_private.me();
end $$;
create function paneludo_private.cast_vote(p_candidate uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_user(); voter_name text; election paneludo_private.elections;
begin
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 select * into election from paneludo_private.elections where id='presidencial-2026';
 if now()<election.opens_at or now()>=election.closes_at then raise exception 'A votação está fora do período oficial.'; end if;
 select display_name into voter_name from paneludo_private.profiles where user_id=actor;
 if voter_name is null then raise exception 'Informe seu nome antes de votar.'; end if;
 if not exists(select 1 from paneludo_private.candidates where id=p_candidate and election_id=election.id and active) then
  raise exception 'Chapa indisponível.';
 end if;
 begin
  insert into paneludo_private.votes(election_id,user_id,candidate_id,name_snapshot) values(election.id,actor,p_candidate,voter_name);
 exception when unique_violation then raise exception 'Esta conta já votou nesta eleição.'; end;
 return paneludo_private.me();
end $$;
create function paneludo_private.admin_votes() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_admin(); result jsonb;
begin
 select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'name',v.name_snapshot,'account_id',v.user_id,
 'cast_at',v.cast_at,'invalidated_at',v.invalidated_at,'reason',v.reason) order by v.cast_at desc),'[]'::jsonb)
 into result from paneludo_private.votes v where election_id='presidencial-2026';
 return result;
end $$;
create function paneludo_private.invalidate(p_vote uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_admin(); clean text:=btrim(p_reason);
begin
 if clean is null or char_length(clean) not between 5 and 500 then raise exception 'Informe um motivo com 5 a 500 caracteres.'; end if;
 perform 1 from paneludo_private.votes where id=p_vote and election_id='presidencial-2026' and invalidated_at is null for update;
 if not found then raise exception 'Voto não encontrado ou já invalidado.'; end if;
 update paneludo_private.votes set invalidated_at=now(),invalidated_by=actor,reason=clean where id=p_vote;
 insert into paneludo_private.audit(actor_id,vote_id,action,reason) values(actor,p_vote,'invalidate',clean);
end $$;
create function paneludo_private.admin_audit() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=paneludo_private.require_admin(); result jsonb;
begin
 select coalesce(jsonb_agg(jsonb_build_object('name',v.name_snapshot,'action',a.action,'reason',a.reason,
 'occurred_at',a.occurred_at) order by a.occurred_at desc),'[]'::jsonb) into result
 from paneludo_private.audit a join paneludo_private.votes v on v.id=a.vote_id;
 return result;
end $$;
create function paneludo_private.results() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if now()<(select closes_at from paneludo_private.elections where id='presidencial-2026') then raise exception 'A apuração fica disponível após encerrar a votação.'; end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.votes desc,r.name),'[]'::jsonb) into result from (
 select c.name,count(v.id) as votes from paneludo_private.candidates c
 left join paneludo_private.votes v on v.candidate_id=c.id and v.invalidated_at is null
 where c.election_id='presidencial-2026' group by c.id,c.name) r;
 return result;
end $$;

create function public.paneludo_state() returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.state()$$;
create function public.paneludo_me() returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.me()$$;
create function public.paneludo_save_name(p_name text) returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.save_name(p_name)$$;
create function public.paneludo_cast_vote(p_candidate uuid) returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.cast_vote(p_candidate)$$;
create function public.paneludo_admin_votes() returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.admin_votes()$$;
create function public.paneludo_invalidate(p_vote uuid,p_reason text) returns void language sql security invoker set search_path='' as $$select paneludo_private.invalidate(p_vote,p_reason)$$;
create function public.paneludo_admin_audit() returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.admin_audit()$$;
create function public.paneludo_results() returns jsonb language sql security invoker set search_path='' as $$select paneludo_private.results()$$;
revoke all on all functions in schema paneludo_private from public,anon,authenticated;
revoke all on function public.paneludo_state(),public.paneludo_me(),public.paneludo_save_name(text),
 public.paneludo_cast_vote(uuid),public.paneludo_admin_votes(),public.paneludo_invalidate(uuid,text),
 public.paneludo_admin_audit(),public.paneludo_results() from public,anon,authenticated;
grant execute on function paneludo_private.state(),paneludo_private.results(),public.paneludo_state(),public.paneludo_results() to anon,authenticated;
grant execute on function paneludo_private.me(),paneludo_private.save_name(text),paneludo_private.cast_vote(uuid),
 paneludo_private.admin_votes(),paneludo_private.invalidate(uuid,text),paneludo_private.admin_audit(),
 public.paneludo_me(),public.paneludo_save_name(text),public.paneludo_cast_vote(uuid),public.paneludo_admin_votes(),
 public.paneludo_invalidate(uuid,text),public.paneludo_admin_audit() to authenticated;
notify pgrst,'reload schema';
commit;

