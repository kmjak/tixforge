#!/usr/bin/env bash
# Tests for json_get in scripts/lib.sh, the JSON reader of the guard hook.
#   1. fixed inputs and the values they must give (no jq needed)
#   2. random objects compared with jq, when jq is installed (CI has it, so
#      the awk of the CI runner is checked too)
#   3. long inputs finish in linear time
#
# Usage: bash tests/json-get.test.sh   (also run it with /bin/bash on macOS for 3.2)
set -u

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../scripts/lib.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0; section=""
ok() { pass=$((pass + 1)); }
ng() { fail=$((fail + 1)); printf 'FAIL  [%s] %s\n' "$section" "$1"; }

# get <path> <json>: json_get's output, trailing newlines kept.
get() { local v; v=$(printf '%s' "$2" | json_get "$1"; printf x); printf '%s' "${v%x}"; }
# check <path> <json> <want> [what]
check() {
  local got
  got=$(get "$1" "$2"; printf x); got=${got%x}
  if [ "$got" = "$3" ]; then ok; else ng "${4:-$2} ($1): want [$3], got [$got]"; fi
}

# --- 1. fixed inputs ---------------------------------------------------------

section="keys"
check cwd '{"cwd":"/a b/c","tool_name":"Bash"}' '/a b/c'
check tool_input.command '{"tool_name":"Bash","tool_input":{"command":"git push"}}' 'git push'
check tool_input.command '{"tool_input":{"description":"x"}}' ''
check tool_input.command '{"tool_input":{"command":1}}' ''
check tool_input.command '{"tool_input":{"command":null}}' ''
check tool_input.command '{"tool_input":{"command":["git push"]}}' ''
check tool_input.command '{"command":"top","tool_input":{"command":"in"}}' 'in'
check tool_input.command '{"x":{"command":"no"},"tool_input":{"command":"yes"}}' 'yes'
check tool_input.command '{"tool_input":{"a":[{"command":"no"}],"command":"yes"}}' 'yes'
check tool_input.command '{"tool_input":{"a":{"b":{"command":"no"}},"command":"yes"}}' 'yes'
check tool_input.command '{"tool_input":{"description":"\"command\":\"no\"","command":"yes"}}' 'yes'
check tool_input.command '{"tool_input":{"description":"{[\"x\"]}","command":"yes"}}' 'yes'
check tool_input.command '{"tool_input":[{"command":1},"rm"]}' ''
check tool_input.file_path '{"tool_input":{"edits":[{"file_path":"no"}],"file_path":"yes"}}' 'yes'
check cwd '{ "cwd" : "x" }' 'x'
check cwd "$(printf '{\n  "a": {\n    "cwd": "no"\n  },\n  "cwd"\n  : "yes"\n}')" 'yes'
check cwd '{"cwd":""}' ''
check cwd '' ''

section="escapes"
check cwd '{"cwd":"a\"b"}' 'a"b'
check cwd '{"cwd":"a\\b"}' 'a\b'
check cwd '{"cwd":"a\\nb"}' 'a\nb'
check cwd '{"cwd":"a\\"}' 'a\'
check cwd '{"cwd":"a\\\""}' 'a\"'
check cwd '{"cwd":"\"a\""}' '"a"'
check cwd '{"cwd":"a\/b"}' 'a/b'
check cwd '{"cwd":"a\nb\tc\rd"}' "$(printf 'a\nb\tc\rd')"
check cwd '{"cwd":"a\bb\fc"}' "$(printf 'a\bb\fc')"
check cwd '{"cwd":"a\n"}' $'a\n' 'a trailing newline is kept'
check cwd '{"cwd":"\u0067it"}' 'git'
check cwd '{"cwd":"\u004A\u004a"}' 'JJ'
check cwd '{"cwd":"\u001b[0m"}' $'\033[0m'
check cwd '{"cwd":"\u00e9"}' 'é'
check cwd '{"cwd":"/a/\u65e5\u672c"}' '/a/日本'
check cwd '{"cwd":"\ud83d\ude00!"}' '😀!'
check cwd '{"cwd":"\ud800x"}' '?x'
check cwd '{"cwd":"\\u0041"}' '\u0041'
check cwd '{"cwd":"日本語 😀"}' '日本語 😀'

# A UTF-8 locale may collate "cwd" equal to "cwdあ" (macOS awk does).
section="locale"
for l in C en_US.UTF-8 ja_JP.UTF-8 C.UTF-8; do
  got=$(printf '%s' '{"cwdあ":"no","cwd":"yes"}' | LC_ALL=$l json_get cwd 2>/dev/null)
  [ "$got" = yes ] && ok || ng "LC_ALL=$l: want [yes], got [$got]"
done

# --- 2. random objects, compared with jq -------------------------------------

