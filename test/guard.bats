#!/usr/bin/env bats
# O guard-rail de escrita em aplicacao viva.
#
# Existe por dois incidentes: um recado assinado "Claude" num mural publico
# gravado em Postgres, e um PNG num site de uploads. Nenhum foi desobediencia a
# uma regra escrita — foram falhas de CLASSIFICACAO, e por isso a barreira e
# mecanica em vez de textual.

load helpers/setup

setup() { make_project; }

chamada() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$1"; }
guard() { chamada "$1" | node "$PLUGIN_ROOT/hooks/guard-write.mjs"; }

aprovar_para() {
  mkdir -p "$CLOUDEZ_GUARD_DIR"
  node -e '
    const c = require("node:crypto"), fs = require("node:fs"), p = require("node:path")
    const h = c.createHash("sha256").update(process.argv[1], "utf8").digest("hex")
    const at = Date.now() - Number(process.argv[2] || 0) * 60000
    fs.writeFileSync(p.join(process.env.CLOUDEZ_GUARD_DIR, "approved-write.json"), JSON.stringify({ hash: h, at }))
  ' "$1" "${2:-0}"
}

# ---------------------------------------------------------------- a decisao --

# Ler nao muda nada do outro lado, e e como se confere um status ou uma listagem.
@test "guard: leitura remota passa" {
  run guard '"curl -s https://example.com/api/uploads"'
  [ "$status" -eq 0 ]
}

@test "guard: leitura com flags de saida passa" {
  run guard '"curl -s -o /dev/null -w %{http_code} https://example.com/"'
  [ "$status" -eq 0 ]
}

@test "guard: escrita remota bloqueia com exit 2" {
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"ESCREVE numa aplicacao remota"* ]] || [[ "$output" == *"ESCREVE numa aplicação remota"* ]]
  [[ "$output" == *"cloudez-approve"* ]]
}

# -d ja implica POST no curl, e -F e upload: o criterio e o VERBO, nao o conteudo.
@test "guard: -d e -F bloqueiam sem precisar de -X" {
  run guard '"curl -d nome=x https://example.com/recados"'
  [ "$status" -eq 2 ]
  run guard '"curl -s -F file=@a.png https://example.com/api/uploads"'
  [ "$status" -eq 2 ]
}

@test "guard: DELETE bloqueia" {
  run guard '"curl -X DELETE https://example.com/api/uploads/1"'
  [ "$status" -eq 2 ]
}

# O /cloudez:dev sobe a aplicacao em localhost para ser exercitada a vontade.
@test "guard: escrita em localhost passa" {
  run guard '"curl -X POST http://localhost:3005/api/uploads"'
  [ "$status" -eq 0 ]
  run guard '"curl -X POST http://127.0.0.1:3000/x"'
  [ "$status" -eq 0 ]
}

# REGRESSAO: a analise varria a linha INTEIRA, e qualquer flag terminada em d, F
# ou T contava como intencao de escrita — mesmo vindo de outro programa do
# pipeline. Leitura seguida de filtro comum era bloqueada, que e metade do uso
# legitimo de curl.
@test "guard: leitura com filtro no pipe passa" {
  run guard '"curl -s https://example.com/x | grep -F erro"'
  [ "$status" -eq 0 ]
  run guard '"curl -s https://example.com/x | cut -d , -f2"'
  [ "$status" -eq 0 ]
  run guard '"curl -s https://example.com/x | xargs -d \n echo"'
  [ "$status" -eq 0 ]
}

# Mas escrita em QUALQUER trecho do pipeline continua barrada.
@test "guard: escrita num trecho posterior do pipe bloqueia" {
  run guard '"curl -s https://a.com/ | curl -X POST https://staging.example.com/"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"staging.example.com"* ]]
}

@test "guard: os comandos do proprio plugin passam" {
  run guard '"cloudez-sync dpl_x ../site"'
  [ "$status" -eq 0 ]
  run guard '"pbpaste | /caminho/bin/cloudez-login --stdin"'
  [ "$status" -eq 0 ]
}

@test "guard: comando sem curl nem wget passa" {
  run guard '"git push origin main"'
  [ "$status" -eq 0 ]
}

@test "guard: tool que nao e Bash passa" {
  run bash -c 'printf "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/x\"}}" | node "$PLUGIN_ROOT/hooks/guard-write.mjs"'
  [ "$status" -eq 0 ]
}

# --------------------------------------------------------------- a aprovacao --

@test "guard: o bloqueio registra o pedido para o approve exibir" {
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 2 ]
  [ -f "$CLOUDEZ_GUARD_DIR/pending-write.json" ]
  [ "$(campo_de "$CLOUDEZ_GUARD_DIR/pending-write.json" .command)" = "curl -X POST https://example.com/api/uploads" ]
}

@test "guard: aprovacao libera o comando exato" {
  aprovar_para "curl -X POST https://example.com/api/uploads"
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 0 ]
}

