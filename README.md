# cloudez-claude-plugin

Plugin do Claude Code para desenvolver e fazer deploy de sites na Cloudez.

## Requisitos

- [Claude Code](https://claude.com/claude-code)
- **Node 20+** — roda o servidor MCP embutido e os adaptadores de `bin/`
- `ssh` e `tar` na máquina local, com uma chave SSH em `~/.ssh/`
- Uma conta na Cloudez. O site precisa ser do tipo **Claude**, numa cloud com
  pelo menos 2 GB de RAM; um site de outro tipo (WordPress, html) é convertido
  pelo `/cloudez:convert`

Não há etapa de build nem `npm install`: o servidor MCP vem pronto em `mcp/`.

## Instalação

### Para o cliente final

No Claude Code:

```
/plugin marketplace add cloudezbr/cloudez-claude-plugin
/plugin install cloudez@cloudez
```

Para atualizar: `/plugin marketplace update cloudez`.

### Para desenvolvimento local

Carregar o plugin a partir do clone, só nesta sessão:

```sh
claude --plugin-dir /caminho/para/cloudez-claude-plugin
```

Depois de editar qualquer arquivo, `/reload-plugins` recarrega sem reiniciar a
sessão. Para instalar o clone de forma permanente:

```
/plugin marketplace add /caminho/para/cloudez-claude-plugin
/plugin install cloudez@cloudez
```

| Comando | O que faz |
| --- | --- |
| `test/run.sh` | roda a suíte inteira (estrutura, estático, unidade, comportamento) |
| `test/run.sh --strict` | igual, mas ferramenta ausente vira erro — o que o CI usa |
| `claude plugin validate .` | confere só a estrutura do plugin |
| `./vendor-mcp.sh [caminho]` | traz o bundle do [`cloudez-mcp`](https://github.com/cloudezbr/cloudez-mcp) para `mcp/`, depois de mudar o servidor MCP |

## Comandos

| Comando | O que faz |
| --- | --- |
| `/cloudez:login` | confere o token da Cloudez e, sem ele, cria a conta ou leva até o token no painel |
| `/cloudez:hire-cloud` | contrata uma cloud: o teste grátis por aqui, o plano pago pelo painel |
| `/cloudez:setup <domínio> <environment>` | liga o projeto a um site da Cloudez, criando o site se ele não existir |
| `/cloudez:compose [diretório]` | escreve o Compose da aplicação junto com você |
| `/cloudez:dev [diretório]` | sobe o site localmente e abre no navegador do Claude Code |
| `/cloudez:deploy [environment] [diretório]` | publica o projeto, com ativação atômica da release |
| `/cloudez:convert [domínio] [environment]` | converte um site de outro tipo para Claude, com backup no servidor, e publica |
| `/cloudez:rollback [environment] [release_id]` | volta o site para uma release anterior |

Todos também atendem pedido em linguagem natural ("publica meu site na
Cloudez"). Para começar do zero, basta pedir o deploy: o plugin conduz o login, a
ligação com o site e o Compose no caminho.

## Permissões

Para reduzir os pedidos de permissão, as tools só de leitura podem ir para o
allowlist em `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__cloudez__cloudez_list_sites",
      "mcp__cloudez__cloudez_get_site",
      "mcp__cloudez__cloudez_list_releases"
    ]
  }
}
```

As que mudam estado no servidor ficam de fora de propósito.

## Proteção contra escrita na aplicação publicada

Num projeto com `.cloudez.yaml`, o plugin bloqueia `curl` e `wget` que escrevam
(POST, PUT, PATCH, DELETE, `-d`, `-F`) nos hosts da aplicação: os domínios do
`.cloudez.yaml`, os subdomínios deles e os endereços temporários da Cloudez
(`*.cloudezapp.io`, `*.configr.cloud`). Leitura passa, inclusive com `-G` ou
`--get`, e qualquer outro host passa. Fora de um projeto da Cloudez, o hook não
faz nada.

Quando ele bloqueia, quem libera é você, no seu terminal:

```sh
cloudez-approve                        # o comando bloqueado, uma vez só
cloudez-approve --host                 # os hosts dele, por 30 minutos
cloudez-approve --host --minutes 60    # os hosts dele, por até 60 minutos
```

No Windows, rode no PowerShell ou no Prompt de Comando, não por duplo clique.

**Para desligar só o hook**, sem desinstalar o plugin, defina `CLOUDEZ_GUARD=off`
no ambiente do Claude Code, por exemplo no `settings.json`:

```json
{ "env": { "CLOUDEZ_GUARD": "off" } }
```

Prefixar o comando com a variável não desliga nada: o hook roda antes do comando,
com o ambiente do Claude Code.

**Se o hook continuar ativo depois de desinstalar**, o plugin ainda está ligado em
outro escopo. Confira o `.claude/settings.json` do projeto: com
`"cloudez@cloudez": true` em `enabledPlugins`, troque para `false` e rode
`/reload-plugins`.

## Documentação

- `commands/*.md` — o procedimento de cada comando
- [`docs/mcp-tool-contract.md`](docs/mcp-tool-contract.md) — o contrato das tools do MCP
