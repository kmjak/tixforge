#!/usr/bin/env bash
# Run the verification commands of .tixforge/config.yml (`commands`), in
# the order written, from the repository root, and print one line that
# tixforge records as is in the Implementation Log:
#
#   Verification @ a1b2c3d: test pass, lint fail
#
# `+dirty` after the hash means uncommitted changes were verified, so the
# line does not stand for that commit. That is also the case when a command
# changed the working tree (a formatter with --fix, code generation): the
# later commands checked a tree that is not the commit, so `+dirty` is added
# and the files that changed are listed after the line. Each command's
# output goes to a log file (listed for failures), so only the failures need
# to be read.
#
#   verify.sh
#
# Exit: 0 all passed (or `commands: {}`), 1 something failed,
#       3 `commands` is missing from the config (an older /tixforge:project init).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

top=$(flow_top)
conf=$(flow_config "$top")

if ! cfg_has commands "$conf"; then
  echo ".tixforge/config.yml に commands がありません（/tixforge:project init の再実行で追加できます）" >&2
  exit 3
fi

# tree_state: the changed files and a checksum of their changes, to notice a
# command that rewrites files.
tree_state() {
  git -C "$top" status --porcelain 2>/dev/null
  git -C "$top" diff HEAD --binary 2>/dev/null | cksum
}

hash=$(git -C "$top" rev-parse --short HEAD 2>/dev/null || echo none)
[ -n "$(git -C "$top" status --porcelain 2>/dev/null)" ] && hash="${hash}+dirty"
before=$(tree_state)

logdir="$(git -C "$top" rev-parse --absolute-git-dir 2>/dev/null || echo "$top")/tixforge/verify"
mkdir -p "$logdir"

tab=$(printf '\t')
results=""; failed=""; ran=0
while IFS="$tab" read -r key command; do
  [ -n "$key" ] || continue
  ran=1
  log="$logdir/$key.log"
  if (cd "$top" && bash -c "$command") < /dev/null > "$log" 2>&1; then
    results="${results}${results:+, }$key pass"
  else
    results="${results}${results:+, }$key fail"
    failed="${failed}log $key: $log
"
  fi
done <<EOF
$(cfg_map commands "$conf")
EOF

if [ $ran -eq 0 ]; then
  echo "Verification @ $hash: 検証コマンドなし"
  exit 0
fi
changed=""
if [ "$(tree_state)" != "$before" ]; then
  case $hash in *+dirty) ;; *) hash="${hash}+dirty" ;; esac
  changed=$(git -C "$top" status --porcelain 2>/dev/null)
fi
echo "Verification @ $hash: $results"
if [ -n "$changed" ]; then
  echo "検証コマンドが作業ツリーを変えました（commit と違う内容を検証したことになります）:"
  printf '%s\n' "$changed"
fi
[ -z "$failed" ] && exit 0
printf '%s' "$failed"
exit 1