# "Por comando" tem de significar por comando: sem isso viraria por janela de tempo.
@test "guard: a aprovacao e de USO UNICO" {
  aprovar_para "curl -X POST https://example.com/api/uploads"
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 0 ]
  [ ! -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 2 ]
}

# Aprovar um POST nao pode liberar um DELETE no mesmo dominio.
@test "guard: aprovacao nao vale para outro comando" {
  aprovar_para "curl -X POST https://example.com/inofensivo"
  run guard '"curl -X DELETE https://example.com/api/tudo"'
  [ "$status" -eq 2 ]
}

@test "guard: aprovacao expirada nao vale" {
  aprovar_para "curl -X POST https://example.com/api/uploads" 11
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 2 ]
}

# ------------------------------------------------------------------ o approve --

# ESTA e a propriedade que sustenta a barreira. A primeira versao usava
# createReadStream, que e preguicoso e nao falha de forma sincrona: o approve
# rodado SEM terminal exibia o prompt em vez de recusar.
@test "guard: cloudez-approve sem TTY recusa" {
  run guard '"curl -X POST https://example.com/api/uploads"'
  run bash -c 'cloudez-approve < /dev/null 2>&1'
  [ "$status" -ne 0 ]
  [ "$(campo "$output" .error.code)" = "no_tty" ]
  [ ! -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]
}

# Com TERMINAL, de proposito. A versao anterior deste teste rodava
# `< /dev/null` e afirmava so `status != 0` — o que a checagem de TTY ja satisfaz
# sozinha. Ele passava sem nunca alcancar o caminho que diz cobrir, e o relatorio
# de cobertura foi quem denunciou: as linhas do `nothing_pending` continuavam
# marcadas como nunca executadas.
@test "guard: approve com terminal e sem nada pendente diz que nao ha pedido" {
  rm -f "$CLOUDEZ_GUARD_DIR/pending-write.json"
  run com_pty $'\n' cloudez-approve
  [ "$status" -ne 0 ]
  [ "$(campo_pty "$output" .error.code)" = "nothing_pending" ]
  [ ! -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]
}

# A aprovacao vale por minutos. Sem esta recusa, um pedido esquecido no disco
# ficaria aprovavel para sempre — e o usuario aprovaria, sem lembrar, um comando
# que o agente montou numa conversa de ontem.
@test "guard: pedido velho expira em vez de ser aprovavel" {
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 2 ]

  # Envelhece o pedido para alem do TTL, mexendo so no carimbo.
  node -e '
    const f = process.env.CLOUDEZ_GUARD_DIR + "/pending-write.json"
    const fs = require("node:fs")
    const p = JSON.parse(fs.readFileSync(f, "utf8"))
    p.at = Date.now() - 99 * 60000
    fs.writeFileSync(f, JSON.stringify(p))
  '

  run com_pty $'aprovo\n' cloudez-approve
  [ "$status" -ne 0 ]
  [ "$(campo_pty "$output" .error.code)" = "pending_expired" ]
  # E o mais importante: nem digitando "aprovo" ele libera.
  [ ! -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]
}

@test "guard: com terminal, aprova e libera uma vez" {
  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 2 ]

  # Com \n: o readline resolve na quebra de linha. Sem terminador o helper manda
  # EOT, e o readline — diferente do prompt do cloudez-login — nao o trata como
  # fim de entrada, entao a pergunta nunca resolve e a suite pendura.
  com_pty $'aprovo\n' cloudez-approve
  [ -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]

  run guard '"curl -X POST https://example.com/api/uploads"'
  [ "$status" -eq 0 ]
}

@test "guard: com terminal, resposta diferente NAO aprova" {
  run guard '"curl -X POST https://example.com/api/uploads"'
  com_pty $'nao\n' cloudez-approve || true
  [ ! -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]
}

# ------------------------------------------------------------------ o escopo --

# O hook so protege a aplicacao publicada. Barrar Slack ou a API de terceiros
# travava quem usa o Claude Code em outros servicos, sem proteger nada da Cloudez.
@test "guard: escrita em servico de terceiro passa, mesmo num projeto da Cloudez" {
  run guard '"curl -s -X POST https://hooks.slack.com/services/x -d {}"'
  [ "$status" -eq 0 ]
  run guard '"curl -s -X POST https://graph.instagram.com/v23.0/1/media -d a=b"'
  [ "$status" -eq 0 ]
}

# O subdominio e da aplicacao: o studio. do Supabase e o caso que mais importa.
@test "guard: subdominio do projeto e endereco temporario bloqueiam" {
  run guard '"curl -X POST https://studio.example.com/api/x"'
  [ "$status" -eq 2 ]
  run guard '"curl -X POST https://meusite.cloudezapp.io/api/x"'
  [ "$status" -eq 2 ]
  run guard '"curl -X POST https://notexample.com/api/x"'
  [ "$status" -eq 0 ]
}

