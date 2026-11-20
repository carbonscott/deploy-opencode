#!/usr/bin/env bash
# End-to-end proof for deploy-opencode branch fix/claude-lcls-launcher.
#
# Run it from a shell that has the client's problem, exactly as reported:
#     export ANTHROPIC_AUTH_TOKEN=yourKeyHere
#     bash proof.sh
#
# Every case runs in a throwaway HOME under node-local /tmp (mode 700) with its
# own GNUPGHOME, so nobody's real ~/.claude-lcls, rc files, pass store or GnuPG
# agent is touched. The branch's launcher and shared settings are used from the
# clone below, not from the live deployment (they are not published yet).
# Expected values are written into each check below BEFORE it runs.
set -u

P=/sdf/scratch/users/c/cwang31/lcls-proof
REPO=$P/repo
LIVE_INST=/sdf/group/lcls/ds/dm/apps/dev/claude/install-claude-lcls.sh
NEW_INST=$REPO/claude/install-claude-lcls.sh
BIN=/sdf/group/lcls/ds/dm/apps/dev/claude/bin/current
export CLAUDE_LCLS_LAUNCHER=$REPO/claude/claude-lcls
export CLAUDE_LCLS_SETTINGS=$REPO/claude/shared-settings.json
R=${PROOF_RESULTS:-$P/results}
mkdir -p "$R"; : > "$R/checks.tsv"; : > "$R/chapters.tsv"
W=$(mktemp -d /tmp/lcls-proof.XXXXXX); chmod 700 "$W"; echo "$W" > "$R/workdir"

# ── helpers ───────────────────────────────────────────────────────────────
chapter() {
  printf '%s\t%s\n' "$(date +%s.%N)" "$1" >> "$R/chapters.tsv"
  printf '\n\033[1;36m━━━━ %s ━━━━ %s\033[0m\n' "$1" "$(date '+%H:%M:%S %Z')"
}
say() { printf '\033[2m# %s\033[0m\n' "$*"; }
# Prefix every output line with the wall clock, and keep an epoch log.
stamp() {
  local l
  while IFS= read -r l; do
    printf '\033[2m%(%H:%M:%S)T\033[0m │ %s\n' -1 "$l"
    printf '%s\t%s\n' "$(date +%s.%N)" "$l" >> "$1"
  done
}
check() {  # id, what, expected, measured, verdict
  printf '%s\t%s\t%s\t%s\t%s\n' "$@" >> "$R/checks.tsv"
  local c=32; [ "$5" = FAIL ] && c=31; [ "$5" = WARN ] && c=33
  printf '  \033[1;%sm%-4s\033[0m \033[1m%s\033[0m %s\n       expected: %s\n       measured: %s\n' "$c" "$5" "$1" "$2" "$3" "$4"
}
verdict() { if eval "$1"; then echo PASS; else echo FAIL; fi; }
gap()  { awk -F'\t' 'NR>1{d=$1-p; if(d>m)m=d} {p=$1} END{printf "%.0f", m}' "$1"; }
span() { awk -F'\t' -v a="$2" -v b="$3" 'index($2,a)&&!s{s=$1} s&&index($2,b){printf "%.1f", $1-s; exit}' "$1"; }
has()  { grep -qF -- "$2" "$1" && echo yes || echo no; }
newhome() {
  local h=$W/$1
  mkdir -p "$h/gnupg"; chmod 700 "$h" "$h/gnupg"; touch "$h/.bashrc" "$h/.zshrc"
  printf '%s\n' "$h"
}
# Run an installer the way the client did, but unattended (no key pasted).
# Leading args are passed to env(1), so -u NAME and NAME=value both work.
inst() {
  local h=$1 f=$2 log=$3; shift 3
  : > "$log"
  ( cd /tmp && env "$@" HOME="$h" GNUPGHOME="$h/gnupg" bash "$f" </dev/null 2>&1 ) | stamp "$log"
  return "${PIPESTATUS[0]}"
}
# One claude-lcls request through the user's own rc file, from directory $2.
# Prints: models|is_error|result. CL_TIMEOUT bounds it.
cl() {
  local h=$1 d=$2 out=$3; shift 3
  ( cd "$d" && env "$@" HOME="$h" timeout "${CL_TIMEOUT:-120}" bash -c \
      'source ~/.bashrc; claude-lcls -p "Reply with exactly: PONG-$RANDOM" --output-format json' \
      </dev/null >"$out.json" 2>"$out.err" )
  python3 -I - "$out.json" <<'PY'
import json, sys
s = open(sys.argv[1]).read()
try:
    d = json.loads(s)
    print("%s|%s|%s" % (",".join(d.get("modelUsage", {})) or "-", d.get("is_error"),
                        str(d.get("result"))[:60].replace("\n", " ")))
except Exception:
    print("-|no-answer|%s" % (s[:60].replace("\n", " ") or "(empty)"))
PY
}

