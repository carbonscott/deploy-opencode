#!/usr/bin/env bash
# Re-checks for the three FAILs of proof.sh's first pass, after reading their evidence:
#   A4  the old function hit the 401 retry loop (the client home exports the token),
#       so the repo-pin effect never showed. Redo in a home without the token.
#   E1  grading typo: grep looked for "dir ok=True", the read-back prints "DIR ok=True".
#       Re-run the read-back live and grade it correctly.
#   H1  the gateway answered the identical test prompt from its response cache in
#       under 1 s, so VERIFY_TIMEOUT=1 could not fire. Redo against a gateway that
#       never answers: a local listener that accepts TCP and never completes TLS,
#       so no request (and no key) is ever sent to it.
set -u
P=/sdf/scratch/users/c/cwang31/lcls-proof; REPO=$P/repo; R=$P/results
LIVE_INST=/sdf/group/lcls/ds/dm/apps/dev/claude/install-claude-lcls.sh
NEW_INST=$REPO/claude/install-claude-lcls.sh
export CLAUDE_LCLS_LAUNCHER=$REPO/claude/claude-lcls
export CLAUDE_LCLS_SETTINGS=$REPO/claude/shared-settings.json
W=$(cat "$R/workdir"); H1=$W/client; PIN=$W/repo-pins-opus5

chapter() { printf '%s\t%s\n' "$(date +%s.%N)" "$1" >> "$R/chapters.tsv"; printf '\n\033[1;36m━━━━ %s ━━━━ %s\033[0m\n' "$1" "$(date '+%H:%M:%S %Z')"; }
say() { printf '\033[2m# %s\033[0m\n' "$*"; }
stamp() { local l; while IFS= read -r l; do printf '\033[2m%(%H:%M:%S)T\033[0m │ %s\n' -1 "$l"; printf '%s\t%s\n' "$(date +%s.%N)" "$l" >> "$1"; done; }
check() { printf '%s\t%s\t%s\t%s\t%s\n' "$@" >> "$R/checks.tsv"; local c=32; [ "$5" = FAIL ] && c=31
  printf '  \033[1;%sm%-4s\033[0m \033[1m%s\033[0m %s\n       expected: %s\n       measured: %s\n' "$c" "$5" "$1" "$2" "$3" "$4"; }
verdict() { if eval "$1"; then echo PASS; else echo FAIL; fi; }
span() { awk -F'\t' -v a="$2" -v b="$3" 'index($2,a)&&!s{s=$1} s&&index($2,b){printf "%.1f", $1-s; exit}' "$1"; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }
newhome() { local h=$W/$1; mkdir -p "$h/gnupg"; chmod 700 "$h" "$h/gnupg"; touch "$h/.bashrc" "$h/.zshrc"; printf '%s\n' "$h"; }
inst() { local h=$1 f=$2 log=$3; shift 3; : > "$log"
  ( cd /tmp && env "$@" HOME="$h" GNUPGHOME="$h/gnupg" bash "$f" </dev/null 2>&1 ) | stamp "$log"; return "${PIPESTATUS[0]}"; }
