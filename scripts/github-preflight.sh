#!/usr/bin/env bash
# The check before any GitHub operation of tixforge: gh is installed and
# logged in, and the repository is known to gh (a GitHub remote, including
# SSH host aliases and GitHub Enterprise hosts gh is logged in to).
#
#   github-preflight.sh
#
# Prints `ok: <owner>/<repo>` and exits 0, or prints what is missing and
# what the user can do, and exits:
#   3 gh is not installed   4 not logged in   5 not a GitHub repository gh knows
set -u

if ! command -v gh > /dev/null 2>&1; then
  echo "gh（GitHub CLI）がありません。インストールしてください（例：brew install gh）。"
  exit 3
fi
if ! gh auth status > /dev/null 2>&1; then
  echo "gh にログインしていません。ユーザーが自分で ! gh auth login を実行する必要があります（対話式のため Claude は実行できない）。"
  exit 4
fi
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2> /dev/null) || {
  echo "このディレクトリを GitHub のリポジトリとして特定できません（origin が GitHub を指していない、またはそのホストに gh でログインしていない）。"
  exit 5
}
echo "ok: $repo"