# ── provenance ────────────────────────────────────────────────────────────
chapter "0. Setup and provenance"
say "host $(hostname)  user $USER  $(date '+%Y-%m-%d %H:%M:%S %Z')"
say "branch commit $(git -C "$REPO" rev-parse --short HEAD): $(git -C "$REPO" log -1 --format=%s)"
say "shared binary $(readlink "$BIN") -> $("$BIN" --version)"
say "live installer md5 $(md5sum "$LIVE_INST" | cut -c1-8)   branch installer md5 $(md5sum "$NEW_INST" | cut -c1-8)"
say "ANTHROPIC_* names in this shell: $(compgen -e | grep '^ANTHROPIC_' | tr '\n' ' ')"
say "ANTHROPIC_AUTH_TOKEN starts with '${ANTHROPIC_AUTH_TOKEN:0:4}' (the client's 401 said Received=your****Here)"

H1=$(newhome client)
echo 'export ANTHROPIC_AUTH_TOKEN=yourKeyHere   # what the client had' >> "$H1/.bashrc"
PIN=$W/repo-pins-opus5; mkdir -p "$PIN/.claude"
echo '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"us.anthropic.claude-opus-5"}}' > "$PIN/.claude/settings.json"
say "client home: $H1 (its .bashrc exports the placeholder too)"
say "a repo with .claude/settings.json pinning opus to Opus 5: $PIN"

# ── A. before ─────────────────────────────────────────────────────────────
chapter "A. BEFORE: live installer in the client's shell"
inst "$H1" "$LIVE_INST" "$R/A.log"; rc=$?
g=$(gap "$R/A.log"); r401=$(has "$R/A.log" "Received=your****Here")
check A1 "live installer, poisoned shell" \
  "silent >=150 s after the uv line, then exit 1 with the 401 (bug reproduced)" \
  "exit $rc; longest silence ${g} s; 401 your****Here in output: $r401" \
  "$(verdict '[ "$rc" = 1 ] && [ "$g" -ge 150 ] && [ "$r401" = yes ]')"

chapter "A'. BEFORE: everyday claude-lcls with the old function"
o=$(CLAUDE_CODE_MAX_RETRIES=0 cl "$H1" /tmp "$R/A2")
check A2 "claude-lcls -p, poisoned shell (retries capped to show it fast)" \
  "is_error True with the 401 (bug reproduced)" "$o" \
  "$(verdict '[[ $o == *"|True|"*401* ]]')"
o=$(CL_TIMEOUT=25 cl "$H1" /tmp "$R/A3" CLAUDE_CODE_USE_BEDROCK=1)
check A3 "claude-lcls -p with CLAUDE_CODE_USE_BEDROCK=1 from another tool" \
  "no answer within 25 s (bug reproduced)" "$o" \
  "$(verdict '[[ $o == *no-answer* || $o == *"|True|"* ]]')"
say "A4 needs a home WITHOUT the token, or the 401 retry loop hides the repo pin"
H4=$(newhome old-clean)
inst "$H4" "$LIVE_INST" "$R/A4-install.log" -u ANTHROPIC_AUTH_TOKEN >/dev/null
o=$(cl "$H4" "$PIN" "$R/A4" -u ANTHROPIC_AUTH_TOKEN)
check A4 "old function inside a repo that pins opus to Opus 5 (no token)" \
  "us.anthropic.claude-opus-5 (repo overrides claude-lcls)" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5|False|"* ]]')"

