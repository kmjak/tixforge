#!/usr/bin/env bash
# Build the Discord message for a release: the version change of
# .claude-plugin/plugin.json and every pull request merged into the default
# branch since the previous version was set.
#
#   release-payload.sh <before> <after>
#
# <before> and <after> are the commits of a push to the default branch.
# Prints the Discord webhook JSON, or nothing (exit 0) when the version did
# not change. Needs git history (fetch-depth: 0), jq and gh (GH_TOKEN, and
# GH_REPO or a GitHub remote).
set -euo pipefail

before=$1 after=$2
file=.claude-plugin/plugin.json

version_at() { git show "$1:$file" 2> /dev/null | jq -r '.version // empty' 2> /dev/null || true; }
name_at() { git show "$1:$file" 2> /dev/null | jq -r '.name // empty' 2> /dev/null || true; }

new=$(version_at "$after")
old=""
git cat-file -e "$before^{commit}" 2> /dev/null && old=$(version_at "$before")
[ -n "$new" ] && [ "$new" != "$old" ] || exit 0
name=$(name_at "$after")

# The previous release point: where the default branch got the old version
# (the merge of the PR that bumped it), found by walking back its first
# parents while the version stays the same. PRs up to that point belonged
# to the previous release. Without an old version, the whole history.
since=""
if [ -n "$old" ]; then
  for c in $(git log --first-parent --format=%H "$before"); do
    [ "$(version_at "$c")" = "$old" ] || break
    since=$c
  done
fi
range=${since:+$since..}$after

# Pull requests of the commits on the default branch in the range, merged
# into it (merge, squash and rebase merges all map back to their PR).
default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
prs=$(
  for sha in $(git log --first-parent --format=%H "$range"); do
    # A commit GitHub does not know (not pushed) has no PR: skip it.
    out=$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" \
      --jq ".[] | select(.merged_at != null and .base.ref == \"$default\")
            | [.number, .title, .user.login, .html_url] | @tsv" 2> /dev/null) || continue
    if [ -n "$out" ]; then printf '%s\n' "$out"; fi
  done | sort -t "$(printf '\t')" -k1,1n -u
)

jq -n --arg name "$name" --arg old "$old" --arg new "$new" --arg prs "$prs" \
  --arg repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" '
  def clip($max): if length > $max then .[0:$max - 1] + "…" else . end;
  ($prs | split("\n") | map(select(. != "") | split("\t")
    | "• [#\(.[0]) \(.[1] | clip(120))](\(.[3])) — @\(.[2])")) as $lines
  # Discord allows 4096 characters in a description; keep whole lines.
  | (reduce $lines[] as $l ({out: [], len: 0};
      if .len + ($l | length) + 1 <= 3800 then {out: (.out + [$l]), len: (.len + ($l | length) + 1)} else . end)) as $fit
  | ($lines | length) as $all
  | {
      username: "tixforge 更新通知",
      embeds: [{
        title: ("\($name) " + (if $old == "" then "v\($new)" else "v\($old) → v\($new)" end)),
        url: "https://github.com/\($repo)",
        color: 8311585,
        description: (if $all == 0 then "マージされた PR はありません。"
                      else ($fit.out | join("\n"))
                        + (if ($fit.out | length) < $all then "\nほか \($all - ($fit.out | length)) 件" else "" end)
                      end),
        fields: [{name: "マージされた PR", value: "\($all) 件", inline: true}],
        footer: {text: $repo}
      }]
    }'
