// opencode plugin: 1-hour prompt cache for Claude Opus 5.5 on the SLAC gateway.
//
// opencode's ProviderTransform.applyCaching hard-codes cache_control
// {type:"ephemeral"} with no ttl (1.2.10 through upstream 1.19.1), so every
// cached prefix expires after 5 minutes. The bundled @ai-sdk/anthropic passes a
// ttl through, and the SLAC gateway honours ttl "1h" without any anthropic-beta
// header (measured 2026-10-15). This plugin fills the gap:
//
//   - `config` hook (runs once at startup, before providers load) gives the
//     `slac` provider a fetch that stamps ttl onto unstamped cache markers in
//     POST /messages bodies for the listed models.
//   - `chat.headers` tags each slac request with its session kind, so only main
//     sessions get the hour and subagents stay on 5 minutes -- the same split as
//     Claude Code's promptCacheTtl. The fetch strips the tag before sending.
//
// Any error leaves the request exactly as opencode built it.
//
// Per-user env overrides:
//   OPENCODE_CACHE_TTL=off       disable stamping (rollback for one user)
//   OPENCODE_CACHE_TTL_MODELS    comma list of wire model ids, "*" = all slac models
//   OPENCODE_CACHE_TTL_SCOPE=all stamp subagent sessions too
//   OPENCODE_CACHE_TTL_LOG       JSONL path: markers stamped + response cache usage
import { appendFileSync } from "node:fs"

const PROVIDER = "slac"
const TTL = process.env.OPENCODE_CACHE_TTL ?? "1h"
const MODELS = (process.env.OPENCODE_CACHE_TTL_MODELS ?? "us.anthropic.claude-opus-5-5").split(",").filter(Boolean)
const SCOPE = process.env.OPENCODE_CACHE_TTL_SCOPE ?? "main"
const LOG = process.env.OPENCODE_CACHE_TTL_LOG
const TAG = "x-opencode-cache-ttl-session"
const WRAPPED = Symbol.for("opencode-cache-ttl.wrapped")

function takeTag(init) {
  const h = init?.headers
  if (!h) return { init }
  if (h instanceof Headers) {
    const tag = h.get(TAG)
    h.delete(TAG)
    return { tag, init }
  }
  let tag
  const headers = {}
  for (const [k, v] of Object.entries(h)) {
    if (k.toLowerCase() === TAG) tag = v
    else headers[k] = v
  }
  return { tag, init: { ...init, headers } }
}

function stamp(body, ttl) {
  let stamped = 0
  let markers = 0
  const visit = (blocks) => {
    if (!Array.isArray(blocks)) return
    for (const b of blocks) {
      const cc = b?.cache_control
      if (cc?.type !== "ephemeral") continue
      markers++
      if (!cc.ttl) {
        cc.ttl = ttl
        stamped++
      }
    }
  }
  visit(body.system)
  visit(body.tools)
  for (const m of body.messages ?? []) visit(m.content)
  return { markers, stamped }
}

function logUsage(res, entry) {
  res
    .clone()
    .text()
    .then((text) => {
      let usage = {}
      if (text.trimStart().startsWith("{")) {
        usage = JSON.parse(text).usage ?? {}
      } else {
        for (const line of text.split("\n")) {
          if (!line.startsWith("data: ")) continue
          const ev = JSON.parse(line.slice(6))
          if (ev.type === "message_start") usage = { ...usage, ...ev.message?.usage }
          if (ev.type === "message_delta") usage = { ...usage, ...ev.usage }
        }
      }
      appendFileSync(LOG, JSON.stringify({ ...entry, status: res.status, usage }) + "\n")
    })
    .catch(() => {})
}

export const CacheTtlPlugin = async ({ client }) => {
  const kinds = new Map() // sessionID -> "main" | "sub" | "unknown"
  const sessionKind = async (sessionID) => {
    if (!kinds.has(sessionID)) {
      const res = await client.session.get({ path: { id: sessionID } }).catch(() => undefined)
      kinds.set(sessionID, res?.data?.parentID ? "sub" : res?.data ? "main" : "unknown")
    }
    return kinds.get(sessionID)
  }

  return {
    "chat.headers": async (input, output) => {
      if (input?.model?.providerID !== PROVIDER || !output?.headers) return
      try {
        output.headers[TAG] = await sessionKind(input.sessionID)
      } catch {}
    },
    config: async (cfg) => {
      const options = cfg.provider?.[PROVIDER]?.options
      if (!options || options.fetch?.[WRAPPED]) return
      const inner = options.fetch
      const wrapped = async (input, init) => {
        let entry
        try {
          const taken = takeTag(init)
          init = taken.init
          const url = typeof input === "string" ? input : (input?.href ?? input?.url ?? "")
          const wanted = TTL !== "off" && (SCOPE === "all" || taken.tag === "main")
          if (init?.method === "POST" && typeof init.body === "string" && url.endsWith("/messages")) {
            const body = JSON.parse(init.body)
            if (MODELS.includes("*") || MODELS.includes(body.model)) {
              const counts = wanted ? stamp(body, TTL) : { markers: -1, stamped: 0 }
              if (counts.stamped) init = { ...init, body: JSON.stringify(body) }
              entry = { ts: new Date().toISOString(), model: body.model, session: taken.tag, ttl: wanted ? TTL : "default", ...counts }
            }
          }
        } catch {}
        const res = await (inner ?? fetch)(input, init)
        if (LOG && entry) logUsage(res, entry)
        return res
      }
      wrapped[WRAPPED] = true
      options.fetch = wrapped
    },
  }
}
