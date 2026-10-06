/**
 * Transporte: tar local em stream para tar remoto, através de ssh, e o
 * inverso, do servidor para a máquina, para o cloudez-pull.
 *
 * Não é rsync: rsync não existe no Windows, o diretório de release está
 * sempre vazio (nada para o delta transfer comparar), e um stream único é
 * mais rápido que os round-trips do scp.
 *
 * O pipe entre os dois processos é montado por descritor, nunca por
 * `.pipe()` do Node, que rotearia cada byte pelo event loop e degradaria a
 * vazão. Ver `esperar` para por que o pai só lê, nunca escreve.
 */

import { spawn } from "node:child_process"

import { listarPayload } from "./_payload.mjs"

/**
 * Envia o conteúdo de `localDir` para o destino ssh gravado no estado do deploy.
 *
 * Devolve `{ stats, logs, erro }`. `erro` nulo é sucesso; `logs` é a stderr
 * agregada dos dois processos, e vem preenchida também no sucesso (o ssh emite
 * aviso de host novo na primeira conexão, que não é falha).
 */
export function transferir(dep, localDir) {
  /**
   * A lista de arquivos vai por stdin, não por `--exclude`: a semântica do
   * gitignore (âncora, negação, `**`) não tem tradução fiel para `--exclude`,
   * e é a mesma lista que o hash percorre, então as duas nunca divergem.
   */
  const { entries, ignore } = listarPayload(localDir)

  /**
   * conferirDiretorio (em cloudez-sync) só olha se o diretório tem algo
   * dentro, e um dist/ cujo .gitignore exclui tudo ainda tem o próprio
   * .gitignore. Sem esta recusa o deploy enviaria um pacote vazio e ativaria
   * uma release sem nenhum arquivo.
   */
  if (entries.length === 0) {
    const e = new Error(mensagemVazio(localDir, ignore))
    e.code = "build_output_empty"
    throw e
  }

  /**
   * `-C` antes de `-T`: no GNU tar `-C` é posicional, e um `-C` depois de
   * `-T` não alcança os nomes lidos da stdin, produzindo um pacote vazio.
   */
  const tarArgs = ["-czf", "-", "-C", localDir, "-T", "-"]

  const sshArgs = argsSsh(dep.ssh, `tar xzf - -C ${aspasParaShellRemoto(dep.ssh.path)}`)

  /**
   * COPYFILE_DISABLE=1 impede o tar do macOS de empacotar os metadados
   * AppleDouble (`._index.html` e afins). Fora do macOS a variável não
   * existe e o tar a ignora, sem precisar de condicional por plataforma.
   */
  const tar = spawn("tar", tarArgs, {
    stdio: ["pipe", "pipe", "pipe"],
    env: { ...process.env, COPYFILE_DISABLE: "1" },
  })

  /**
   * A lista, não o conteúdo, entra pela stdin do tar; o pipe do sistema a
   * absorve antes mesmo de o ssh estar de pé.
   */
  tar.stdin.on("error", () => {}) // EPIPE quando o tar morre antes de ler tudo.
  tar.stdin.end(entries.map((e) => e.rel).join("\n") + "\n")

  /**
   * tar.stdout entra como stdin do ssh por descritor duplicado, sem passar
   * pelo pai. Ler `tar.stdout` aqui também criaria um segundo leitor do
   * mesmo pipe, dividindo os bytes entre os dois e corrompendo o pacote:
   * o `destroy` fecha essa ponta de vez.
   */
  const ssh = spawn("ssh", sshArgs, { stdio: [tar.stdout, "pipe", "pipe"] })
  tar.stdout.destroy()

  let tarErr = ""
  let sshErr = ""
  tar.stderr.setEncoding("utf8")
  ssh.stderr.setEncoding("utf8")
  tar.stderr.on("data", (d) => { tarErr += d })
  ssh.stderr.on("data", (d) => { sshErr += d })

  return Promise.all([esperar(tar, "tar"), esperar(ssh, "ssh")]).then(([doTar, doSsh]) => {
    const logs = `${tarErr}\n${sshErr}`.trim()

    /**
     * Checa o tar antes do ssh: se o tar local falhar no meio, o tar remoto
     * ainda pode extrair o parcial e sair zero, o que reportaria sucesso.
     */
    if (doTar) return { stats: "", logs, erro: doTar }
    if (doSsh) return { stats: "", logs, erro: doSsh }

    const resumo = ignore.sources.length > 0 ? ` (${ignore.sources.join("+")}: ${ignore.pruned} podados)` : ""
    return { stats: `tar+ssh -> ${dep.ssh.host}:${dep.ssh.path}${resumo}`, logs, erro: null }
  })
}

