# shellcheck shell=bash
# Shared helpers for the tixforge scripts. Source it:
#   . "$(cd "$(dirname "$0")" && pwd)/lib.sh"
# Portable to macOS bash 3.2 and BWK awk (no gawk, no yq).

flow_top() { git rev-parse --show-toplevel 2> /dev/null || pwd; }

# Everything tixforge keeps in a project lives under .tixforge/:
#   .tixforge/config.yml        settings (in git, shared)
#   .tixforge/.gitignore        keeps everything else out of git
#   .tixforge/<id>/ticket.md    a ticket (LT: the ticket itself; GT: a working
#                               copy of the issue)
#   .tixforge/<id>/state.md     the run of that ticket
tf_dir() { printf '%s/.tixforge\n' "${1:-$(flow_top)}"; }
flow_config() { printf '%s/config.yml\n' "$(tf_dir "${1:-}")"; }
ticket_file() { printf '%s/%s/ticket.md\n' "$(tf_dir "${2:-}")" "$1"; }
state_file() { printf '%s/%s/state.md\n' "$(tf_dir "${2:-}")" "$1"; }

# ensure_workspace [top]: create .tixforge/.gitignore when it is missing, so
# tickets and runs never show up in git status (only config.yml is tracked).
ensure_workspace() {
  local d
  d=$(tf_dir "${1:-}")
  mkdir -p "$d"
  [ -f "$d/.gitignore" ] || printf '*\n!.gitignore\n!config.yml\n' > "$d/.gitignore"
}

# Ticket ids: LT-<6 digits> for local tickets, GT-<6 digits> for GitHub
# issues (GT-000123 is issue #123). More than 6 digits are written as is.
# shellcheck disable=SC2034 # used by ticket-id.sh
ID_PAD=6
is_ticket_id() { printf '%s\n' "$1" | grep -Eq '^(LT|GT)-(0[0-9]{5}|[1-9][0-9]{5,})$'; }
id_kind() { printf '%s\n' "${1%%-*}"; } # LT | GT
# issue_of <id>: the issue number of a GT id, or nothing.
issue_of() { case "$1" in GT-*) printf '%s\n' "${1#GT-}" | sed 's/^0*//' ;; esac }

# msg <key>: a fixed message in the document language, from messages.yml
# next to the scripts (English when the language has none).
msg() {
  local lang file v
  file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/messages.yml"
  lang=$(cfg language)
  lang=${lang:-ja}
  v=$(cfg "$lang.$1" "$file")
  [ -n "$v" ] || v=$(cfg "en.$1" "$file")
  printf '%s\n' "$v"
}

