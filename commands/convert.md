---
description: Converte um site que já existe na Cloudez (WordPress, html ou outro tipo) para o tipo Claude, guardando os arquivos atuais num backup no servidor, e publica o projeto local nele. Sem o código na máquina, baixa antes o site WordPress ou html do servidor e monta o Compose dele. Use quando o site do .cloudez.yaml não for do tipo Claude e o usuário quiser fazer deploy nele, mesmo sem ter o código local.
argument-hint: "[domain] [environment]"
allowed-tools: mcp__cloudez__cloudez_auth_status, mcp__cloudez__cloudez_panel_info, mcp__cloudez__cloudez_signup, mcp__cloudez__cloudez_resend_phone_code, mcp__cloudez__cloudez_confirm_phone, mcp__cloudez__cloudez_get_site, mcp__cloudez__cloudez_find_compose, mcp__cloudez__cloudez_list_local_ssh_keys, mcp__cloudez__cloudez_authorize_ssh_key, mcp__cloudez__cloudez_convert_site, mcp__cloudez__cloudez_configure_site, mcp__cloudez__cloudez_begin_pull, mcp__cloudez__cloudez_prepare_wordpress, Bash(cloudez-setup:*), Bash(cloudez-pull:*), Read, AskUserQuestion
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
  Siga normalmente: a tool do passo 8 percebe e só termina o que faltou.
- **qualquer outro** (`wordpress`, `html`, ...) — é o caso deste comando. Vá direto para o passo 3.

## 3. Perguntar se o usuário quer converter

**Sempre pergunte, logo depois de identificar o tipo**, antes de qualquer outra
coisa: nada de Compose, chave SSH ou backup antes da resposta. Vale também quando
este comando foi aberto pelo `/cloudez:deploy` ou pelo `/cloudez:setup`, e quando
o pedido do usuário foi "publica" ou "faz o deploy": pedir o deploy não é aceitar
a conversão. A única exceção é o usuário já ter respondido sim a esta mesma
pergunta, com o aviso de downtime, nesta conversa.

Com AskUserQuestion, pergunte se ele quer converter o site para o tipo Claude, e
diga em termos do que acontece, sem nome de campo ou arquivo:

- **pode haver breves períodos de downtime**: o site sai do ar na conversão e
  volta quando o deploy terminar, em seguida;
- o conteúdo atual do site vai para uma pasta de backup **no próprio servidor**
  (`www/bkp-<data>/`), e nada é apagado;
- o **banco de dados não é tocado**;
- voltar ao tipo antigo não é algo que este plugin faça.

Opções: converter e publicar, ou cancelar. **Sem aceite explícito, pare.** É a
única etapa deste plugin que tira do ar um site que estava funcionando.

## 4. Chave SSH desta máquina

O download, o backup e o deploy conectam por SSH. Siga o passo 6 do
`commands/setup.md`, lendo o arquivo em vez de reconstruir o procedimento.

Se a chave foi autorizada agora, lembre que ela leva até um minuto para valer no
servidor: um `ssh_failed` logo depois disso é esse atraso.

## 5. O projeto tem o código do site?

Olhe o diretório do projeto. Se ele só tem `.cloudez.yaml`, `.git`, `.gitignore`,
`.claude` ou `.DS_Store`, o usuário não tem o código na máquina, e o caminho é
baixar o site do servidor. Isso vale para `wordpress` e `html`; para outro tipo,
diga que o download não cobre aquele tipo e peça o código ao usuário.

Com o código no diretório, pule para o passo 6.

**Inspecionar.** Antes de qualquer pergunta:

```
cloudez_begin_pull(domain: "<domain>")
```

Ela não altera nada no servidor. Devolve o `pull_id`, o `kind` (`wordpress` ou
`html`) e os tamanhos medidos lá: `total_bytes` (tudo, com os uploads),
`uploads_bytes` (`wp-content/uploads`) e `database_bytes`. Campo ausente quer
dizer que a medição falhou: diga que não se sabe, não chute.

**`source_not_found`**: não há arquivos no servidor. Diga isso e peça o código ao
usuário.

**Oferecer o download.** Com AskUserQuestion, ofereça baixar o site do servidor
para o diretório do projeto. No WordPress, as opções são baixar **sem** as mídias
(`wp-content/uploads`), baixar **com** elas, ou não baixar e trazer o código por
conta própria. Diga, em cada opção, quanto será baixado e quanto disco ocupa na
máquina: sem as mídias é `total_bytes` menos `uploads_bytes`; com elas,
`total_bytes`. Some o banco quando houver `database_bytes`, e diga que os tamanhos
são do disco do servidor, sem compressão. Sem as mídias o site local abre com as
imagens quebradas, e produção não perde nada: lá elas continuam no servidor. Num
`html`, as opções são baixar ou não. Sem aceite, não baixe: peça o código.

