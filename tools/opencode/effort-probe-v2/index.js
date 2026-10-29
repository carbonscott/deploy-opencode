// Test-only opencode 2.x plugin: append the effort, thinking and cache fields
// of every outgoing model request body to the JSONL file named by
// EFFORT_PROBE_LOG. Logs nothing when it is unset. Never deploy it.
// 2.x plugins configured by path must be DIRECTORIES, so load this folder:
//   APPTAINERENV_OPENCODE_CONFIG_CONTENT='{"plugin":["/abs/path/effort-probe-v2"]}' \
//   APPTAINERENV_EFFORT_PROBE_LOG=$PWD/effort.jsonl \
//   OPENCODE_SANDBOX_VERSION=<2.x> opencode-sandbox --incognito -- run "Reply OK"
// For 1.x use ../effort-probe.js.
import { appendFileSync } from "node:fs"
const LOG = process.env.EFFORT_PROBE_LOG
export default {
  id: "lcls.effort-probe",
  async setup(ctx) {
    await ctx.session.hook("http.request", async (event) => {
      if (!LOG) return
      let body = {}
      try { body = await event.request.clone().json() } catch {}
      const text = JSON.stringify(body)
      appendFileSync(LOG, JSON.stringify({
        kind: event.kind,
        agent: typeof event.agent === "string" ? event.agent : (event.agent?.id ?? event.agent?.name),
        session: event.sessionID,
        model: body.model,
        effort: body.output_config?.effort,
        thinking: body.thinking,
        reasoning: body.reasoning,
        msg_effort_fields: (JSON.stringify(body.messages || []).match(/"effort"/g) || []).length,
        cache_ttls: [...new Set(text.match(/"ttl":"[^"]*"/g) || [])],
      }) + "\n")
    })
  },
}