/**
 * O sentido inverso, para o cloudez-pull: o comando remoto escreve um tar.gz
 * em stdout, e o `tar` local o extrai em `localDir`. Mesmo pipe por
 * descritor do envio. Devolve `{ logs, erro }`, como `transferir`.
 */
export function receber(alvo, comando, localDir) {
  const ssh = spawn("ssh", argsSsh(alvo, comando), { stdio: ["ignore", "pipe", "pipe"] })
  const tar = spawn("tar", ["xzf", "-", "-C", localDir], { stdio: [ssh.stdout, "ignore", "pipe"] })
  ssh.stdout.destroy()

  let sshErr = ""
  let tarErr = ""
  ssh.stderr.setEncoding("utf8")
  tar.stderr.setEncoding("utf8")
  ssh.stderr.on("data", (d) => { sshErr += d })
  tar.stderr.on("data", (d) => { tarErr += d })

  /**
   * Aqui o produtor é o ssh, e ele é checado primeiro: um tar remoto
   * que morreu no meio é a causa, e o erro do tar local é só o sintoma.
   */
  return Promise.all([esperar(ssh, "ssh"), esperar(tar, "tar")]).then(([doSsh, doTar]) => ({
    logs: `${sshErr}\n${tarErr}`.trim(),
    erro: doSsh ?? doTar,
  }))
}

// Stdout do comando remoto direto num descritor de arquivo já aberto.
export function baixar(alvo, comando, fd) {
  const ssh = spawn("ssh", argsSsh(alvo, comando), { stdio: ["ignore", fd, "pipe"] })
  let logs = ""
  ssh.stderr.setEncoding("utf8")
  ssh.stderr.on("data", (d) => { logs += d })
  return esperar(ssh, "ssh").then((erro) => ({ logs: logs.trim(), erro }))
}

/**
 * BatchMode evita travar num prompt de senha, e accept-new aceita host novo
 * mas ainda recusa chave trocada. O comando remoto vai como um argumento só.
 */
function argsSsh(alvo, comando) {
  return [
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-p", String(alvo.port),
    `${alvo.user}@${alvo.host}`,
    comando,
  ]
}

/**
 * Espera um processo. Resolve com `null` em sucesso, ou com uma mensagem
 * quando falhou ou nem chegou a existir (binário fora do PATH).
 */
function esperar(proc, nome) {
  return new Promise((resolve) => {
    proc.on("error", (e) => resolve(`${nome}: ${e.message}`))
    proc.on("close", (code, signal) => {
      if (signal) return resolve(`${nome}: terminado por ${signal}`)
      resolve(code === 0 ? null : `${nome}: saiu com ${code}`)
    })
  })
}

// Protege o caminho para o shell remoto: o ssh junta os argumentos numa string.
function aspasParaShellRemoto(s) {
  return `'${s.split("'").join(`'\\''`)}'`
}

/**
 * Por que não sobrou nada, na forma que o `cloudez-sync` já usa.
 *
 * A distinção não é cosmética: "está vazio" manda refazer o build, e "um padrão
 * excluiu tudo" manda corrigir o padrão. Errar aqui custa uma investigação no
 * lugar errado.
 */
function mensagemVazio(dir, ignore) {
  const fontes = ignore?.sources ?? []
  const porque =
    fontes.length > 0
      ? `os padrões de ${fontes.join(" e ")} excluíram tudo`
      : "só há `.git`, que o deploy sempre exclui"
  return `Diretório '${dir}' não tem nenhum arquivo publicável: ${porque}.`
}
