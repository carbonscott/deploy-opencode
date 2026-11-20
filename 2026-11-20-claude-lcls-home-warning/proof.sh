#!/bin/bash
# Proof for deploy-opencode PR #59: claude-lcls names a token in
# ~/.claude/settings*.json when it starts in the home folder.
#
#   NEW=<launcher under test> [OLD=<launcher before the change>] bash proof.sh <out-dir>
#
# Runs on S3DF as any ps-users member. Nothing real is used: a fresh fake HOME,
# a fake key ("fake-helper-key-0001", from apiKeyHelper), and the shared
# settings with the gateway URL pointed at a local listener that answers 401
# and logs which key arrived. Expected values are written into each check
# before it runs; checks.tsv holds expected, measured and verdict.
set -u
DEV=/sdf/group/lcls/ds/dm/apps/dev
NEW=${NEW:?set NEW to the launcher under test}
OLD=${OLD:-}
OUT=${1:?usage: NEW=... bash proof.sh <out-dir>}
mkdir -p "$OUT"
TSV=$OUT/checks.tsv
printf 'id\twhat\texpected\tmeasured\tverdict\n' > "$TSV"
pass=0; fail=0
check() {  # check <id> <what> <expected> <measured> <0|1>
    local v=FAIL; [ "$5" = 0 ] && v=PASS
    [ $v = PASS ] && pass=$((pass+1)) || fail=$((fail+1))
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$v" >> "$TSV"
    printf '%-4s %-4s %s | expected: %s | measured: %s\n' "$1" "$v" "$2" "$3" "$4"
}

T=$(mktemp -d /tmp/home-warning.XXXXXX)
H=$T/home
mkdir -p "$H/.claude-lcls" "$H/.claude" "$H/work"
ln -s "$H" "$T/homelink"
echo '{ "apiKeyHelper": "echo fake-helper-key-0001" }' > "$H/.claude-lcls/settings.json"

# Local stand-in for the gateway: 401 for every request, log the key it got.
PORT=$((30000 + RANDOM % 20000))
cat > "$T/listen.py" <<'EOF'
import http.server, sys, json
LOG = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('content-length') or 0))
        with open(LOG, 'a') as f:
            f.write("auth={}\n".format(self.headers.get('authorization')))
        body = json.dumps({"error": {"message": "local stand-in 401", "type": "auth_error"}}).encode()
        self.send_response(401); self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
EOF
python3 -I "$T/listen.py" "$PORT" "$T/req.log" & LP=$!
disown "$LP"   # no "Terminated" job notice when the trap stops it
trap 'kill $LP 2>/dev/null; rm -rf "$T"' EXIT
sleep 1
# The published shared settings, gateway URL swapped for the listener.
sed -E "s#(\"ANTHROPIC_BASE_URL\"[[:space:]]*:[[:space:]]*\")[^\"]*\"#\1http://127.0.0.1:$PORT\"#" \
    "$DEV/claude/shared-settings.json" > "$T/shared.json"

# The client's ~/.claude/settings.json, same shape and line numbers: a gateway
# setup for plain `claude` with the token placeholder on line 4.
client_settings() {
cat <<'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://ai-api.slac.stanford.edu",
    "ANTHROPIC_AUTH_TOKEN": "yourKeyHere",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "us.anthropic.claude-sonnet-5-5[1m]",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "us.anthropic.claude-fable-5-2[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "us.anthropic.claude-opus-5-5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "us.anthropic.claude-haiku-5-5"
  }
}
EOF
}

run() {  # run <id> <launcher> <dir> <args...>: clean env, fake HOME
    local id=$1 L=$2 dir=$3; shift 3
    : > "$T/req.log"
    ( cd "$dir" && env -i HOME="$H" PATH=/usr/bin:/bin USER="$USER" LANG=C.UTF-8 \
        CLAUDE_LCLS_SETTINGS="$T/shared.json" \
        CLAUDE_LCLS_KEEP_ENV=CLAUDE_CODE_MAX_RETRIES CLAUDE_CODE_MAX_RETRIES=0 \
        timeout 60 "$L" "$@" </dev/null >"$OUT/$id.out" 2>"$OUT/$id.err" )
    echo $? > "$OUT/$id.rc"
    cp "$T/req.log" "$OUT/$id.req"
}
nwarn() { grep -c 'sets ANTHROPIC_AUTH_TOKEN' "$OUT/$1.err"; }
sent()  { sed -n '1s/^auth=Bearer //p' "$OUT/$1.req"; }

