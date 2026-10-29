// Test-only opencode plugin: append the provider options of every LLM call
// (agent, model, options -- effort/thinking/reasoningEffort live there) to the
// JSONL file named by EFFORT_PROBE_LOG. Nothing is logged when it is unset.
// Never deploy it into dev/opencode/plugin/. Load it for one run instead:
//   APPTAINERENV_OPENCODE_CONFIG_CONTENT='{"plugin":["file:///abs/path/effort-probe.js"]}' \
//   APPTAINERENV_EFFORT_PROBE_LOG=$PWD/effort.jsonl opencode-sandbox --incognito -- run "Reply OK"
// The file must sit somewhere the sandbox can read (e.g. under /sdf/data/lcls).
import { appendFileSync } from "node:fs"
const LOG = process.env.EFFORT_PROBE_LOG
export default async () => ({
  "chat.params": async (input, output) => {
    if (!LOG) return
    const agent = typeof input.agent === "string" ? input.agent : input.agent?.name
    appendFileSync(LOG, JSON.stringify({ agent, model: input.model?.id, options: output.options }) + "\n")
  },
})