# ── B. after ──────────────────────────────────────────────────────────────
chapter "B. AFTER: branch installer, same home, same shell"
inst "$H1" "$NEW_INST" "$R/B.log"; rc=$?
v=$(span "$R/B.log" "sending one test request" "live completion succeeded"); g=$(gap "$R/B.log")
check B1 "branch installer, poisoned shell" \
  "exit 0 and 'live completion succeeded'" \
  "exit $rc; succeeded: $(has "$R/B.log" "live completion succeeded")" \
  "$(verdict '[ "$rc" = 0 ] && grep -qF "live completion succeeded" "$R/B.log"')"
check B2 "verification time; longest silence" "verification < 20 s; no silence > 20 s" \
  "verification ${v:-n/a} s; longest silence ${g} s" \
  "$(verdict '[ -n "$v" ] && awk -v v="$v" "BEGIN{exit !(v < 20)}" && [ "$g" -le 20 ]')"
check B3 "preflight names where the variable is set" \
  "warning naming ~/.bashrc:<line>" \
  "$(grep -oE 'it is set at:[^-]*' "$R/B.log" | head -1)" \
  "$(verdict 'grep -qE "it is set at: ~/.bashrc:[0-9]+" "$R/B.log"')"
nb=$(grep -c '^# >>> claude-lcls >>>' "$H1/.bashrc"); nz=$(grep -c '^# >>> claude-lcls >>>' "$H1/.zshrc")
nl=$(grep -cF "\"$CLAUDE_LCLS_LAUNCHER\" \"\$@\"" "$H1/.bashrc")
check B4 "rc files now call the shared launcher" \
  "exactly one block in .bashrc and .zshrc, calling the launcher" \
  ".bashrc blocks $nb, .zshrc blocks $nz, launcher calls in .bashrc $nl" \
  "$(verdict '[ "$nb" = 1 ] && [ "$nz" = 1 ] && [ "$nl" = 1 ]')"

# ── C. after, everyday use ────────────────────────────────────────────────
chapter "C. AFTER: everyday claude-lcls, other software's settings"
o=$(cl "$H1" /tmp "$R/C1")
check C1 "claude-lcls -p, poisoned shell" "us.anthropic.claude-opus-5-5, is_error False" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5-5|False|"* ]]')"
check C1b "stderr tells the user once" "one 'ignoring ANTHROPIC_AUTH_TOKEN' line" \
  "$(grep -c 'ignoring ANTHROPIC_AUTH_TOKEN' "$R/C1.err") line(s)" \
  "$(verdict '[ "$(grep -c "ignoring ANTHROPIC_AUTH_TOKEN" "$R/C1.err")" = 1 ]')"
