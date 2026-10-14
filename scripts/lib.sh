# Shared helpers for the tixforge scripts. Source it:
#   . "$(cd "$(dirname "$0")" && pwd)/lib.sh"
# Portable to macOS bash 3.2 and BWK awk (no gawk, no yq).

flow_top() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

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
ID_PAD=6
is_ticket_id() { printf '%s\n' "$1" | grep -Eq '^(LT|GT)-(0[0-9]{5}|[1-9][0-9]{5,})$'; }
id_kind() { printf '%s\n' "${1%%-*}"; }                       # LT | GT
# issue_of <id>: the issue number of a GT id, or nothing.
issue_of() { case "$1" in GT-*) printf '%s\n' "${1#GT-}" | sed 's/^0*//' ;; esac; }

# msg <key>: a fixed message in the document language, from messages.yml
# next to the scripts (English when the language has none).
msg() {
  local lang file v
  file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/messages.yml"
  lang=$(cfg language); lang=${lang:-ja}
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

flow_now() { date '+%Y-%m-%d %H:%M'; }

# is_open_status <status>: a run that is neither done nor canceled.
is_open_status() { case "$1" in done|canceled|'') return 1 ;; *) return 0 ;; esac; }
