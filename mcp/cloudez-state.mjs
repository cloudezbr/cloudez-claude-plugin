// cloudez-mcp 0.2.30 — gerado por 'npm run bundle'. Nao edite.

// src/deploy-state.ts
import { mkdirSync, readdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

// src/errors.ts
var ToolError = class extends Error {
  body;
  /**
   * Corpo cru do 400, só para quem lançou poder reconhecer um campo específico (ver cloud.ts).
   * Nunca sai daqui: errorResult() só serializa `body`, então isto não vaza para o modelo.
   */
  rawBody;
  constructor(code, message, opts = {}) {
    super(message);
    this.name = "ToolError";
    this.body = {
      error: {
        code,
        message,
        retryable: opts.retryable ?? false,
        ...opts.hint ? { hint: opts.hint } : {}
      }
    };
    this.rawBody = opts.rawBody;
  }
};

// src/deploy-state.ts
function stateDir() {
  return process.env.CLOUDEZ_STATE_DIR || join(homedir(), ".cloudez", "state");
}
function stateDirLegado() {
  return ".cloudez/state";
}
function statePath(deployId) {
  return join(stateDir(), `${deployId}.json`);
}
function loadState(deployId) {
  for (const dir of [stateDir(), stateDirLegado()]) {
    try {
      return JSON.parse(readFileSync(join(dir, `${deployId}.json`), "utf8"));
    } catch {
    }
  }
  throw new ToolError("deploy_not_found", `deploy_id '${deployId}' desconhecido. Chame cloudez_begin_deploy primeiro.`);
}
function saveState(state) {
  const file = statePath(state.deploy_id);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(state, null, 2));
  return state;
}

// src/pull-state.ts
import { mkdirSync as mkdirSync2, readFileSync as readFileSync2, writeFileSync as writeFileSync2 } from "node:fs";
import { join as join2 } from "node:path";
var PULL_ID = /^pull_[0-9a-f]{8}$/;
function loadPullState(pullId) {
  if (!PULL_ID.test(pullId)) throw desconhecido(pullId);
  try {
    return JSON.parse(readFileSync2(join2(stateDir(), `${pullId}.json`), "utf8"));
  } catch {
    throw desconhecido(pullId);
  }
}
function desconhecido(pullId) {
  return new ToolError("pull_not_found", `pull_id '${pullId}' desconhecido.`, {
    hint: "Chame cloudez_begin_pull e use o pull_id que ele devolver."
  });
}
export {
  loadPullState,
  loadState,
  saveState,
  statePath
};