@test "guard: fora de um projeto da Cloudez nada bloqueia" {
  mkdir -p "$TEST_TMP/outro"
  run bash -c 'cd "$TEST_TMP/outro" && printf "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"curl -X POST https://example.com/x\"}}" | node "$PLUGIN_ROOT/hooks/guard-write.mjs"'
  [ "$status" -eq 0 ]
}

# O harness manda o cwd da sessao, e e ele que decide, nao o diretorio do processo.
@test "guard: o cwd da chamada decide o projeto, inclusive num subdiretorio" {
  mkdir -p "$TEST_TMP/project/app/src" "$TEST_TMP/outro"
  run bash -c 'cd "$TEST_TMP/outro" && printf "{\"tool_name\":\"Bash\",\"cwd\":\"%s\",\"tool_input\":{\"command\":\"curl -X POST https://example.com/x\"}}" "$TEST_TMP/project/app/src" | node "$PLUGIN_ROOT/hooks/guard-write.mjs"'
  [ "$status" -eq 2 ]
  run bash -c 'cd "$TEST_TMP/project" && printf "{\"tool_name\":\"Bash\",\"cwd\":\"%s\",\"tool_input\":{\"command\":\"curl -X POST https://example.com/x\"}}" "$TEST_TMP/outro" | node "$PLUGIN_ROOT/hooks/guard-write.mjs"'
  [ "$status" -eq 0 ]
}

# Com -G, --get ou -X GET os dados vao na URL de um GET.
@test "guard: -G, --get e -X GET sao leitura" {
  run guard '"curl -s -G https://example.com/busca --data-urlencode q=x"'
  [ "$status" -eq 0 ]
  run guard '"curl -sG https://example.com/busca -d q=x"'
  [ "$status" -eq 0 ]
  run guard '"curl --get https://example.com/busca -d q=x"'
  [ "$status" -eq 0 ]
  run guard '"curl -X GET https://example.com/busca -d q=x"'
  [ "$status" -eq 0 ]
  run guard '"curl -X POST -G https://example.com/busca -d q=x"'
  [ "$status" -eq 2 ]
}

# ------------------------------------------------------------- o interruptor --

@test "guard: CLOUDEZ_GUARD=off no ambiente do Claude Code desliga o hook" {
  run bash -c 'printf "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"curl -X POST https://example.com/x\"}}" | CLOUDEZ_GUARD=off node "$PLUGIN_ROOT/hooks/guard-write.mjs"'
  [ "$status" -eq 0 ]
}

# O agente nao desliga o hook escrevendo a variavel no proprio comando.
@test "guard: CLOUDEZ_GUARD=off dentro do comando nao desliga" {
  run guard '"CLOUDEZ_GUARD=off curl -X POST https://example.com/x"'
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------- aprovacao por host --

@test "guard: aprovacao por host libera outros comandos no mesmo host, so nele" {
  run guard '"curl -X POST https://example.com/api/a"'
  [ "$status" -eq 2 ]
  com_pty $'aprovo\n' cloudez-approve --host --minutes 5

  run guard '"curl -X POST https://example.com/api/a"'
  [ "$status" -eq 0 ]
  run guard '"curl -X DELETE https://example.com/api/b"'
  [ "$status" -eq 0 ]
  run guard '"curl -X POST https://staging.example.com/api/a"'
  [ "$status" -eq 2 ]
}

@test "guard: aprovacao por host vencida nao vale" {
  mkdir -p "$CLOUDEZ_GUARD_DIR"
  node -e '
    const fs = require("node:fs")
    const a = { approvals: [{ kind: "host", host: "example.com", until: Date.now() - 1000 }] }
    fs.writeFileSync(process.env.CLOUDEZ_GUARD_DIR + "/approved-write.json", JSON.stringify(a))
  '
  run guard '"curl -X POST https://example.com/api/a"'
  [ "$status" -eq 2 ]
}

@test "guard: --minutes fora de 1 a 60 e recusado" {
  run guard '"curl -X POST https://example.com/api/a"'
  run com_pty $'aprovo\n' cloudez-approve --host --minutes 120
  [ "$status" -ne 0 ]
  [ "$(campo_pty "$output" .error.code)" = "usage" ]
  [ ! -f "$CLOUDEZ_GUARD_DIR/approved-write.json" ]
}

# ---------------------------------------------------------------- o Windows --

# Sem o .cmd, quem chama pelo cmd ou pelo PowerShell nao acha o comando. O
# conteudo deriva o alvo do nome do arquivo, entao os tres sao iguais.
@test "guard: os launchers Windows existem e sao iguais ao do sync" {
  for nome in cloudez-approve cloudez-login; do
    cmp -s "$PLUGIN_ROOT/bin/cloudez-sync.cmd" "$PLUGIN_ROOT/bin/$nome.cmd"
  done
}
