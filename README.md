# Minezinho Paneludo

Portal eleitoral da comunidade, com identidade visual inspirada em Minecraft.

## Stack

- HTML, CSS e JavaScript, com animações e layout responsivo.
- Supabase Auth (Microsoft, fluxo PKCE) e Postgres.
- Regras de votação e autorização aplicadas no banco por RPCs.
- Publicação estática pelo Sites.

## Desenvolvimento

Requer Node.js e npm.

```sh
npm ci
npm run build
python -m http.server 4173 --directory dist
```

`dist/` contém o site pronto. `src/voting.js` é a fonte da área de votação e administração. Não edite diretamente o bundle `dist/voting.js`.

## Configuração do Supabase

O endereço do projeto e a chave **publicável** usados pelo cliente estão em `src/voting.js`. Uma chave publicável não concede acesso aos votos ou ao painel. Nunca coloque chave `service_role`, segredo OAuth ou senha no frontend.

Em um projeto novo, execute `database/election.sql` uma única vez. Ele cria tabelas em um schema privado com RLS, sem acesso direto pelo cliente, e expõe apenas operações específicas. O schema `paneludo_private` deve continuar fora da lista de schemas expostos na Data API.

Cadastre o e-mail do administrador **privadamente** no SQL Editor, substituindo o valor do exemplo:

```sql
insert into paneludo_private.admin_invites(email)
values (lower('ADMINISTRADOR@EXEMPLO.COM'));
```

O primeiro login Microsoft com esse e-mail verificado vincula a permissão ao UID autenticado. Nenhum administrador é escolhido pelo navegador ou pelo nome informado.

Configure Azure (Microsoft) no Supabase Auth e um aplicativo no Microsoft Entra para contas pessoais. O callback Microsoft é `https://SEU-PROJETO.supabase.co/auth/v1/callback`. Client ID e Client Secret devem ficar no painel do Supabase. Configure Site URL e URLs de retorno `/?access=vote` e `/?access=admin` para o domínio publicado. [Guia oficial](https://supabase.com/docs/guides/auth/social-login/auth-azure).

Sem esse cadastro, o site informa que o acesso Microsoft está em configuração; não simula login e não aceita votos.

## Eleição

- Inscrições: até 24/10/2026 às 23h, pelo grupo da comunidade.
- Votação: 20/11/2026, de 00h até a virada para 21/11, no fuso UTC−3.
- Um voto por conta Microsoft, protegido por restrição única no banco.
- Nome obrigatório; não pode ser alterado depois do voto.
- Painel administrativo sem mostrar a escolha da chapa.
- Invalidação exige motivo, registra histórico e não libera novo voto.
- Apuração bloqueada antes do encerramento.

As chapas reais ainda precisam ser cadastradas em `paneludo_private.candidates`, com presidente, vice, slogan, URL HTTPS do pôster e pelo menos três propostas. Não há candidatos fictícios na produção.

Para atualizar as datas, ajuste o calendário no banco e o contador em `dist/script.js`. O banco é a autoridade para aceitar ou recusar votos.

## Verificação

`database/verify-rollback.sql` testa autorização, prazo, duplicidade, nome após votação, privilégio administrativo e invalidação. Os dados de teste são desfeitos com `ROLLBACK`. Execute em um ambiente de teste vazio, antes de existir participação real.

Os avisos informativos de RLS sem políticas nas tabelas privadas são intencionais: o cliente não pode acessar essas tabelas; usa funções com verificações explícitas de identidade e permissão.

O painel esconde a escolha, mas o banco mantém um vínculo técnico conta–voto necessário à invalidação. Portanto, não se trata de anonimato absoluto perante o administrador do banco.

## Imagens

As imagens de referência foram fornecidas pela comunidade. O projeto não tem vínculo com Mojang ou Microsoft. A publicação do código não concede direitos sobre as marcas e imagens de terceiros.
