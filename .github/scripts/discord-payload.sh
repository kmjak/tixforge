#!/usr/bin/env bash
# Build the Discord message for a GitHub Release made by release-please: its
# title, link and notes (the CHANGELOG section of that version).
#
#   discord-payload.sh <tag>
#
# Prints the Discord webhook JSON. Needs jq and gh (GH_TOKEN, and GH_REPO or a
# GitHub remote).
set -euo pipefail

tag=$1
gh release view "$tag" --json name,body,url \
  | jq '
  # Discord allows 4096 characters in a description; keep whole lines.
  def fit($max):
    reduce split("\n")[] as $l ({out: [], len: 0, cut: false};
      if .cut then .
      elif .len + ($l | length) + 1 <= $max then {out: (.out + [$l]), len: (.len + ($l | length) + 1), cut: false}
      else .cut = true end)
    | (.out | join("\n")) + (if .cut then "\n…" else "" end);
  {
    username: "tixforge 更新通知",
    embeds: [{
      title: .name,
      url: .url,
      color: 8311585,
      description: ((.body // "") | if . == "" then "変更点の記載はありません。" else fit(3800) end)
    }]
  }'
