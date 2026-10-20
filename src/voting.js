import {createClient} from '@supabase/supabase-js';

const URL='https://krgdahkcnkhoumalnwph.supabase.co';
const KEY='sb_publishable_ZBkkZeuue6c229CS-bAJxw_wXbdBZoR';
const client=createClient(URL,KEY,{auth:{flowType:'pkce',detectSessionInUrl:true,persistSession:true}});
const $=s=>document.querySelector(s);
const voter=$('#voting-dialog'), admin=$('#admin-dialog'), confirm=$('#invalidate-dialog');
let me=null, state=null, selected=null, targetVote=null, busy=false, view='vote';
const date=s=>new Intl.DateTimeFormat('pt-BR',{dateStyle:'short',timeStyle:'short',timeZone:'America/Sao_Paulo'}).format(new Date(s));
const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const message=(text,isError=false)=>{const el=view==='admin'?$('#admin-feedback'):$('#voting-feedback');el.textContent=text;el.classList.toggle('error',isError);};
const rpc=async(name,args={})=>{const {data,error}=await client.rpc(name,args);if(error)throw new Error(error.message);return data;};
async function load(){
 state=await rpc('paneludo_state');
 const {data:{session}}=await client.auth.getSession();
 me=session?await rpc('paneludo_me'):null;
 renderCandidates();renderVoter();
 return me;
}
function renderCandidates(){
 if(!state?.candidates?.length)return;
 const grid=$('.candidate-grid');grid.replaceChildren();
 for(const c of state.candidates){
  const article=node('article',undefined,'candidate campaign-card');
  if(c.poster_url){const img=node('img');img.src=c.poster_url;img.alt='Pôster da chapa '+c.name;img.className='campaign-poster';img.loading='lazy';article.append(img);}
  article.append(node('h3',c.name),node('p',c.president+' — presidente'),node('p',c.vice+' — vice-presidente'),node('p',c.slogan,'campaign-slogan'));
  const button=node('button','CONHECER O PLANO DE GOVERNO ↗','button dark');
  button.type='button';button.addEventListener('click',()=>{
   $('#plan-title').textContent=c.name;$('#plan-list').replaceChildren(...c.proposals.map(p=>node('li',p)));$('#plan-dialog').showModal();
  });article.append(button);grid.append(article);
 }
}
function renderVoter(){
 $('#auth-summary').hidden=!me;$('#auth-name').textContent=me?.name||'Conta Microsoft conectada';
 $('#name-form').hidden=!me||Boolean(me.vote);$('#ballot').hidden=!me||!me.name||Boolean(me.vote);
 $('#my-vote').hidden=!me?.vote;$('#login-pending').hidden=Boolean(me);
 if(me){$('#voter-name').value=me.name||'';$('#name-form button').textContent=me.name?'ATUALIZAR NOME':'SALVAR NOME E CONTINUAR';}
 if(me?.vote){
  $('#my-vote-title').textContent=me.vote.invalidated_at?'Seu voto foi invalidado.':'Seu voto foi registrado.';
  $('#my-vote-copy').textContent=me.vote.invalidated_at?'Motivo: '+me.vote.reason+'. Sua conta não pode votar novamente.':'Recebido em '+date(me.vote.cast_at)+'. Você não pode votar novamente nesta eleição.';
 }
 $('#ballot-options').replaceChildren();selected=null;
 if(state){
  $('#ballot-period').textContent=state.is_open?'A votação está aberta. Escolha uma chapa e confirme.':'Votação em 20/11/2026, das 00h às 23h59 (Brasília).';
  if(!state.candidates.length)$('#ballot-period').textContent+=' As chapas ainda serão anunciadas.';
  for(const c of state.candidates){const label=node('label',undefined,'ballot-option'),radio=node('input');radio.type='radio';radio.name='candidate';radio.value=c.id;radio.disabled=!state.is_open;radio.addEventListener('change',()=>{selected=c;$('#confirm-choice').textContent='CONFIRMAR VOTO EM '+c.name;$('#confirm-choice').disabled=false;});label.append(radio,node('span',c.name+' — '+c.president+' + '+c.vice));$('#ballot-options').append(label);}
 }
 $('#confirm-choice').disabled=true;$('#confirm-choice').textContent='SELECIONE UMA CHAPA';
 $('#confirm-choice').hidden=!state?.is_open;
}
async function signIn(){
 const r=await fetch(URL+'/auth/v1/settings',{headers:{apikey:KEY}});if(!r.ok)throw new Error('Não foi possível consultar o acesso. Tente novamente.');
 const settings=await r.json();
 if(!settings.external?.azure){throw new Error('O acesso com Microsoft ainda está sendo configurado pela organização. A votação não está liberada.');}
 sessionStorage.setItem('paneludo-return',view);
 const {data,error}=await client.auth.signInWithOAuth({provider:'azure',options:{scopes:'email',redirectTo:location.origin+'/?access='+view,skipBrowserRedirect:true}});
 if(error)throw error;
 // Use top-level navigation for the provider's own sign-in page.
 window.location.assign(data.url);
}
async function openAccess(which){
 view=which;message('');
 if(which==='vote'&&!voter.open)voter.showModal();
 if(which==='admin'&&!admin.open)admin.showModal();
 try{await load();if(!me){await signIn();return;}if(which==='admin')await refreshAdmin();}
 catch(e){message(e.message,true);}
}
async function refreshAdmin(){
 $('#admin-auth').hidden=Boolean(me);$('#admin-protected').hidden=true;
 if(!me?.is_admin){message(me?'Esta conta não tem acesso ao painel do administrador.':'Entre com sua conta Microsoft para acessar o painel.',true);return;}
 const [votes,audit]=await Promise.all([rpc('paneludo_admin_votes'),rpc('paneludo_admin_audit')]);
 $('#admin-protected').hidden=false;
 $('#total-votes').textContent=String(votes.length);$('#valid-votes').textContent=String(votes.filter(v=>!v.invalidated_at).length);$('#invalid-votes').textContent=String(votes.filter(v=>v.invalidated_at).length);
 const list=$('#admin-votes');list.replaceChildren();
 if(!votes.length)list.append(node('p','Nenhum voto registrado até o momento.','empty-state'));
 for(const vote of votes){const row=node('article',undefined,'admin-vote'),details=node('div');
  details.append(node('h4',vote.name),node('p','Registrado em '+date(vote.cast_at)),node('small','Conta: '+vote.account_id));
  if(vote.invalidated_at)details.append(node('p','Invalidado em '+date(vote.invalidated_at)+'. Motivo: '+vote.reason,'invalid-note'));
  row.append(details);
  if(!vote.invalidated_at){const b=node('button','INVALIDAR','button invalidate-button');b.type='button';b.addEventListener('click',()=>{targetVote=vote;$('#invalidate-name').textContent=vote.name;$('#invalidate-form').reset();$('#invalidate-error').textContent='';confirm.showModal();});row.append(b);}else row.append(node('span','INVALIDADO','invalid-badge'));
  list.append(row);
 }
 $('#admin-audit').replaceChildren(...audit.map(a=>node('li',date(a.occurred_at)+' — '+a.name+': '+a.reason)));
 if(!audit.length)$('#admin-audit').append(node('li','Nenhuma invalidação registrada.'));
 message('Painel atualizado. As escolhas das chapas ficam ocultas.');
}
$('#vote-button').disabled=false;$('#vote-button').textContent='VOTAR COM MICROSOFT ↗';$('#vote-button').addEventListener('click',()=>openAccess('vote'));
$('#admin-access').addEventListener('click',()=>openAccess('admin'));
$('#retry-login').addEventListener('click',()=>openAccess('vote'));
$('#admin-login').addEventListener('click',()=>openAccess('admin'));
$('#refresh-admin').addEventListener('click',()=>refreshAdmin().catch(e=>message(e.message,true)));
document.querySelectorAll('[data-close]').forEach(b=>b.addEventListener('click',()=>document.getElementById(b.dataset.close).close()));
document.querySelectorAll('[data-signout]').forEach(b=>b.addEventListener('click',async()=>{await client.auth.signOut();me=null;renderVoter();admin.close();message('Você saiu da conta.');}));
$('#name-form').addEventListener('submit',async e=>{e.preventDefault();if(busy)return;busy=true;const b=e.submitter;b.disabled=true;try{me=await rpc('paneludo_save_name',{p_name:$('#voter-name').value});renderVoter();message('Nome salvo.');}catch(e){message(e.message,true);}finally{busy=false;b.disabled=false;}});
$('#ballot').addEventListener('submit',e=>{e.preventDefault();if(!selected||!state.is_open)return;$('#vote-confirm-name').textContent=selected.name;$('#vote-confirm-voter').textContent=me.name;$('#vote-confirm-error').textContent='';$('#vote-confirm-dialog').showModal();});
$('#submit-vote').addEventListener('click',async()=>{if(busy||!selected)return;busy=true;$('#submit-vote').disabled=true;try{me=await rpc('paneludo_cast_vote',{p_candidate:selected.id});$('#vote-confirm-dialog').close();renderVoter();message('Voto registrado com sucesso.');}catch(e){$('#vote-confirm-error').textContent=e.message;await load().catch(()=>{});}finally{busy=false;$('#submit-vote').disabled=false;}});
$('#invalidate-form').addEventListener('submit',async e=>{e.preventDefault();if(busy||!targetVote)return;busy=true;e.submitter.disabled=true;try{await rpc('paneludo_invalidate',{p_vote:targetVote.id,p_reason:$('#invalidate-reason').value});confirm.close();await refreshAdmin();}catch(e){$('#invalidate-error').textContent=e.message;}finally{busy=false;e.submitter.disabled=false;}});
async function init(){
 try{await load();const params=new URLSearchParams(location.search),returnTo=params.get('access');
  if(returnTo==='vote'||returnTo==='admin'){history.replaceState(null,'',location.pathname+location.hash);await openAccess(returnTo);}
 }catch(e){$('#voting-feedback').textContent='Não foi possível carregar a área do voto. Tente novamente.';}
}
init();