Se vier `database_unavailable`, diga ao usuário que o banco não vem junto, e por
quê: sem ele o WordPress local não abre.

**Baixar:**

```sh
cloudez-pull <pull_id> <diretório do projeto>                  # sem os uploads
cloudez-pull <pull_id> <diretório do projeto> --with-uploads   # com eles
```

Ele recusa um diretório com código (`directory_not_empty`) sem apagar nada. No
WordPress, o dump do banco fica em `.cloudez/db/dump.sql.gz`, e o `cloudez-pull`
garante `.cloudez/db/` no `.gitignore`, que é o que o mantém fora do deploy.

- **`transfer_failed`**: o que chegou ficou no diretório. Mostre o `logs`, e só
  repita com o usuário de acordo em esvaziar o diretório.
- **`database_dump_failed`**: os arquivos chegaram e o banco não. Mostre o
  `logs` e diga que o WordPress local não abre sem ele.

**O `wp-config.php` baixado tem a senha do banco de produção.** Diga ao usuário
que não commite nada até o Compose estar escrito, porque é ali que esse arquivo é
reescrito sem a senha. Não mostre o conteúdo dele na conversa.

## 6. O projeto tem Compose?

```
cloudez_find_compose(directory: "<diretório do projeto>")
```

**`compose: false`**: execute o `/cloudez:compose` **antes** de converter, e só
volte quando o arquivo estiver escrito. Converter primeiro deixaria o site fora do
ar pelo tempo de escrever o Compose junto com o usuário, em vez de pelo tempo de um
deploy. Para um WordPress baixado no passo 5, é a seção do WordPress daquele
comando que vale.

Guarde a porta que a sobreposição põe em produção, ou a que o Compose publica
(`ports[].published`): é a `custom_port` do passo 10.

## 7. Testar na máquina, antes de converter

Só quando o site foi baixado no passo 5. Ofereça o `/cloudez:dev` antes de
converter: **o site ainda está no ar**, e é o único momento em que um problema do
Compose não custa downtime. Se o usuário aceitar, execute o comando e volte aqui
quando ele disser que o site local está certo.

## 8. Converter

```
cloudez_convert_site(domain: "<domain>", user_confirmed: true)
```

A tool troca o tipo e, só depois de confirmar a troca, move o conteúdo do site
para o backup.

**Sucesso**: diga onde ficou o backup (`backup_path`), em uma frase. `moved: 0`
quer dizer que não havia nada a guardar; não é erro.

**`ssh_failed`**: o tipo **já foi trocado**, e os arquivos continuam onde estavam.
Diga isso, espere um minuto se a chave acabou de ser autorizada, e chame a mesma
tool de novo: ela refaz só o backup. Não siga para o deploy sem o backup feito.

## 9. Levar o WordPress para o `shared/`

Só para um WordPress com o Compose da seção do WordPress do `/cloudez:compose`:

```
cloudez_prepare_wordpress(domain: "<domain>")
```

Copia o `wp-content` do backup para o `shared/` do site e grava a senha do banco,
o prefixo e os salts no arquivo de ambiente, lidos do `wp-config.php` do backup
**dentro do servidor**: nenhum valor passa pela conversa. Repetir é seguro.

- **`missing`** não vazio: aquelas chaves não estavam no `wp-config.php`. Sem as
  do banco o site não conecta; pergunte o valor ao usuário e grave com
  `cloudez_set_env`.
- **`wp_content: "absent"`**: o backup não tinha `wp-content`, e o primeiro
  deploy vai usar o do projeto.

## 10. Configurar o site

O usuário já aceitou a saída do ar no passo 3, então isto não pede um segundo
aceite:

```
cloudez_configure_site(
  domain: "<domain>",
  app_root_path: "claude/current",
  custom_port: "<a porta do passo 6>",
  framework: "<o framework do projeto, escolhido como no passo 2 do setup; wordpress para o site baixado no passo 5>"
)
```

Se vier erro dizendo que o valor **não mudou**, não siga para o deploy: o site
publicaria sem aparecer.

## 11. Publicar

Execute o `/cloudez:deploy` com o mesmo environment, sem perguntar de novo: o
aceite do passo 3 já foi para converter **e** publicar. É o deploy que traz o site
de volta ao ar.