o=$(CL_TIMEOUT=60 cl "$H1" /tmp "$R/C2" CLAUDE_CODE_USE_BEDROCK=1)
check C2 "with CLAUDE_CODE_USE_BEDROCK=1" "us.anthropic.claude-opus-5-5, is_error False" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5-5|False|"* ]]')"
o=$(cl "$H1" /tmp "$R/C3" ANTHROPIC_BASE_URL=https://127.0.0.1:9 ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-5)
check C3 "with a bogus ANTHROPIC_BASE_URL and an Opus 5 alias in the shell" \
  "us.anthropic.claude-opus-5-5, is_error False" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5-5|False|"* ]]')"
o=$(cl "$H1" "$PIN" "$R/C4")
check C4 "inside the repo that pins opus to Opus 5" "us.anthropic.claude-opus-5-5" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5-5|False|"* ]]')"
o=$(cl "$H1" /tmp "$R/C5" CLAUDE_LCLS_KEEP_ENV="ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_MAX_RETRIES" CLAUDE_CODE_MAX_RETRIES=0)
check C5 "opt-in: CLAUDE_LCLS_KEEP_ENV keeps the token on purpose" \
  "is_error True with the 401 (the opt-out is honoured)" "$o" \
  "$(verdict '[[ $o == *"|True|"*401* ]]')"

# ── D. next model move ────────────────────────────────────────────────────
chapter "D. The next model move needs no re-run"
say "simulate a stale settings.json: point opus/sonnet back at Opus 5 / Sonnet 5"
python3 -I - "$H1/.claude-lcls/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["env"]["ANTHROPIC_DEFAULT_OPUS_MODEL"] = "us.anthropic.claude-opus-5[1m]"
d["env"]["ANTHROPIC_DEFAULT_SONNET_MODEL"] = "us.anthropic.claude-sonnet-5[1m]"
json.dump(d, open(p, "w"), indent=2)
PY
o=$(cl "$H1" /tmp "$R/D1")
check D1 "plain claude-lcls with a stale settings.json" \
  "us.anthropic.claude-opus-5-5 (shared settings decide)" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5-5|False|"* ]]')"

# ── E. independent read-back ──────────────────────────────────────────────
chapter "E. Independent read-back: /proc, files, the key itself"
say "start a session that runs 'sleep 12', then read its process from outside"
( cd /tmp && HOME="$H1" bash -c 'source ~/.bashrc; claude-lcls -p "Use the Bash tool to run: sleep 12. Then reply with exactly: slept" --allowedTools "Bash(sleep:*)" --output-format json' \
    </dev/null >"$R/E1.json" 2>"$R/E1.err" ) &
bgpid=$!
pid=""; for _ in $(seq 1 40); do
  pid=$(pgrep -u "$USER" -n -f -- "--settings $CLAUDE_LCLS_SETTINGS" || true)
  [ -n "$pid" ] && break; sleep 0.5
done
python3 -I - "${pid:-0}" "$H1" "$CLAUDE_LCLS_SETTINGS" > "$R/E1.readback" <<'PY'
import sys
pid, home, shared = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    env = dict(kv.split("=", 1) for kv in open("/proc/%s/environ" % pid).read().split("\0") if "=" in kv)
    argv = open("/proc/%s/cmdline" % pid).read().split("\0")
except OSError as e:
    print("pid=%s unreadable: %s" % (pid, e)); sys.exit()
print("pid=%s exe=%s" % (pid, argv[0]))
print("ANTHROPIC_AUTH_TOKEN present=%s" % ("ANTHROPIC_AUTH_TOKEN" in env))
print("ANTHROPIC_/CLAUDE_CODE_ names=%s" % sorted(k for k in env if k.startswith(("ANTHROPIC_", "CLAUDE_CODE_"))))
print("CLAUDE_CONFIG_DIR ok=%s" % (env.get("CLAUDE_CONFIG_DIR") == home + "/.claude-lcls"))
print("PATH first=%s" % env.get("PATH", "").split(":")[0])
print("argv has --settings shared=%s" % (["--settings", shared] == argv[1:3]))
PY
wait "$bgpid"
sed 's/^/       /' "$R/E1.readback"
ok_e1=$(grep -c -e 'ANTHROPIC_AUTH_TOKEN present=False' -e 'CLAUDE_CONFIG_DIR ok=True' -e 'settings shared=True' -e 'PATH first=/sdf/group/lcls/ds/dm/apps/dev/bin$' "$R/E1.readback")
check E1 "/proc of the running session (poisoned parent shell)" \
  "no ANTHROPIC_AUTH_TOKEN; config dir, PATH head, --settings as designed" \
  "$ok_e1 of 4 properties hold; reply: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result"))' "$R/E1.json" 2>/dev/null)" \
  "$(verdict '[ "$ok_e1" = 4 ]')"
python3 -I - "$H1" "$CLAUDE_LCLS_SETTINGS" "$NEW_INST" > "$R/E2.readback" <<'PY'
import json, re, sys
home, shared, inst = sys.argv[1:4]
want = json.load(open(shared))["env"]
tmpl = open(inst).read()
bad = [k for k, v in want.items()
       if '"%s": "%s"' % (k, v) not in tmpl and not (k == "ANTHROPIC_BASE_URL" and v in tmpl)]
print("shared keys missing from installer template: %s" % (bad or "none"))
s = json.load(open(home + "/.claude-lcls/settings.json"))
print("apiKeyHelper ok=%s" % (s.get("apiKeyHelper") == "cat %s/.config/slac-ai/key.dat" % home))
for rc in (".bashrc", ".zshrc"):
    t = open(home + "/" + rc).read()
    print("%s begin=%d end=%d" % (rc, t.count("# >>> claude-lcls >>>"), t.count("# <<< claude-lcls <<<")))