echo "host $(hostname) | binary $("$DEV/claude/bin/current" --version) | NEW md5 $(md5sum < "$NEW" | cut -c1-8)${OLD:+ | OLD md5 $(md5sum < "$OLD" | cut -c1-8)}"

client_settings > "$H/.claude/settings.json"

if [ -n "$OLD" ]; then
    run B1 "$OLD" "$H" -p hi
    w=$(nwarn B1); k=$(sent B1)
    check B1 "BEFORE: old launcher, started in ~" "no warning; key sent yourKeyHere (the client's 401)" \
        "$w warning(s); key sent ${k:-none}" "$([ "$w" = 0 ] && [ "$k" = yourKeyHere ]; echo $?)"
fi

run A1 "$NEW" "$H" -p hi
w=$(nwarn A1); n=$(grep -c 'settings.json line 4 sets' "$OUT/A1.err")
check A1 "started in ~, token on line 4" "1 warning naming ~/.claude/settings.json line 4" \
    "$w warning(s), $n naming line 4" "$([ "$w" = 1 ] && [ "$n" = 1 ]; echo $?)"
k=$(sent A1)
check A2 "same run: behavior unchanged (warn only)" "key sent yourKeyHere" \
    "key sent ${k:-none}" "$([ "$k" = yourKeyHere ]; echo $?)"

run A3 "$NEW" "$H/work" -p hi
w=$(nwarn A3); k=$(sent A3)
check A3 "started in ~/work, same files" "no warning; key sent fake-helper-key-0001" \
    "$w warning(s); key sent ${k:-none}" "$([ "$w" = 0 ] && [ "$k" = fake-helper-key-0001 ]; echo $?)"

run A4 "$NEW" "$T/homelink" --version
w=$(nwarn A4)
check A4 "started in ~ through a symlink to it" "1 warning" "$w warning(s)" "$([ "$w" = 1 ]; echo $?)"

v=$("$DEV/claude/bin/current" --version)
o=$(cat "$OUT/A4.out"); rc=$(cat "$OUT/A4.rc")
check A5 "stdout untouched: --version from ~" "stdout '$v', exit 0" "stdout '$o', exit $rc" \
    "$([ "$o" = "$v" ] && [ "$rc" = 0 ]; echo $?)"

rm "$H/.claude/settings.json"
run A6 "$NEW" "$H" --version
w=$(nwarn A6)
check A6 "started in ~, no ~/.claude/settings.json" "no warning" "$w warning(s)" "$([ "$w" = 0 ]; echo $?)"

# The installer template's commented-out key must not trigger it.
cat > "$H/.claude/settings.json" <<'EOF'
{
  "apiKeyHelper": "cat /YOUR/HOME/.config/slac-ai/key.dat",
  "env": {
    "// ANTHROPIC_AUTH_TOKEN": "PASTE-YOUR-SLAC-API-KEY-HERE (only if you delete apiKeyHelper above)"
  }
}
EOF
run A7 "$NEW" "$H" --version
w=$(nwarn A7)
check A7 "started in ~, template's commented-out token key only" "no warning" "$w warning(s)" "$([ "$w" = 0 ]; echo $?)"
rm "$H/.claude/settings.json"

printf '{\n  "env": { "ANTHROPIC_AUTH_TOKEN": "yourKeyHere" }\n}\n' > "$H/.claude/settings.local.json"
run A8 "$NEW" "$H" --version
w=$(nwarn A8); n=$(grep -c 'settings.local.json line 2 sets' "$OUT/A8.err")
check A8 "started in ~, token in settings.local.json (line 2)" "1 warning naming settings.local.json line 2" \
    "$w warning(s), $n naming it" "$([ "$w" = 1 ] && [ "$n" = 1 ]; echo $?)"

bash -n "$NEW"; s=$?
check A9 "bash -n on the launcher" "exit 0" "exit $s" "$s"

echo "RESULT $pass PASS, $fail FAIL"
echo "$pass PASS, $fail FAIL" > "$OUT/result.txt"