# The YAML /tixforge:project init writes is flat: top-level keys and one level of
# nesting, one key per line, `# comments`, optional quotes. Anything richer
# (anchors, multi-line strings, deeper nesting) is not supported. CRLF line
# ends are accepted.
_cfg_awk='
function clean(v,   q, i, rest, r) {
  sub(/^[ \t]+/, "", v)
  q = substr(v, 1, 1)
  if (q == "\"" || q == "\047") {           # quoted: up to the closing quote
    i = index(substr(v, 2), q)
    if (i > 0) {
      rest = substr(v, i + 2); r = rest; sub(/^[ \t]+/, "", r)
      if (r == "" || substr(r, 1, 1) == "#") return substr(v, 2, i - 1)
      # More follows the closing quote ("./run tests.sh" --fast): the quotes
      # belong to the value, so keep them and drop only a trailing comment.
      sub(/[ \t]+#.*$/, "", rest); sub(/[ \t]+$/, "", rest)
      return substr(v, 1, i + 1) rest
    }
  }
  sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
  return v
}
function keyof(s) { sub(/^[ \t]+/, "", s); sub(/:.*/, "", s); return s }
function valof(s) { sub(/^[^:]*:/, "", s); return clean(s) }
{ sub(/\r$/, "") }
/^[ \t]*(#|$)/ { next }
'

# cfg <key> [config-file]: value of "language" or "ticket.tracker".
# Prints nothing when the key is absent.
cfg() {
  local file=${2:-$(flow_config)}
  [ -f "$file" ] || return 0
  awk -v want="$1" "$_cfg_awk"'
    /^[^ \t]/ { parent = keyof($0); if (parent == want) { print valof($0); exit } next }
    $0 !~ /^[ \t]+-/ { if (parent "." keyof($0) == want) { print valof($0); exit } }
  ' "$file"
}

# cfg_has <top-level-key> [config-file]: exit 0 when the key exists.
cfg_has() {
  local file=${2:-$(flow_config)}
  [ -f "$file" ] || return 1
  awk -v want="$1" "$_cfg_awk"'
    /^[^ \t]/ && keyof($0) == want { found = 1; exit }
    END { exit !found }
  ' "$file"
}

# cfg_map <top-level-key> [config-file]: "key<TAB>value" per nested key,
# in file order (commands run in the order they are written).
cfg_map() {
  local file=${2:-$(flow_config)}
  [ -f "$file" ] || return 0
  awk -v want="$1" "$_cfg_awk"'
    /^[^ \t]/ { parent = keyof($0); next }
    parent == want && $0 !~ /^[ \t]+-/ { print keyof($0) "\t" valof($0) }
  ' "$file"
}

# cfg_list <top-level-key> [config-file]: one item per line, from either
# `key: [a, b]` or a block list of `- a` lines.
cfg_list() {
  local file=${2:-$(flow_config)}
  [ -f "$file" ] || return 0
  awk -v want="$1" "$_cfg_awk"'
    /^[^ \t]/ {
      parent = keyof($0)
      if (parent == want) {
        v = valof($0)
        if (v ~ /^\[.*\]$/) {
          v = substr(v, 2, length(v) - 2); n = split(v, a, ",")
          for (i = 1; i <= n; i++) { x = clean(a[i]); if (x != "") print x }
        }
      }
      next
    }
    parent == want && /^[ \t]+-/ { x = $0; sub(/^[ \t]+-/, "", x); x = clean(x); if (x != "") print x }
  ' "$file"
}

# The sections of state.md, in phase order. A section starts only at one of
# these six headings, and not inside a ``` / ~~~ fence: an Approach may quote
# Markdown that has "## " lines of its own. _section_awk defines
# heading_index(line) for awk programs: 1..6 for a section heading, else 0.
# Call it on every line, in order (it tracks the fences).
STATE_SECTIONS="Research|Approach|Plan|Implementation Log|Review|PR"
_section_awk='
function heading_index(line,   m, name, i, n, s) {
  if (!_sec_n) { _sec_n = split("'"$STATE_SECTIONS"'", s, "|"); for (i = 1; i <= _sec_n; i++) _sec_idx[s[i]] = i }
  sub(/\r$/, "", line)
  if (match(line, /^ ? ? ?(```+|~~~+)/)) {
    m = substr(line, RSTART, RLENGTH); sub(/^ +/, "", m)
    if (_fence == "") _fence = m
    else if (substr(m, 1, 1) == substr(_fence, 1, 1) && length(m) >= length(_fence) && substr(line, RSTART + RLENGTH) ~ /^[ \t]*$/) _fence = ""
    return 0
  }
  if (_fence != "" || line !~ /^## /) return 0
  name = substr(line, 4); sub(/[ \t]+$/, "", name)
  return (name in _sec_idx) ? _sec_idx[name] : 0
}
'

# field <state.md> <name>: value from the state file's header table.
field() {
  awk -F'|' -v k="$2" '{ key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key) }
    key == k { v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1"
}

# json_get <path>: the string at a key path ("cwd", "tool_input.command") of
# the JSON object on stdin, with its escapes decoded; nothing when absent or
# not a string. Enough for hook input, so the guard needs no jq.
# - awk runs in the C locale: strings compare byte by byte (a UTF-8 locale may
#   collate "cwd" equal to "cwdあ") and %c writes one byte of UTF-8.
# - It only splits at one-character separators, a single linear pass in every
#   awk; regex gsub / split take quadratic time in BWK awk, and a command can
#   be a long heredoc. BWK awk also splits a one-character separator at every
#   newline, so the input is joined into one line first (raw newlines are
#   only between tokens).
json_get() {
  LC_ALL=C awk -v want="$1" '
    function is_hex4(h) { return h ~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/ }
    function hex(h,   n, k) {
      h = tolower(h); n = 0
      for (k = 1; k <= 4; k++) n = n * 16 + index("0123456789abcdef", substr(h, k, 1)) - 1
      return n
    }
    function utf8(n) {
      if (n < 128) return n ? sprintf("%c", n) : ""
      if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
      if (n < 65536) return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
      return sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64)
    }
    # odd_tail <s>: 1 when s ends in an odd number of backslashes, that is,
    # the quote after it is escaped.
    function odd_tail(s,   l, n) {
      l = length(s); n = 0
      while (n < l && substr(s, l - n, 1) == "\\") n++
      return n % 2
    }
    # unescape <s>: prints s decoded. After a split at "\", every piece but
    # the first starts with an escape letter, except the one after "\\".
    function unescape(s,   e, m, k, c, h, lo, lit) {
      m = split(s, e, "\\"); printf "%s", e[1]; lit = 0
      for (k = 2; k <= m; k++) {
        if (lit) { printf "%s", e[k]; lit = 0; continue }
        if (e[k] == "") { printf "\\"; lit = 1; continue }
        c = substr(e[k], 1, 1)
        if (c == "u") {
          h = substr(e[k], 2, 4)
          if (!is_hex4(h)) { printf "?%s", substr(e[k], 2); continue }
          h = hex(h)
          # A surrogate pair is two \u in a row: high D800-DBFF, low DC00-DFFF.
          if (h >= 55296 && h < 56320 && length(e[k]) == 5 && k < m && substr(e[k + 1], 1, 1) == "u" && is_hex4(substr(e[k + 1], 2, 4))) {
            lo = hex(substr(e[k + 1], 2, 4))
            if (lo >= 56320 && lo < 57344) {
              k++; printf "%s%s", utf8(65536 + (h - 55296) * 1024 + lo - 56320), substr(e[k], 6)
              continue
            }
          }
          printf "%s%s", (h >= 55296 && h < 57344 ? "?" : utf8(h)), substr(e[k], 6)
          continue
        }
        if (c == "n") c = "\n"; else if (c == "t") c = "\t"; else if (c == "r") c = "\r"
        else if (c == "b") c = "\b"; else if (c == "f") c = "\f"
        printf "%s%s", c, substr(e[k], 2)
      }
    }
    { buf = buf $0 " " }
    END {
      # Split at ": the pieces alternate between the text between strings and
      # a string, which goes on over pieces that end at an escaped quote. In
      # the text, { and [ open a level named by the key before it; a string
      # followed by ":" is a key.
      n = split(buf, q, "\""); depth = 0; key = ""; i = 1
      while (1) {
        for (k = 1; k <= length(q[i]); k++) {
          c = substr(q[i], k, 1)
          if (c == "{" || c == "[") { name[++depth] = key; key = "" }
          else if (c == "}" || c == "]") { depth--; key = "" }
        }
        if (++i > n) break
        for (j = i; j < n && odd_tail(q[j]); j++) ;
        if (q[j + 1] ~ /^[ \t\r]*:/) key = (j == i ? q[i] : "")
        else {
          path = ""
          for (k = 2; k <= depth; k++) path = path name[k] "."
          if (path key == want) {
            for (k = i; k < j; k++) { unescape(substr(q[k], 1, length(q[k]) - 1)); printf "\"" }
            unescape(q[j]); exit
          }
          key = ""
        }
        if ((i = j + 1) > n) break
      }
    }
  '
}

flow_now() { date '+%Y-%m-%d %H:%M'; }

# is_open_status <status>: a run that is neither done nor canceled.
is_open_status() { case "$1" in done | canceled | '') return 1 ;; *) return 0 ;; esac }