PY
sed 's/^/       /' "$R/E2.readback"
check E2 "files on disk, parsed by a separate program" \
  "template carries every shared key; apiKeyHelper = own key file; one block per rc" \
  "$(tr '\n' ';' < "$R/E2.readback")" \
  "$(verdict 'grep -q "missing from installer template: none" "$R/E2.readback" && grep -q "apiKeyHelper ok=True" "$R/E2.readback" && [ "$(grep -c "begin=1 end=1" "$R/E2.readback")" = 2 ]')"
code=$(sed -n '1s/^/x-api-key: /p' "$H1/.config/slac-ai/key.dat" | curl -q -s -o /dev/null -m 15 -w '%{http_code}' -H @- https://ai-api.slac.stanford.edu/v1/models)
check E3 "the key file itself, with curl (no Claude Code)" "HTTP 200" "HTTP $code" \
  "$(verdict '[ "$code" = 200 ]')"

# ── F. fresh user ─────────────────────────────────────────────────────────
chapter "F. Fresh user, clean shell (no regression)"
H3=$(newhome fresh)
inst "$H3" "$NEW_INST" "$R/F.log" -u ANTHROPIC_AUTH_TOKEN; rc=$?
v=$(span "$R/F.log" "sending one test request" "live completion succeeded")
check F1 "branch installer, new user, nothing in the shell" \
  "exit 0, verification < 20 s, no variable warnings" \
  "exit $rc; verification ${v:-n/a} s; AUTH_TOKEN warning: $(has "$R/F.log" "ANTHROPIC_AUTH_TOKEN is set")" \
  "$(verdict '[ "$rc" = 0 ] && [ -n "$v" ] && awk -v v="$v" "BEGIN{exit !(v < 20)}" && ! grep -qF "ANTHROPIC_AUTH_TOKEN is set" "$R/F.log"')"

# ── G. pasted token fails fast ────────────────────────────────────────────
chapter "G. A token pasted into settings.json fails fast, with a hint"
say "the one place the launcher cannot reach: env.ANTHROPIC_AUTH_TOKEN inside settings.json"
python3 -I - "$H1/.claude-lcls/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["env"]["ANTHROPIC_AUTH_TOKEN"] = "yourKeyHere"
json.dump(d, open(p, "w"), indent=2)
PY
inst "$H1" "$NEW_INST" "$R/G.log"; rc=$?
v=$(span "$R/G.log" "sending one test request" "verification FAILED")
check G1 "branch installer with the token in settings.json" \
  "warning before the test; exit 1 within 15 s of starting it; hint names settings.json" \
  "exit $rc; failed after ${v:-n/a} s; warning: $(has "$R/G.log" "sets env.ANTHROPIC_AUTH_TOKEN"); hint: $(has "$R/G.log" "is being sent instead")" \
  "$(verdict '[ "$rc" = 1 ] && [ -n "$v" ] && awk -v v="$v" "BEGIN{exit !(v < 15)}" && grep -qF "sets env.ANTHROPIC_AUTH_TOKEN" "$R/G.log" && grep -qF "is being sent instead" "$R/G.log"')"

say "undo G: take the pasted token back out of settings.json"
python3 -I - "$H1/.claude-lcls/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["env"].pop("ANTHROPIC_AUTH_TOKEN", None)
json.dump(d, open(p, "w"), indent=2)
PY

# ── H. timeout backstop ───────────────────────────────────────────────────
chapter "H. Timeout backstop"
say "a gateway that never answers: accepts TCP, never completes TLS, so nothing is sent to it"
python3 -I -c '
import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0)); s.listen(16); print(s.getsockname()[1]); sys.stdout.flush()
held = []; s.settimeout(1); end = time.time() + 90
while time.time() < end:
    try: held.append(s.accept()[0])
    except socket.timeout: pass