section="jq"
if command -v jq >/dev/null 2>&1; then
  # One object per line, with no duplicate keys and no lone surrogates
  # (jq rejects both).
  LC_ALL=C awk -v n=200 'BEGIN {
    srand(20261029)
    nk = split("command cwd file_path tool_input tool_name a edits", K, " ")
    np = split("git push|gh pr create|x|日本|😀| |\\\"|\\\\|\\\\\\\"|\\n|\\t|\\r|\\b|\\f|\\/|\\u0067|\\u00e9|\\u65e5|\\ud83d\\ude00|{|}|[|]|:|,|\\\\n|\\\\u0041", P, "|")
    for (i = 0; i < n; i++) print obj(0)
  }
  function r(k) { return int(rand() * k) + 1 }
  function str(   s, m, j) { s = ""; m = r(6) - 1; for (j = 0; j < m; j++) s = s P[r(np)]; return "\"" s "\"" }
  function val(d,   t) {
    t = r(d < 3 ? 8 : 5)
    if (t <= 3) return str()
    if (t == 4) return r(100)
    if (t == 5) return (r(2) == 1 ? "true" : "null")
    if (t <= 7) return obj(d + 1)
    return "[" str() "," obj(d + 1) "," r(9) "]"
  }
  function obj(d,   s, m, j, used, k) {
    s = "{"; m = r(4); split("", used)
    for (j = 0; j < m; j++) {
      do k = K[r(nk)]; while (k in used)
      used[k] = 1
      s = s (j ? "," : "") "\"" k "\":" val(d)
    }
    return s "}"
  }' > "$tmp/random.jsonl"
  paths="command cwd tool_input.command tool_input.cwd a.file_path tool_input.a.command edits.cwd"
  # One jq for all: the value at every path of every line, each ended by NUL.
  jq -j --arg ps "$paths" '($ps | split(" ")[]) as $p
    | (try (getpath($p | split(".")) | if type == "string" then . else "" end) catch "") + "\u0000"' \
    "$tmp/random.jsonl" > "$tmp/want"
  bad=0; i=0
  exec 3< "$tmp/want"
  while IFS= read -r line; do
    i=$((i + 1))
    for p in $paths; do
      IFS= read -r -d '' want <&3
      got=$(get "$p" "$line"; printf x); got=${got%x}
      if [ "$want" = "$got" ]; then ok; else
        bad=$((bad + 1)); [ $bad -le 5 ] && ng "line $i ($p): $line
      jq [$want] json_get [$got]"
      fi
    done
  done < "$tmp/random.jsonl"
  exec 3<&-
  [ $bad -gt 5 ] && ng "... $bad mismatches in all"
else
  echo "skip  [jq] jq is not installed"
fi

# --- 3. long inputs ----------------------------------------------------------

# Quadratic time (a regex gsub over the whole input in BWK awk) takes minutes
# here; linear time takes about a second.
section="long"
# within <seconds> <what> <command...>: the command finishes in time.
within() {
  local limit=$1 what=$2 start end; shift 2
  start=$(date +%s); "$@"; end=$(date +%s)
  if [ $((end - start)) -le "$limit" ]; then ok; else ng "$what took $((end - start))s (limit ${limit}s)"; fi
}
# A 4 MB heredoc: 400,000 lines with escaped quotes and backslashes.
awk 'BEGIN { printf "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > f <<EOF\\n"
  for (i = 0; i < 400000; i++) printf "echo \\\"a\\\\b\\\"\\n"
  printf "EOF\"}}" }' > "$tmp/heredoc.json"
awk 'BEGIN { printf "cat > f <<EOF\n"; for (i = 0; i < 400000; i++) printf "echo \"a\\b\"\n"; printf "EOF" }' > "$tmp/heredoc.want"
long_cmd() { json_get tool_input.command < "$tmp/heredoc.json" > "$tmp/heredoc.got"; }
within 15 "a 4 MB command" long_cmd
cmp -s "$tmp/heredoc.got" "$tmp/heredoc.want" && ok || ng "the 4 MB command is read as written"
# 20,000 strings and no notebook_path: the whole input is walked.
awk 'BEGIN { printf "{\"tool_name\":\"MultiEdit\",\"tool_input\":{\"edits\":["
  for (i = 0; i < 10000; i++) printf "%s{\"old_string\":\"a\\\"b\",\"new_string\":\"c\"}", (i ? "," : "")
  printf "],\"file_path\":\"/x\"}}" }' > "$tmp/many.json"
many() { json_get tool_input.notebook_path < "$tmp/many.json" > "$tmp/many.got"; }
within 15 "20,000 strings" many
[ ! -s "$tmp/many.got" ] && ok || ng "no notebook_path in the many-strings input"

echo "json-get: $pass passed, $fail failed"
[ $fail -eq 0 ]
