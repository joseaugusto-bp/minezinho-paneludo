-- Integration checks. All fixtures, votes and changes are rolled back.
begin;
do $$
declare voter uuid:=gen_random_uuid(); owner_id uuid:=gen_random_uuid(); candidate uuid; payload jsonb; failed boolean;
begin
 insert into paneludo_private.admin_invites(email) values ('test-admin@example.invalid');
 insert into auth.users(id,email,email_confirmed_at) values(voter,'test-'||voter||'@example.invalid',now()),(owner_id,'test-admin@example.invalid',now());
 insert into auth.identities(user_id,provider_id,provider,identity_data)
 values(voter,voter::text,'azure',jsonb_build_object('sub',voter)),(owner_id,owner_id::text,'azure',jsonb_build_object('sub',owner_id));
 perform set_config('request.jwt.claims','{}',true);
 failed:=false;begin perform public.paneludo_me();exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Anonymous identity accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',voter,'role','authenticated')::text,true);
 perform public.paneludo_save_name('Jogador de teste');
 failed:=false;begin perform public.paneludo_admin_votes();exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Non-admin accessed list';end if;
 failed:=false;begin perform public.paneludo_cast_vote(gen_random_uuid());exception when others then
 if sqlerrm='A votação está fora do período oficial.' then failed:=true;else raise;end if;end;
 if not failed then raise exception 'Vote outside dates accepted';end if;
 failed:=false;begin perform public.paneludo_results();exception when others then
 if sqlerrm='A apuração fica disponível após encerrar a votação.' then failed:=true;else raise;end if;end;
 if not failed then raise exception 'Early results exposed';end if;
 update paneludo_private.elections set opens_at=now()-interval '1 hour',closes_at=now()+interval '1 hour' where id='presidencial-2026';
 insert into paneludo_private.candidates(election_id,name,president,vice,slogan,proposals)
 values('presidencial-2026','TESTE ROLLBACK','Presidente teste','Vice teste','Não publicar',array['Proposta teste 1','Proposta teste 2','Proposta teste 3']) returning id into candidate;
 perform public.paneludo_cast_vote(candidate);
 failed:=false;begin perform public.paneludo_cast_vote(candidate);exception when others then
 if sqlerrm='Esta conta já votou nesta eleição.' then failed:=true;else raise;end if;end;
 if not failed then raise exception 'Duplicate vote accepted';end if;
 failed:=false;begin perform public.paneludo_save_name('Outro nome');exception when others then
 if sqlerrm='O nome fica registrado após o voto.' then failed:=true;else raise;end if;end;
 if not failed then raise exception 'Name changed after vote';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 payload:=public.paneludo_me();if not (payload->>'is_admin')::boolean then raise exception 'Admin bootstrap failed';end if;
 payload:=public.paneludo_admin_votes();
 if payload->0 ? 'candidate_id' or payload->0 ? 'candidate' then raise exception 'Choice exposed to admin list';end if;
 perform public.paneludo_invalidate((payload->0->>'id')::uuid,'Conta de teste não pertence ao servidor');
 if (select count(*) from paneludo_private.audit)<>1 then raise exception 'Missing audit';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',voter,'role','authenticated')::text,true);
 failed:=false;begin perform public.paneludo_cast_vote(candidate);exception when others then
 if sqlerrm='Esta conta já votou nesta eleição.' then failed:=true;else raise;end if;end;
 if not failed then raise exception 'Invalidated account voted again';end if;
end $$;
rollback;
select jsonb_build_object('checks','passed','real_votes',(select count(*) from paneludo_private.votes),'real_admins',(select count(*) from paneludo_private.admins),'real_candidates',(select count(*) from paneludo_private.candidates)) as verification;

