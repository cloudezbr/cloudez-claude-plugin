---
description: Converte um site que já existe na Cloudez (WordPress, html ou outro tipo) para o tipo Claude, guardando os arquivos atuais num backup no servidor, e publica o projeto local nele. Use quando o site do .cloudez.yaml não for do tipo Claude e o usuário quiser fazer deploy nele.
argument-hint: "[domain] [environment]"
allowed-tools: mcp__cloudez__cloudez_auth_status, mcp__cloudez__cloudez_panel_info, mcp__cloudez__cloudez_signup, mcp__cloudez__cloudez_resend_phone_code, mcp__cloudez__cloudez_confirm_phone, mcp__cloudez__cloudez_get_site, mcp__cloudez__cloudez_find_compose, mcp__cloudez__cloudez_list_local_ssh_keys, mcp__cloudez__cloudez_authorize_ssh_key, mcp__cloudez__cloudez_convert_site, mcp__cloudez__cloudez_configure_site, Bash(cloudez-setup:*), Read, AskUserQuestion
---

Argumentos recebidos: `$ARGUMENTS` — o domínio e o environment, os dois opcionais.

Converter troca o que a Cloudez provisiona para o site: ele deixa de ser servido
como WordPress (ou html) e passa a encaminhar para o container deste plugin. **O
site antigo sai do ar na conversão e só volta com o deploy**, então este comando
prepara tudo antes, converte, e emenda no deploy na mesma conversa.

## 0. Autenticação, antes de qualquer coisa

Chame `cloudez_auth_status`. Com `authenticated: false`, **pare** e conduza o
`/cloudez:login`; volte aqui depois que ele passar.

## 1. Qual site

**Com `.cloudez.yaml`**, escolha o environment como no passo 1 do
`commands/deploy.md` (o argumento, se veio; senão, pergunte entre os que existem),
e use o `domain` dele.

**Sem `.cloudez.yaml`**, use o domínio do argumento — ou pergunte, se não veio — e
confirme o site com o passo 2 abaixo antes de qualquer coisa. Só com o site
confirmado, escolha o environment e crie a config como nos passos 3 e 4 do
`commands/setup.md`, lendo o arquivo em vez de reconstruir o procedimento.

## 2. Confirmar o site e o tipo

```
cloudez_get_site(domain: "<domain>")
```

**`match` diferente de `"exact"`** — **pare.** Se o domínio veio da config, ela
aponta para um site que não está na conta, e isso se corrige no `.cloudez.yaml`.
Se veio do usuário, o site não existe com esse domínio, e não há o que converter:
ofereça o `/cloudez:setup <domain>`, que mostra os parecidos e cria o site.

**`ssh_unavailable` dizendo que o SSH não está liberado** — **pare antes de
converter.** O backup dos arquivos é feito por SSH; sem ele, a conversão tiraria o
site do ar sem guardar o que estava lá. Diga que o acesso SSH precisa ser
habilitado no painel da Cloudez.

Pelo `stack`:

- **`claude` com `app_root_path` valendo `claude/current`, ou `container_docker`**
  — não há o que converter. Diga que o site já está pronto para receber deploy e
  ofereça o `/cloudez:deploy`. Fim.
- **`claude` sem esse `app_root_path`** — uma conversão anterior não chegou ao fim.
  Siga normalmente: a tool do passo 6 percebe e só termina o que faltou.
- **qualquer outro** (`wordpress`, `html`, ...) — é o caso deste comando. Siga.

## 3. O projeto tem Compose?

```
cloudez_find_compose(directory: "<diretório do projeto>")
```

**`compose: false`** — execute o `/cloudez:compose` **antes** de converter, e só
volte quando o arquivo estiver escrito. Converter primeiro deixaria o site fora do
ar pelo tempo de escrever o Compose junto com o usuário, em vez de pelo tempo de um
deploy.

Guarde a porta que o Compose publica (`ports[].published`): é a `custom_port` do
passo 7.

## 4. Confirmar com o usuário

Com AskUserQuestion, diga em termos do que acontece, sem nome de campo ou arquivo:

- o site **sai do ar agora** e volta quando o deploy terminar, em seguida;
- o conteúdo atual do site vai para uma pasta de backup **no próprio servidor**
  (`www/bkp-<data>/`) — nada é apagado;
- o **banco de dados não é tocado**;
- voltar ao tipo antigo não é algo que este plugin faça.

Opções: converter e publicar agora, ou cancelar. **Sem aceite explícito, pare** —
é a única etapa deste plugin que tira do ar um site que estava funcionando.

## 5. Chave SSH desta máquina

O backup e o deploy conectam por SSH. Siga o passo 6 do `commands/setup.md`, lendo
o arquivo em vez de reconstruir o procedimento.

Se a chave foi autorizada agora, lembre que ela leva até um minuto para valer no
servidor: um `ssh_failed` no passo 6 logo depois disso é esse atraso.

## 6. Converter

```
cloudez_convert_site(domain: "<domain>")
```

A tool troca o tipo e, só depois de confirmar a troca, move o conteúdo do site
para o backup.

**Sucesso** — diga onde ficou o backup (`backup_path`), em uma frase. `moved: 0`
quer dizer que não havia nada a guardar; não é erro.

**`cloud_too_small`** — **pare.** A cloud tem menos RAM que o mínimo do tipo
Claude, e **nada foi alterado**: o site continua no ar como estava. Diga o que o
`hint` diz sobre a saída.

**`ssh_failed`** — o tipo **já foi trocado**, e os arquivos continuam onde estavam.
Diga isso, espere um minuto se a chave acabou de ser autorizada, e chame a mesma
tool de novo: ela refaz só o backup. Não siga para o deploy sem o backup feito.

## 7. Configurar o site

O usuário já aceitou a saída do ar no passo 4, então isto não pede um segundo
aceite:

```
cloudez_configure_site(
  domain: "<domain>",
  app_root_path: "claude/current",
  custom_port: "<a porta do passo 3>",
  framework: "<o framework do projeto, escolhido como no passo 2 do setup>"
)
```

Se vier erro dizendo que o valor **não mudou**, não siga para o deploy: o site
publicaria sem aparecer.

## 8. Publicar

Execute o `/cloudez:deploy` com o mesmo environment, sem perguntar de novo: o
aceite do passo 4 já foi para converter **e** publicar. É o deploy que traz o site
de volta ao ar.
