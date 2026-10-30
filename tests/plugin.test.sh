#!/usr/bin/env bash
# Tests for the plugin's files other than the scripts:
#   1. the manifests and hooks.json are valid JSON with the keys Claude Code needs
#   2. every script a hook runs exists
#   3. every plugin path the skills, references, agents and README name exists
#      (a renamed file is otherwise read by Claude as missing, silently)
#
# Needs jq. Usage: bash tests/plugin.test.sh
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

pass=0
fail=0
section=""
ok() { pass=$((pass + 1)); }
ng() {
  fail=$((fail + 1))
  printf 'FAIL  [%s] %s\n' "$section" "$1"
}

# --- manifests ---------------------------------------------------------------
section="manifests"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  jq empty "$f" 2> /dev/null && ok || ng "$f is valid JSON"
done
jq -e '.name == "tixforge"' .claude-plugin/plugin.json > /dev/null && ok || ng "plugin.json: name is tixforge"
jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' .claude-plugin/plugin.json > /dev/null && ok \
  || ng "plugin.json: version is x.y.z"
jq -e '.plugins | map(.name) | index("tixforge") != null' .claude-plugin/marketplace.json > /dev/null && ok \
  || ng "marketplace.json lists tixforge"

# --- hooks -------------------------------------------------------------------
section="hooks"
cmds=$(jq -r '.hooks[][].hooks[].command' hooks/hooks.json)
[ -n "$cmds" ] && ok || ng "hooks.json has commands"
while IFS= read -r c; do
  [ -n "$c" ] || continue
  p=$(printf '%s\n' "$c" | sed -n 's|.*"\${CLAUDE_PLUGIN_ROOT}"/\([^ "]*\).*|\1|p')
  if [ -z "$p" ]; then
    ng "hook command runs a file under \${CLAUDE_PLUGIN_ROOT}: $c"
  elif [ -f "$p" ]; then
    ok
  else
    ng "hook command runs a missing file: $p"
  fi
done <<< "$cmds"

# --- paths named in the documents ---------------------------------------------
# <plugin>/x, ${CLAUDE_PLUGIN_ROOT}/x and bare skills/, references/, scripts/,
# templates/, agents/ paths are relative to the plugin root; <scripts>/x is
# scripts/x. Only full file names are checked (no <placeholder>, * or {}).
section="references"
docs=$(git ls-files 'skills/*.md' 'references/*.md' 'agents/*.md' README.md)
[ -n "$docs" ] && ok || ng "documents found"
refs=$(
  # shellcheck disable=SC2086 # $docs is a list of paths without spaces
  grep -oE '(<plugin>/|<scripts>/|\$\{CLAUDE_PLUGIN_ROOT\}/)?(skills|references|scripts|templates|agents)?/?[A-Za-z0-9_./-]+\.(md|sh|yml|json)' $docs \
    | sed -E 's|^[^:]*:||; s|^(<plugin>/\|\$\{CLAUDE_PLUGIN_ROOT\}/)||; s|^<scripts>/|scripts/|' \
    | grep -E '^(skills|references|scripts|templates|agents)/' | sort -u
)
n=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  n=$((n + 1))
  [ -e "$p" ] && ok || ng "a document names a missing file: $p ($(grep -lF "$p" $docs | tr '\n' ' '))"
done <<< "$refs"
[ "$n" -gt 20 ] && ok || ng "the documents name plugin files ($n found)"

echo "plugin: $pass passed, $fail failed"
[ $fail -eq 0 ]