' > "$W/blackhole.port" &
bh=$!; for _ in $(seq 1 20); do [ -s "$W/blackhole.port" ] && break; sleep 0.2; done
sed "s|https://ai-api.slac.stanford.edu|https://127.0.0.1:$(cat "$W/blackhole.port")|" "$CLAUDE_LCLS_SETTINGS" > "$W/blackhole-settings.json"
inst "$H3" "$NEW_INST" "$R/H.log" -u ANTHROPIC_AUTH_TOKEN CLAUDE_LCLS_SETTINGS="$W/blackhole-settings.json" VERIFY_TIMEOUT=10; rc=$?
kill "$bh" 2>/dev/null
v=$(span "$R/H.log" "sending one test request" "verification FAILED")
check H1 "VERIFY_TIMEOUT=10 against a gateway that never answers" \
  "exit 1 with '(no answer within 10s)' about 10 s after the test starts" \
  "exit $rc; failed after ${v:-n/a} s; message: $(has "$R/H.log" "(no answer within 10s)")" \
  "$(verdict '[ "$rc" = 1 ] && grep -qF "(no answer within 10s)" "$R/H.log" && awk -v v="${v:-99}" "BEGIN{exit !(v >= 9 && v < 15)}"')"

# ── J. publish tool ───────────────────────────────────────────────────────
chapter "J. Publish tool, rehearsed against a mock deploy root"
M=$W/mock; mkdir -p "$M/claude/bin/versions"
echo '{"active": null, "published": []}' > "$M/claude/bin/VERSIONS.json"
PT=$REPO/tools/claude-binary/scripts/publish-claude-binary.sh
penv=(env CLAUDE_BINARY_SRC_REPO="$REPO" DEPLOY_ROOT="$M" CLAUDE_TREE_ROOT="$M/claude" CLAUDE_BIN_ROOT="$M/claude/bin" INSTALLER_REF=HEAD)
"${penv[@]}" bash "$PT" installer --yes-really-publish 2>&1 | stamp "$R/J1.log"
modes=$(stat -c '%n %a %G' "$M/claude/shared-settings.json" "$M/claude/bin/claude-lcls" "$M/claude/install-claude-lcls.sh" | sed "s|$M/||")
mg=$(echo "$modes" | awk '{printf "%s %s ", $2, $3}')
check J1 "installer mode publishes three files" \
  "shared-settings.json 644, bin/claude-lcls 755, install-claude-lcls.sh 755, all ps-users" \
  "$(echo "$modes" | tr '\n' ';')" \
  "$(verdict '[ "$mg" = "644 ps-users 755 ps-users 755 ps-users " ]')"
"${penv[@]}" bash "$PT" verify 2>&1 | sed -n '/claude\/shared-settings.json$/,$p' | stamp "$R/J2.log"
same=$(grep -c ' same' "$R/J2.log"); diffs=$(grep -c 'differs from' "$R/J2.log")
check J2 "verify: three files vs HEAD, shared settings vs template" \
  "8 keys 'same', no 'differs'" "$same same, $diffs differs" \
  "$(verdict '[ "$same" = 8 ] && [ "$diffs" = 0 ]')"
say "now break it: change the opus id in the published shared settings"
sed -i 's/claude-opus-5-5\[1m\]/claude-opus-5[1m]/' "$M/claude/shared-settings.json"
"${penv[@]}" bash "$PT" verify 2>&1 | sed -n '/claude\/shared-settings.json$/,$p' | stamp "$R/J3.log"
check J3 "verify catches a drifted shared settings file" \
  "FAIL for ANTHROPIC_DEFAULT_OPUS_MODEL and 'differs from HEAD'" \
  "opus FAIL: $(has "$R/J3.log" "ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-5[1m]"); differs: $(has "$R/J3.log" "shared-settings.json differs from HEAD")" \
  "$(verdict 'grep -qF "ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-5[1m]" "$R/J3.log" && grep -qF "shared-settings.json differs from HEAD" "$R/J3.log"')"

# ── summary ───────────────────────────────────────────────────────────────
chapter "Summary"
awk -F'\t' '{n[$5]++; printf "  %-4s %-4s %s\n", $5, $1, $2} END{printf "\n  "; for (k in n) printf "%s %d   ", k, n[k]; print ""}' "$R/checks.tsv"
say "workdir kept for the interactive chapter and cleanup: $W"
