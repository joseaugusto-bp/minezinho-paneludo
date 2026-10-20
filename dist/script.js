// Calendário oficial. O calendário não habilita a urna sem o sistema de votos.
const electionConfig = {
  registrationEndsAt: '2026-10-24T23:00:00-03:00',
  startsAt: '2026-11-20T00:00:00-03:00',
  endsAt: '2026-11-21T00:00:00-03:00'
};
function getElectionState(now = Date.now()) {
  const registrationOpen = now <= Date.parse(electionConfig.registrationEndsAt);
  const start = Date.parse(electionConfig.startsAt), end = Date.parse(electionConfig.endsAt);
  const phase = now < start ? 'before' : now < end ? 'voting-day' : 'ended';
  const target = phase === 'before' ? start : end;
  const remaining = phase === 'ended' ? 0 : Math.max(0, Math.floor((target - now) / 1000));
  return {registrationOpen, phase, values: [Math.floor(remaining/86400), Math.floor(remaining/3600)%24, Math.floor(remaining/60)%60, remaining%60]};
}
const menu = document.querySelector('.menu'), nav = document.querySelector('nav');
menu.addEventListener('click', () => {const open = menu.getAttribute('aria-expanded') !== 'true'; menu.setAttribute('aria-expanded', String(open));menu.setAttribute('aria-label',open?'Fechar menu':'Abrir menu');nav.classList.toggle('open',open);});
nav.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{nav.classList.remove('open');menu.setAttribute('aria-expanded','false');menu.setAttribute('aria-label','Abrir menu');}));
function tick(){
  const {registrationOpen,phase,values} = getElectionState();
  ['days','hours','minutes','seconds'].forEach((id,i)=>document.getElementById(id).textContent=String(values[i]).padStart(2,'0'));
  document.querySelector('#registration-status').textContent=registrationOpen?'INSCRIÇÕES ABERTAS':'INSCRIÇÕES ENCERRADAS';
  document.querySelector('#registration-deadline-label').textContent=registrationOpen?'PRAZO PARA INSCRIÇÃO':'PRAZO DE INSCRIÇÃO ENCERRADO';
  const captions={before:'FALTA PARA O DIA DA VOTAÇÃO','voting-day':'TEMPO RESTANTE NO DIA DA VOTAÇÃO',ended:'DIA DA VOTAÇÃO ENCERRADO'};
  document.querySelector('#countdown-caption').textContent=captions[phase];
  document.querySelector('.countdown').setAttribute('aria-label',captions[phase]);
  
  if(phase==='voting-day'){
    document.querySelector('#vote-heading').textContent='Hoje é dia de votar.';
    document.querySelector('#vote-description').textContent='Entre com Microsoft, informe seu nome e escolha sua chapa. A votação termina às 23h59, no horário de Brasília.';
    
  }else if(phase==='ended'){
    document.querySelector('#vote-heading').textContent='Acompanhe a apuração.';
    document.querySelector('#vote-description').textContent='O dia de votação terminou. A divulgação do resultado será anunciada pela organização.';
    
  }
}
 tick();setInterval(tick,1000);
if('IntersectionObserver' in window){const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target);}}),{threshold:.08});document.querySelectorAll('.section-heading,.candidate,.faq-grid,.world-copy').forEach(el=>{el.classList.add('reveal');observer.observe(el);});}