cl() { local h=$1 d=$2 out=$3; shift 3
  ( cd "$d" && env "$@" HOME="$h" timeout "${CL_TIMEOUT:-120}" bash -c \
      'source ~/.bashrc; claude-lcls -p "Reply with exactly: PONG-$RANDOM" --output-format json' </dev/null >"$out.json" 2>"$out.err" )
  python3 -I -c 'import json,sys
s=open(sys.argv[1]).read()
try:
  d=json.loads(s); print("%s|%s|%s" % (",".join(d.get("modelUsage",{})) or "-", d.get("is_error"), str(d.get("result"))[:60]))
except Exception: print("-|no-answer|%s" % (s[:60] or "(empty)"))' "$out.json"; }

chapter "R. Re-checks of A4, E1, H1 after reading their evidence"

say "A4 again: the OLD function in a home WITHOUT the token, inside the repo that pins Opus 5"
H4=$(newhome old-clean)
inst "$H4" "$LIVE_INST" "$R/R-A4-install.log" -u ANTHROPIC_AUTH_TOKEN; rc=$?
say "live installer, clean shell: exit $rc"
o=$(cl "$H4" "$PIN" "$R/R-A4" -u ANTHROPIC_AUTH_TOKEN)
check A4r "old function inside the repo that pins opus to Opus 5 (no token)" \
  "us.anthropic.claude-opus-5 (repo overrides claude-lcls)" "$o" \
  "$(verdict '[[ $o == "us.anthropic.claude-opus-5|False|"* ]]')"

say "E1 again: read the running session from outside, graded case-correctly"
( cd /tmp && HOME="$H1" bash -c 'source ~/.bashrc; claude-lcls -p "Use the Bash tool to run: sleep 12. Then reply with exactly: slept" --allowedTools "Bash(sleep:*)" --output-format json' \
    </dev/null >"$R/R-E1.json" 2>"$R/R-E1.err" ) &
bg=$!; pid=""
for _ in $(seq 1 40); do pid=$(pgrep -u "$USER" -n -f -- "--settings $CLAUDE_LCLS_SETTINGS" || true); [ -n "$pid" ] && break; sleep 0.5; done
say "parent shell: ANTHROPIC_AUTH_TOKEN set=$( [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] && echo yes || echo no ); session pid=$pid"
python3 -I - "${pid:-0}" "$H1" "$CLAUDE_LCLS_SETTINGS" > "$R/R-E1.readback" <<'PY'
import sys
pid, home, shared = sys.argv[1:4]
env = dict(kv.split("=", 1) for kv in open("/proc/%s/environ" % pid).read().split("\0") if "=" in kv)
argv = open("/proc/%s/cmdline" % pid).read().split("\0")
print("pid=%s exe=%s" % (pid, argv[0]))
print("ANTHROPIC_AUTH_TOKEN present=%s" % ("ANTHROPIC_AUTH_TOKEN" in env))
print("ANTHROPIC_/CLAUDE_CODE_ names=%s" % sorted(k for k in env if k.startswith(("ANTHROPIC_", "CLAUDE_CODE_"))))
print("CLAUDE_CONFIG_DIR ok=%s" % (env.get("CLAUDE_CONFIG_DIR") == home + "/.claude-lcls"))
print("PATH first=%s" % env.get("PATH", "").split(":")[0])
print("argv has --settings shared=%s" % (["--settings", shared] == argv[1:3]))
PY
wait "$bg"; sed 's/^/       /' "$R/R-E1.readback"
n=$(grep -c -e 'ANTHROPIC_AUTH_TOKEN present=False' -e 'CLAUDE_CONFIG_DIR ok=True' -e 'settings shared=True' -e 'PATH first=/sdf/group/lcls/ds/dm/apps/dev/bin$' "$R/R-E1.readback")
check E1r "/proc of the running session, graded with the exact strings" \
  "4 of 4: no token, config dir, PATH head, --settings" \
  "$n of 4; reply: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result"))' "$R/R-E1.json" 2>/dev/null)" \
  "$(verdict '[ "$n" = 4 ]')"

say "H1 again: a gateway that never answers (accepts TCP, never completes TLS; nothing is sent)"
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
port=$(cat "$W/blackhole.port")
sed "s|https://ai-api.slac.stanford.edu|https://127.0.0.1:$port|" "$CLAUDE_LCLS_SETTINGS" > "$W/blackhole-settings.json"
say "shared settings copy pointing at https://127.0.0.1:$port (listener pid $bh)"
H5=$(newhome timeout)
inst "$H5" "$NEW_INST" "$R/R-H1.log" -u ANTHROPIC_AUTH_TOKEN CLAUDE_LCLS_SETTINGS="$W/blackhole-settings.json" VERIFY_TIMEOUT=10; rc=$?
kill "$bh" 2>/dev/null
v=$(span "$R/R-H1.log" "sending one test request" "verification FAILED")
check H1r "VERIFY_TIMEOUT=10 against a gateway that never answers" \
  "exit 1 with '(no answer within 10s)' about 10 s after the test starts" \
  "exit $rc; failed after ${v:-n/a} s; message: $(has "$R/R-H1.log" "(no answer within 10s)")" \
  "$(verdict '[ "$rc" = 1 ] && grep -qF "(no answer within 10s)" "$R/R-H1.log" && awk -v v="${v:-99}" "BEGIN{exit !(v >= 9 && v < 15)}"')"

chapter "Summary after re-checks"
awk -F'\t' '{n[$5]++; printf "  %-4s %-4s %s\n", $5, $1, $2} END{printf "\n  "; for (k in n) printf "%s %d   ", k, n[k]; print ""}' "$R/checks.tsv"
say "first-pass FAILs A4, E1, H1 were test-design errors; see A4r, E1r, H1r"
