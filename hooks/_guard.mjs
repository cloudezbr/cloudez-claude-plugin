/**
 * Decisão do guard-rail de escrita, separada do processo que a aplica, para
 * poder ser testada como função em vez de exercitar o adaptador.
 */

import { createHash } from "node:crypto"
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"

// Endereços temporários que a Cloudez dá aos sites, antes do domínio próprio.
const TEMPORARIOS = [".cloudezapp.io", ".configr.cloud"]

/**
 * Os hosts remotos que este comando escreveria. Vazio significa "pode passar".
 *
 * O critério é o verbo, não o conteúdo: num `curl`, `-d` já implica POST e
 * `-F` é upload. Leitura (GET, HEAD) passa sempre.
 */
export function escritaRemota(cmd) {
  if (typeof cmd !== "string") return []

  const remotos = []
  for (const trecho of segmentos(cmd)) {
    if (!/(^|\s)(curl|wget)(\s|$)/.test(trecho)) continue
    if (!escreve(trecho)) continue
    for (const host of hosts(trecho)) if (!local(host)) remotos.push(host)
  }
  return [...new Set(remotos)]
}

/**
 * Quebra a linha nos operadores do shell.
 *
 * Sem isto, uma flag `-d` de `cut` ou `xargs` no mesmo pipeline de um `curl`
 * de leitura contava como intenção de escrita. A quebra é textual e não
 * entende aspas, mas só pode partir um trecho em dois, nunca juntar dois.
 */
function segmentos(cmd) {
  return cmd.split(/\|\||&&|[|;\n]/)
}

/**
 * Verbo de escrita neste trecho. `-d` já é POST no curl, `-F` é upload.
 * Com `-G`, `--get` ou `-X GET`, os dados vão na URL de um GET, e isso é leitura.
 */
function escreve(t) {
  if (/(^|\s)-X\s*(POST|PUT|PATCH|DELETE)\b/i.test(t)) return true
  if (/--(request|method)[=\s]+(POST|PUT|PATCH|DELETE)\b/i.test(t)) return true
  if (/(^|\s)-[a-zA-Z]*G[a-zA-Z]*(\s|$)/.test(t) || /(^|\s)--get(\s|$)/.test(t)) return false
  if (/(^|\s)-X\s*GET\b/i.test(t) || /--request[=\s]+GET\b/i.test(t)) return false
  return (
    /(^|\s)-[a-zA-Z]*[dFT](\s|=)/.test(t) ||
    /--(data|data-raw|data-binary|data-urlencode|form|upload-file|post-data|post-file)\b/.test(t)
  )
}

function hosts(t) {
  const out = []
  for (const m of t.matchAll(/https?:\/\/([^\s/'"$)]+)/gi)) {
    out.push(
      m[1]
        .replace(/^[^@]*@/, "") // usuário:senha@
        .replace(/:\d+$/, "") // porta
        .toLowerCase(),
    )
  }
  return out
}

/**
 * Endereço da própria máquina. O `/cloudez:dev` sobe a aplicação em
 * `localhost` para ser exercitada à vontade; barrar ali não protegeria nada.
 */
export function local(host) {
  return (
    host === "localhost" ||
    host === "127.0.0.1" ||
    host === "::1" ||
    host === "[::1]" ||
    host === "0.0.0.0" ||
    host.endsWith(".localhost") ||
    host.endsWith(".local")
  )
}

/**
 * Os domínios do `.cloudez.yaml` mais próximo de `cwd`, subindo pelos diretórios, ou `null`
 * fora de um projeto da Cloudez. É o que limita o hook ao que o plugin publica.
 */
export function dominiosDoProjeto(cwd) {
  if (typeof cwd !== "string" || cwd === "") return null
  for (let dir = cwd; ; dir = dirname(dir)) {
    let texto
    try {
      texto = readFileSync(join(dir, ".cloudez.yaml"), "utf8")
    } catch {
      if (dirname(dir) === dir) return null
      continue
    }
    const dominios = [...texto.matchAll(/^\s*domain:\s*["']?([A-Za-z0-9.-]+)/gm)].map((m) => m[1].toLowerCase())
    return [...new Set(dominios)]
  }
}

// Host da aplicação do projeto: um domínio dele, um subdomínio (como o studio.) ou endereço temporário.
export function protegido(host, dominios) {
  if (TEMPORARIOS.some((sufixo) => host.endsWith(sufixo))) return true
  return dominios.some((d) => host === d || host.endsWith(`.${d}`))
}

/**
 * Hash do comando inteiro, não só do host: aprovar um `POST /api/uploads`
 * não pode liberar um `DELETE /api/uploads/tudo` do mesmo domínio.
 */
export function hash(cmd) {
  return createHash("sha256").update(cmd, "utf8").digest("hex")
}
